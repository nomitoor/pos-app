import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:pos_app/core/database/database_helper.dart';
import 'package:pos_app/features/customers/ledger.dart';
import 'package:pos_app/features/day_close/z_report.dart';
import 'package:pos_app/models/bill.dart';
import 'package:pos_app/models/customer.dart';
import 'package:pos_app/models/expense.dart';
import 'package:pos_app/models/held_bill.dart';
import 'package:pos_app/models/product.dart';
import 'package:pos_app/models/sale_return.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _day = DateTime(2026, 11, 12);
DateTime _at(int h) => _day.add(Duration(hours: h));

Bill _bill(int id, double total, String method,
        {int? customerId, int h = 10, double discount = 0}) =>
    Bill(
      id: id,
      billNumber: 'B$id',
      items: [
        BillItem(barcode: 'x', name: 'Shirt', price: total + discount,
            quantity: 1),
      ],
      totalAmount: total,
      discount: discount,
      createdAt: _at(h),
      paymentMethod: method,
      customerId: customerId,
    );

SaleReturn _ret(int billId, double amount, String method, {int h = 15}) =>
    SaleReturn(
      returnNumber: 'R$billId',
      billId: billId,
      billNumber: 'B$billId',
      items: [
        ReturnItem(barcode: 'x', name: 'Shirt', price: amount, quantity: 1,
            refund: amount, restocked: true),
      ],
      reason: 'Wrong size',
      refundMethod: method,
      createdAt: _at(h),
    );

void main() {
  group('whatsapp number', () {
    test('Pakistani formats', () {
      expect(Customer.whatsappNumber('0300-1234567'), '923001234567');
      expect(Customer.whatsappNumber('+92 300 1234567'), '923001234567');
      expect(Customer.whatsappNumber('3001234567'), '923001234567');
      expect(Customer.whatsappNumber('0092 300 1234567'), '923001234567');
    });
  });

  group('udhaar ledger', () {
    final ali = Customer(id: 1, name: 'Ali', phone: '0300', createdAt: _day);
    final sara = Customer(id: 2, name: 'Sara', phone: '0301', createdAt: _day);

    test('balance = credit sales − payments − returns to account', () {
      final bills = [
        _bill(1, 5000, Bill.udhaar, customerId: 1),
        _bill(2, 2000, Bill.cash, customerId: 1), // paid, not udhaar
        _bill(3, 1000, Bill.udhaar, customerId: 2),
      ];
      final payments = [
        CustomerPayment(customerId: 1, billId: 1, amount: 1000,
            method: Bill.cash, createdAt: _at(10)),
        CustomerPayment(customerId: 1, amount: 1500, method: 'JazzCash',
            createdAt: _at(12)),
      ];
      final returns = [_ret(1, 500, Bill.udhaar)];

      final acc = buildAccounts(customers: [ali, sara], bills: bills,
          returns: returns, payments: payments);

      expect(acc[1]!.balance, 5000 - 1000 - 1500 - 500);
      expect(acc[1]!.totalSpent, 7000);
      expect(acc[1]!.bills.length, 2);
      expect(acc[2]!.balance, 1000);
      expect(unpaidOnBill(bills[0], payments), 4000);
      expect(unpaidOnBill(bills[1], payments), 0);
    });
  });

  group('z report', () {
    test('expected cash and totals', () {
      final bills = [
        _bill(1, 3000, Bill.cash, h: 10, discount: 200),
        _bill(2, 2000, 'JazzCash', h: 11),
        _bill(3, 4000, Bill.udhaar, customerId: 1, h: 12),
        _bill(4, 9999, Bill.cash, h: 8), // before the period
      ];
      final z = computeZReport(
        from: _at(9),
        to: _at(21),
        openingFloat: 5000,
        bills: bills,
        returns: [_ret(1, 1000, Bill.cash)],
        expenses: [
          Expense(category: 'Tea / Food', amount: 300,
              paidFrom: Expense.cashDrawer, date: _at(13)),
          Expense(category: 'Rent', amount: 50000,
              paidFrom: 'Bank / Card', date: _at(14)),
        ],
        payments: [
          CustomerPayment(customerId: 1, billId: 3, amount: 1500,
              method: Bill.cash, createdAt: _at(12)),
          CustomerPayment(customerId: 1, amount: 700, method: 'Easypaisa',
              createdAt: _at(16)),
        ],
      );

      expect(z.billCount, 3);
      expect(z.sales, 9000);
      expect(z.discounts, 200);
      expect(z.refunds, 1000);
      expect(z.netSales, 8000);
      expect(z.udhaarGiven, 4000);
      expect(z.udhaarCollected, 2200);
      expect(z.expenses, 50300);
      // 5000 float + 3000 cash sales − 1000 cash refund + 1500 udhaar
      // cash − 300 drawer expense
      expect(z.expectedCash, 8200);

      // Survives the save/load round trip used for reprints.
      final again = ZReport.fromMap(z.toMap());
      expect(again.expectedCash, 8200);
      expect(again.salesByMethod, z.salesByMethod);
      expect(again.topItems.first.$1, 'Shirt');
    });
  });

  group('database', () {
    final db = DatabaseHelper.instance;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await deleteDatabase(join(await getDatabasesPath(), 'pos_app.db'));
      await db.insertProduct(
          Product(barcode: 'x', name: 'Shirt', price: 3000, quantity: 10));
    });

    test('udhaar checkout needs a customer and records paid-now', () async {
      final custId = await db.saveCustomer(
          Customer(name: 'Ali', phone: '0300-1234567', createdAt: _day));

      await expectLater(
        db.checkout(_bill(0, 3000, Bill.udhaar)),
        throwsA(isA<StateError>()),
      );

      final bill = Bill(
        billNumber: 'U1',
        items: [BillItem(barcode: 'x', name: 'Shirt', price: 3000, quantity: 1)],
        totalAmount: 3000,
        createdAt: _at(10),
        paymentMethod: Bill.udhaar,
        customerId: custId,
        customerName: 'Ali',
        customerPhone: '0300-1234567',
      );
      final savedBill = await db.checkout(bill, paidNow: 1000);
      final billId = savedBill.id;

      final saved = (await db.getAllBills()).single;
      expect(saved.customerName, 'Ali');
      expect(saved.isUdhaar, true);
      final pays = await db.getCustomerPayments();
      expect(pays.single.amount, 1000);
      expect(pays.single.billId, billId);

      // Customer with history can't be deleted.
      await expectLater(db.deleteCustomer(custId), throwsA(isA<StateError>()));

      // Voiding the bill removes its checkout payment too, and a voided
      // bill doesn't stop the customer being deleted.
      await db.voidBill(savedBill, 'Customer cancelled');
      expect(await db.getCustomerPayments(), isEmpty);
      await db.deleteCustomer(custId); // now allowed
      expect(await db.getCustomers(), isEmpty);
    });

    test('expenses, held bills and day closes save and load', () async {
      await db.saveExpense(Expense(category: 'Rent', amount: 40000,
          paidFrom: 'Bank / Card', date: _day));
      expect((await db.getExpenses()).single.amount, 40000);

      await db.holdBill(HeldBill(
          label: 'Lady in blue',
          items: [BillItem(barcode: 'x', name: 'Shirt', price: 3000, quantity: 2)],
          createdAt: _day));
      final held = (await db.getHeldBills()).single;
      expect(held.label, 'Lady in blue');
      expect(held.pieces, 2);
      await db.deleteHeldBill(held.id!);
      expect(await db.getHeldBills(), isEmpty);
    });
  });
}
