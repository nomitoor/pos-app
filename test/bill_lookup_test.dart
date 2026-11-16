import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/bills/bill_lookup.dart';
import 'package:pos_app/models/bill.dart';
import 'package:pos_app/models/sale_return.dart';

void main() {
  final bills = [
    Bill(
      id: 1,
      billNumber: 'BILL-7F3A2C1D',
      items: [BillItem(barcode: 'h', name: 'Classic Hoodie', price: 2000, quantity: 1)],
      totalAmount: 2000,
      createdAt: DateTime(2026, 11, 12),
      paymentMethod: 'JazzCash',
    ),
    Bill(
      id: 2,
      billNumber: 'BILL-00000002',
      items: [BillItem(barcode: 't', name: 'Trouser', price: 1500, quantity: 1)],
      totalAmount: 1500,
      createdAt: DateTime(2026, 11, 12),
    ),
  ];
  SaleReturn ret(String no, int? billId) => SaleReturn(
        returnNumber: no,
        billId: billId,
        billNumber: 'BILL-7F3A2C1D',
        items: const [],
        reason: 'Wrong size',
        refundMethod: 'Cash',
        createdAt: DateTime(2026, 11, 13),
      );

  test('finds a bill by its scanned invoice number', () {
    final r = findBillByCode('BILL-7F3A2C1D', bills, const []);
    expect(r.bill!.id, 1);
    expect(r.viaReturn, isNull);
  });

  test('ignores case and surrounding spaces', () {
    expect(findBillByCode('  bill-7f3a2c1d \n', bills, const []).bill!.id, 1);
  });

  test('credit note barcode opens the original bill', () {
    final r = findBillByCode('RET-AAAA1111', bills, [ret('RET-AAAA1111', 1)]);
    expect(r.bill!.id, 1);
    expect(r.viaReturn!.returnNumber, 'RET-AAAA1111');
  });

  test('credit note whose bill was deleted', () {
    final r = findBillByCode('RET-B', bills, [ret('RET-B', null)]);
    expect(r.bill, isNull);
    expect(r.viaReturn, isNotNull);
  });

  test('unknown code finds nothing', () {
    final r = findBillByCode('8964000123456', bills, const []);
    expect(r.bill, isNull);
    expect(r.viaReturn, isNull);
  });

  test('search box matches number, item, method and amount', () {
    bool m(String q) => billMatches(bills[0], q);
    expect(m('7f3a'), true);
    expect(m('hoodie'), true);
    expect(m('jazz'), true);
    expect(m('2000'), true);
    expect(m('trouser'), false);
    expect(m(''), true);
  });
}
