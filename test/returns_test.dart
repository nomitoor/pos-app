import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:pos_app/core/database/database_helper.dart';
import 'package:pos_app/features/insights/insights_data.dart';
import 'package:pos_app/features/returns/providers/returns_provider.dart';
import 'package:pos_app/models/bill.dart';
import 'package:pos_app/models/product.dart';
import 'package:pos_app/models/sale_return.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ReturnItem _ri(BillItem i, int qty, Bill bill, {bool restock = true}) =>
    ReturnItem(
      barcode: i.barcode,
      name: i.name,
      price: i.price,
      quantity: qty,
      refund: refundFor(bill, i, qty),
      restocked: restock,
      size: i.size,
      costPrice: i.costPrice,
    );

SaleReturn _ret(Bill bill, List<ReturnItem> items,
        {String reason = 'Wrong size', DateTime? at}) =>
    SaleReturn(
      returnNumber: 'RET-${items.hashCode}',
      billId: bill.id,
      billNumber: bill.billNumber,
      items: items,
      reason: reason,
      refundMethod: 'Cash',
      createdAt: at ?? DateTime(2026, 11, 12, 16),
    );

void main() {
  final db = DatabaseHelper.instance;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await deleteDatabase(join(await getDatabasesPath(), 'pos_app.db'));
  });

  test('refund includes the bill discount share', () {
    final item = BillItem(barcode: 'a', name: 'A', price: 1000, quantity: 2);
    final bill = Bill(
        billNumber: 'B', items: [item], totalAmount: 1800,
        createdAt: DateTime(2026), discount: 200);
    expect(refundFor(bill, item, 1), closeTo(900, 0.001));
  });

  group('database', () {
    late Bill bill;

    setUpAll(() async {
      await db.insertProduct(Product(
          barcode: 'r1', name: 'Hoodie', price: 2000, quantity: 10,
          size: 'Medium', costPrice: 1200));
      await db.checkout(Bill(
        billNumber: 'BILL-R',
        items: [
          BillItem(barcode: 'r1', name: 'Hoodie', price: 2000, quantity: 3,
              size: 'Medium', costPrice: 1200),
        ],
        totalAmount: 6000,
        createdAt: DateTime(2026, 11, 12, 10),
        paymentMethod: 'Cash',
      ));
      bill = (await db.getAllBills()).single;
    });

    test('return restocks and is saved', () async {
      expect((await db.getProductByBarcode('r1'))!.quantity, 7);
      await db.insertReturn(bill, _ret(bill, [_ri(bill.items[0], 1, bill)]));
      expect((await db.getProductByBarcode('r1'))!.quantity, 8);
      final r = (await db.getAllReturns()).single;
      expect(r.refundAmount, 2000);
      expect(r.items.single.restocked, true);
      expect(await db.returnedQtyForBill(bill.id!), {'r1': 1});
    });

    test('damaged item is not restocked', () async {
      await db.insertReturn(bill,
          _ret(bill, [_ri(bill.items[0], 1, bill, restock: false)],
              reason: 'Defective / damaged'));
      expect((await db.getProductByBarcode('r1'))!.quantity, 8);
    });

    test('cannot return more than was sold', () async {
      // 3 sold, 2 already returned → 1 left.
      await expectLater(
        db.insertReturn(bill, _ret(bill, [_ri(bill.items[0], 2, bill)])),
        throwsA(isA<StateError>()),
      );
      expect((await db.getAllReturns()).length, 2);
      expect((await db.getProductByBarcode('r1'))!.quantity, 8);
    });

    test('bill with returns cannot be edited', () async {
      await expectLater(
        db.updateBill(bill, [
          BillItem(barcode: 'r1', name: 'Hoodie', price: 2000, quantity: 3),
        ]),
        throwsA(isA<StateError>()),
      );
    });

    test('bill with returns cannot be voided', () async {
      await expectLater(
        db.voidBill(bill, 'Customer cancelled'),
        throwsA(isA<StateError>()),
      );
      expect((await db.getBillById(bill.id!))!.isVoided, false);
      expect((await db.getAllReturns()).length, 2);
    });
  });

  test('insights: net sales, return rate, reasons and profit', () {
    final now = DateTime(2026, 11, 12, 18);
    final item = BillItem(barcode: 'h', name: 'Hoodie', price: 2000,
        quantity: 4, size: 'Large', costPrice: 1200);
    final bill = Bill(id: 1, billNumber: 'B', items: [item],
        totalAmount: 8000, createdAt: DateTime(2026, 11, 12, 10));
    final returns = [
      _ret(bill, [_ri(item, 1, bill)]), // restocked: lose 800 margin
      _ret(bill, [_ri(item, 1, bill, restock: false)],
          reason: 'Defective / damaged'), // written off: lose 2000
    ];

    final d = computeInsights(
        bills: [bill], products: const [], returns: returns,
        period: InsightPeriod.today, now: now);

    expect(d.revenue, 8000);
    expect(d.refundTotal, 4000);
    expect(d.netRevenue, 4000);
    expect(d.returnCount, 2);
    expect(d.returnRatePct, 50);
    // Sold: 4 × 800 = 3200 profit; minus 800 and 2000.
    expect(d.profit, closeTo(400, 0.001));
    expect(d.returnsByReason.map((s) => s.label).toSet(),
        {'Wrong size', 'Defective / damaged'});
    expect(d.mostReturned.single.qty, 2);
    expect(d.mostReturned.single.returnedQty, 0); // no "100% returned"
    final large = d.bySize.single;
    expect(large.returnedQty, 2);
    expect(large.returnRatePct, 50);
  });
}
