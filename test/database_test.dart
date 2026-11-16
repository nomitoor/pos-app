import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:pos_app/core/database/database_helper.dart';
import 'package:pos_app/models/bill.dart';
import 'package:pos_app/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final db = DatabaseHelper.instance;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await deleteDatabase(join(await getDatabasesPath(), 'pos_app.db'));
  });

  test('duplicate barcode is rejected instead of replacing', () async {
    await db.insertProduct(
        Product(barcode: 'dup', name: 'First', price: 100, quantity: 1));
    await expectLater(
      db.insertProduct(
          Product(barcode: 'dup', name: 'Second', price: 200, quantity: 1)),
      throwsA(isA<DatabaseException>()),
    );
    expect((await db.getProductByBarcode('dup'))!.name, 'First');
  });

  test('checkout stores discount, payment method and cost; backup restores',
      () async {
    await db.insertProduct(Product(
        barcode: 'h1', name: 'Hoodie', price: 2000, quantity: 5,
        size: 'Large', type: 'Hoodie', costPrice: 1200));

    await db.checkout(Bill(
      billNumber: 'BILL-1',
      items: [
        BillItem(barcode: 'h1', name: 'Hoodie', price: 2000, quantity: 2,
            size: 'Large', type: 'Hoodie', costPrice: 1200),
      ],
      totalAmount: 3600,
      createdAt: DateTime(2026, 11, 12, 10),
      discount: 400,
      paymentMethod: 'Easypaisa',
    ));

    final bill = (await db.getAllBills()).single;
    expect(bill.discount, 400);
    expect(bill.paymentMethod, 'Easypaisa');
    expect(bill.items.single.costPrice, 1200);
    expect((await db.getProductByBarcode('h1'))!.quantity, 3);

    // Back up (through JSON, as the real file would), then change data.
    final backup = jsonDecode(jsonEncode(await db.exportAll()))
        as Map<String, dynamic>;
    await db.voidBill(bill, 'Test');
    await db.insertProduct(
        Product(barcode: 'x', name: 'Extra', price: 1, quantity: 1));

    await db.restoreAll(backup);

    final bills = await db.getAllBills();
    expect(bills.single.billNumber, 'BILL-1');
    expect(bills.single.discount, 400);
    expect(await db.getProductByBarcode('x'), isNull);
    final hoodie = (await db.getProductByBarcode('h1'))!;
    expect(hoodie.quantity, 3);
    expect(hoodie.costPrice, 1200);
  });

  test('editing a bill keeps its discount, capped at the new subtotal',
      () async {
    final bill = (await db.getAllBills()).single;
    // Reduce to 1 hoodie (2000): discount 400 still fits.
    await db.updateBill(bill, [
      BillItem(barcode: 'h1', name: 'Hoodie', price: 2000, quantity: 1),
    ]);
    final edited = (await db.getAllBills()).single;
    expect(edited.discount, 400);
    expect(edited.totalAmount, 1600);
    expect((await db.getProductByBarcode('h1'))!.quantity, 4);
  });

  test('restore rejects a file that is not a backup', () async {
    await expectLater(
      db.restoreAll({'hello': 'world'}),
      throwsA(isA<FormatException>()),
    );
  });
}
