import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/day_close/z_report.dart';
import 'package:pos_app/models/bill.dart';
import 'package:pos_app/models/customer.dart';
import 'package:pos_app/models/expense.dart';
import 'package:pos_app/models/sale_return.dart';
import 'package:pos_app/models/shop_settings.dart';
import 'package:pos_app/shared/services/pdf_service.dart';

const _settings = ShopSettings(
  shopName: 'Toor Clothing',
  address: 'Shop 12, Main Market, Gulberg, Lahore',
  phone: '0300-1234567',
  email: 'hello@toorclothing.pk',
  taxNumber: 'NTN 1234567-8',
  terms: 'Exchange within 7 days with original receipt and tags. '
      'No cash refund on sale items.',
);

void main() {
  // Lets the PDF service load the bundled Urban Thread mark.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('amount in words', () {
    expect(PdfService.amountInWords(2000), 'Rupees Two Thousand Only');
    expect(PdfService.amountInWords(3100.5),
        'Rupees Three Thousand One Hundred and Fifty Paisa Only');
    expect(PdfService.amountInWords(1234567),
        'Rupees One Million Two Hundred Thirty-Four Thousand Five Hundred Sixty-Seven Only');
  });

  test('invoice and credit note render (long bills span pages)', () async {
    final bill = Bill(
      billNumber: 'BILL-7F3A2C1D',
      items: [
        BillItem(barcode: 'a', name: 'Classic Hoodie', price: 1000,
            quantity: 2, size: 'Large', type: 'Hoodie', listPrice: 1100,
            promo: 'Buy 2 for Rs 2000'),
        BillItem(barcode: 'b', name: 'Slim Fit Trouser', price: 1800,
            quantity: 1, size: 'Medium', type: 'Trouser'),
        BillItem(barcode: 'c', name: 'Graphic Tee', price: 650,
            quantity: 3, size: 'Small', type: 'T-Shirt'),
      ],
      totalAmount: 5750 - 300, // items after offer (5750) − discount
      discount: 300,
      paymentMethod: 'JazzCash',
      createdAt: DateTime(2026, 11, 12, 15, 42),
    );
    final bytes = await PdfService.buildBillPdf(bill, _settings);
    expect(bytes.length, greaterThan(1000));

    final longBill = Bill(
      billNumber: 'BILL-LONG',
      items: [
        for (var i = 0; i < 45; i++)
          BillItem(barcode: '$i', name: 'Item $i', price: 100, quantity: 1),
      ],
      totalAmount: 4500,
      createdAt: DateTime(2026, 11, 12),
    );
    final longBytes = await PdfService.buildBillPdf(longBill, _settings);

    final ret = SaleReturn(
      returnNumber: 'RET-91B0C2AA',
      billId: 1,
      billNumber: 'BILL-7F3A2C1D',
      items: const [
        ReturnItem(barcode: 'a', name: 'Classic Hoodie', price: 1000,
            quantity: 1, refund: 945.95, restocked: true, size: 'Large',
            type: 'Hoodie'),
      ],
      reason: 'Wrong size',
      refundMethod: 'Cash',
      createdAt: DateTime(2026, 11, 14, 11, 5),
    );
    final retBytes = await PdfService.buildReturnPdf(ret, _settings);

    final udhaarBill = Bill(
      billNumber: 'BILL-UD123456',
      items: [
        BillItem(barcode: 'b', name: 'Slim Fit Trouser', price: 1800,
            quantity: 2, size: 'Medium', type: 'Trouser'),
      ],
      totalAmount: 3600,
      paymentMethod: Bill.udhaar,
      customerId: 1,
      customerName: 'Ali Raza',
      customerPhone: '0300-7654321',
      createdAt: DateTime(2026, 11, 12, 17, 10),
    );
    final udhaarBytes =
        await PdfService.buildBillPdf(udhaarBill, _settings, 1000);

    final z = computeZReport(
      from: DateTime(2026, 11, 12, 9),
      to: DateTime(2026, 11, 12, 21),
      openingFloat: 5000,
      bills: [bill, udhaarBill],
      returns: [ret],
      expenses: [
        Expense(category: 'Tea / Food', amount: 350,
            paidFrom: Expense.cashDrawer, date: DateTime(2026, 11, 12, 13)),
      ],
      payments: [
        CustomerPayment(customerId: 1, amount: 1000, method: Bill.cash,
            createdAt: DateTime(2026, 11, 12, 17, 10)),
      ],
    );
    final zBytes = await PdfService.buildZReportPdf(z, _settings,
        countedCash: 6300, floatKept: 5000, note: 'Rs 50 note torn',
        closedAt: DateTime(2026, 11, 12, 21));
    expect(zBytes.length, greaterThan(1000));

    // Optional: write files for visual inspection.
    final out = Platform.environment['PDF_OUT'];
    if (out != null) {
      File('$out/invoice.pdf').writeAsBytesSync(bytes);
      File('$out/invoice_long.pdf').writeAsBytesSync(longBytes);
      File('$out/credit_note.pdf').writeAsBytesSync(retBytes);
      File('$out/invoice_udhaar.pdf').writeAsBytesSync(udhaarBytes);
      File('$out/z_report.pdf').writeAsBytesSync(zBytes);
    }
  });
}
