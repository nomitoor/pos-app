import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_app/core/database/database_helper.dart';
import 'package:pos_app/features/billing/providers/billing_provider.dart';
import 'package:pos_app/models/product.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late ProviderContainer container;
  const barcode = 'TEST-CART-001';

  setUp(() async {
    // Inserting an existing barcode now fails, so start from a clean row.
    final existing =
        await DatabaseHelper.instance.getProductByBarcode(barcode);
    if (existing != null) {
      await DatabaseHelper.instance.deleteProduct(existing.id!);
    }
    await DatabaseHelper.instance.insertProduct(
      Product(barcode: barcode, name: 'Test Product', price: 10, quantity: 2),
    );
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  test('addItem stops at available stock', () async {
    final notifier = container.read(cartProvider.notifier);
    final product =
        Product(barcode: barcode, name: 'Test Product', price: 10, quantity: 2);

    expect(await notifier.addItem(product), true);
    expect(await notifier.addItem(product), true);
    // stock is 2, third add must be rejected
    expect(await notifier.addItem(product), false);
    expect(notifier.inCartQty(barcode), 2);
  });

  test('decrementItem removes the line once quantity hits zero', () async {
    final notifier = container.read(cartProvider.notifier);
    final product =
        Product(barcode: barcode, name: 'Test Product', price: 10, quantity: 2);

    await notifier.addItem(product);
    notifier.decrementItem(barcode);

    expect(notifier.inCartQty(barcode), 0);
    expect(container.read(cartProvider).any((i) => i.barcode == barcode), false);
  });
}
