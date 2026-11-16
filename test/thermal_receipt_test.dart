import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/printing/printer_settings.dart';
import 'package:pos_app/features/printing/thermal_receipt.dart';
import 'package:pos_app/models/bill.dart';
import 'package:pos_app/models/shop_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final bill = Bill(
    billNumber: 'BILL-TEST01',
    createdAt: DateTime(2026, 11, 16, 14, 30),
    totalAmount: 4300,
    discount: 200,
    paymentMethod: 'Cash',
    customerName: 'Ali',
    items: [
      BillItem(
          barcode: '1', name: 'Denim Jacket', price: 3000, quantity: 1, size: 'L'),
      // Non-Latin name must not crash the printer encoding.
      BillItem(barcode: '2', name: 'کرتا Kurta', price: 750, quantity: 2),
    ],
  );
  const shop = ShopSettings(shopName: 'Urban Thread', phone: '0300 1234567');

  for (final paper in PaperWidth.values) {
    test('builds a ${paper.label} receipt', () async {
      final bytes = await ThermalReceipt.bill(bill, shop, paper);
      final text = latin1.decode(bytes, allowInvalid: true);
      expect(text, contains('Urban Thread'));
      expect(text, contains('BILL-TEST01'));
      expect(text, contains('Denim Jacket (L)'));
      expect(text, contains('Kurta'));
      expect(text, contains('Rs 4,300'));
    });
  }

  test('builds a test slip', () async {
    final bytes = await ThermalReceipt.test(PaperWidth.mm58, 'Urban Thread');
    expect(latin1.decode(bytes, allowInvalid: true), contains('Printer test'));
  });
}
