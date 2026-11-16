import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:pos_app/core/database/database_helper.dart';
import 'package:pos_app/models/design.dart';
import 'package:pos_app/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Product _p(String code, String name, String? size,
        {String? type = 'Hoodie', double price = 2000, int qty = 5}) =>
    Product(barcode: code, name: name, price: price, quantity: qty,
        size: size, type: type);

void main() {
  final db = DatabaseHelper.instance;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await deleteDatabase(join(await getDatabasesPath(), 'pos_app.db'));
  });

  test('size ordering', () {
    final s = ['XXL', 'Small', null, '32', 'Extra Small', 'Free', '28',
        'Medium']..sort(compareSizes);
    expect(s, ['Extra Small', 'Small', 'Medium', 'XXL', '28', '32', 'Free',
        null]);
    expect(shortSize('Extra Large'), 'XL');
    expect(shortSize(null), 'One size');
  });

  test('same name + type share a design; other types do not', () async {
    await db.insertProduct(_p('h-s', 'Classic Hoodie', 'Small'));
    await db.insertProduct(_p('h-m', 'classic hoodie ', 'Medium')); // case/space
    await db.insertProduct(_p('t-s', 'Classic Hoodie', 'Small', type: 'Jacket'));

    final products = await db.getAllProducts();
    final hs = products.firstWhere((p) => p.barcode == 'h-s');
    final hm = products.firstWhere((p) => p.barcode == 'h-m');
    final ts = products.firstWhere((p) => p.barcode == 't-s');
    expect(hs.designId, isNotNull);
    expect(hm.designId, hs.designId);
    expect(ts.designId, isNot(hs.designId));
    expect((await db.getDesigns()).length, 2);
  });

  test('renaming a size moves it; empty designs are removed', () async {
    final ts = (await db.getAllProducts()).firstWhere((p) => p.barcode == 't-s');
    // Jacket renamed to the hoodie design → joins it, jacket design vanishes.
    await db.updateProduct(ts.copyWith(type: 'Hoodie'));
    final designs = await db.getDesigns();
    expect(designs.length, 1);
    final all = await db.getAllProducts();
    expect(all.map((p) => p.designId).toSet().length, 1);
  });

  test('saveDesign adds, updates and removes sizes', () async {
    final id = await db.saveDesign(
      Design(name: 'Slim Trouser', type: 'Trouser', price: 1800,
          costPrice: 1100, createdAt: DateTime(2026)),
      [
        _p('tr-30', 'x', '30', type: null, price: 1800, qty: 4),
        _p('tr-32', 'x', '32', type: null, price: 1800, qty: 6),
      ],
    );
    var sizes = (await db.getAllProducts()).where((p) => p.designId == id);
    expect(sizes.length, 2);
    // Name/type/cost come from the design.
    expect(sizes.every((p) => p.name == 'Slim Trouser' && p.type == 'Trouser'),
        true);
    expect(sizes.first.costPrice, 1100);

    final tr30 = sizes.firstWhere((p) => p.size == '30');
    final tr32 = sizes.firstWhere((p) => p.size == '32');
    final design = (await db.getDesigns()).firstWhere((d) => d.id == id);
    await db.saveDesign(design.copyWith(name: 'Slim Fit Trouser'), [
      tr30.copyWith(quantity: 9),
      _p('tr-34', 'x', '34', type: null, price: 1900, qty: 2),
    ], removeIds: [tr32.id!]);

    sizes = (await db.getAllProducts()).where((p) => p.designId == id);
    expect(sizes.map((p) => p.size).toSet(), {'30', '34'});
    expect(sizes.firstWhere((p) => p.size == '30').quantity, 9);
    expect(sizes.firstWhere((p) => p.size == '34').price, 1900);
    expect(sizes.every((p) => p.name == 'Slim Fit Trouser'), true);
  });

  test('duplicate barcode in a design is rejected, nothing saved', () async {
    final before = (await db.getAllProducts()).length;
    await expectLater(
      db.saveDesign(
        Design(name: 'Tee', type: 'T-Shirt', price: 900, createdAt: DateTime(2026)),
        [_p('h-s', 'x', 'Small', type: null)], // h-s already exists
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect((await db.getAllProducts()).length, before);
    expect((await db.getDesigns()).any((d) => d.name == 'Tee'), false);
  });

  test('stock adjust never goes below zero; deleteDesign removes sizes',
      () async {
    final hs = (await db.getAllProducts()).firstWhere((p) => p.barcode == 'h-s');
    await db.adjustStock(hs.id!, -100);
    expect((await db.getProductByBarcode('h-s'))!.quantity, 0);
    await db.adjustStock(hs.id!, 3);
    expect((await db.getProductByBarcode('h-s'))!.quantity, 3);

    await db.deleteDesign(hs.designId!);
    expect(await db.getProductByBarcode('h-s'), isNull);
    expect(await db.getProductByBarcode('h-m'), isNull);
  });

  test('restoring a backup from before variants groups its products',
      () async {
    final backup = {
      'format': DatabaseHelper.backupFormat,
      'version': 1,
      'tables': {
        'products': [
          {'id': 1, 'barcode': 'a', 'name': 'Polo', 'price': 1200,
              'quantity': 2, 'size': 'Small', 'type': 'Shirt'},
          {'id': 2, 'barcode': 'b', 'name': 'Polo', 'price': 1200,
              'quantity': 3, 'size': 'Large', 'type': 'Shirt'},
        ],
        'bills': [],
        'settings': [],
      },
    };
    await db.restoreAll(backup);
    final designs = await db.getDesigns();
    expect(designs.single.name, 'Polo');
    final products = await db.getAllProducts();
    expect(products.every((p) => p.designId == designs.single.id), true);
  });
}
