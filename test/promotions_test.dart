import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:pos_app/core/database/database_helper.dart';
import 'package:pos_app/features/promotions/promo_engine.dart';
import 'package:pos_app/models/bill.dart';
import 'package:pos_app/models/product.dart';
import 'package:pos_app/models/promotion.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

BillItem _item(String code, double price, int qty, {String? type}) =>
    BillItem(barcode: code, name: code, price: price, quantity: qty, type: type);

const _twoFor2000 = Promotion(
  name: '2 for 2000',
  kind: PromoKind.bundle,
  buyQty: 2,
  value: 2000,
  scope: PromoScope.products,
  barcodes: ['shirt'],
);

void main() {
  final now = DateTime(2026, 11, 12, 12);

  test('user example: 2 × 1100 with "buy 2 for 2000" = 2000', () {
    final p = applyPromotions([_item('shirt', 1100, 2)], [_twoFor2000],
        now: now);
    expect(p.listTotal, 2200);
    expect(p.total, 2000);
    expect(p.savings, 200);
    final bi = p.lines.single.toBillItem();
    expect(bi.price, 1000); // charged per piece
    expect(bi.listPrice, 1100);
    expect(bi.promo, '2 for 2000');
    expect(bi.subtotal, 2000);
  });

  test('odd quantity: 3 pieces = one bundle + one at full price', () {
    final p = applyPromotions([_item('shirt', 1100, 3)], [_twoFor2000],
        now: now);
    expect(p.total, 3100);
  });

  test('1 piece gets no offer', () {
    final p = applyPromotions([_item('shirt', 1100, 1)], [_twoFor2000],
        now: now);
    expect(p.total, 1100);
    expect(p.lines.single.hasPromo, false);
    expect(p.lines.single.toBillItem().listPrice, isNull);
  });

  test('type scope mixes and matches different hoodies', () {
    const promo = Promotion(
      name: 'Any 2 hoodies 3000',
      kind: PromoKind.bundle,
      buyQty: 2,
      value: 3000,
      scope: PromoScope.type,
      scopeType: 'Hoodie',
    );
    final p = applyPromotions([
      _item('h1', 2000, 1, type: 'Hoodie'),
      _item('h2', 1800, 1, type: 'Hoodie'),
      _item('t', 900, 1, type: 'Trouser'), // not covered
    ], [promo], now: now);
    expect(p.total, 3000 + 900);
    expect(p.lines[2].hasPromo, false);
    // Saving 800 is shared in proportion to price.
    expect(p.lines[0].discount, closeTo(800 * 2000 / 3800, 0.001));
  });

  test('buy 2 get 1 free: cheapest of each group is free', () {
    const promo = Promotion(
      name: 'B2G1',
      kind: PromoKind.buyGetFree,
      buyQty: 2,
      freeQty: 1,
      scope: PromoScope.all,
    );
    final p = applyPromotions([
      _item('a', 1000, 2),
      _item('b', 600, 1),
    ], [promo], now: now);
    expect(p.savings, 600);
    expect(p.total, 2000);
  });

  test('percent off only above minimum quantity', () {
    const promo = Promotion(
      name: '20% on 3+',
      kind: PromoKind.percentOff,
      buyQty: 3,
      value: 20,
      scope: PromoScope.all,
    );
    expect(applyPromotions([_item('a', 1000, 2)], [promo], now: now).total,
        2000);
    expect(applyPromotions([_item('a', 1000, 3)], [promo], now: now).total,
        2400);
  });

  test('best offer wins; each piece gets one offer', () {
    const tenPct = Promotion(
        name: '10%', kind: PromoKind.percentOff, buyQty: 1, value: 10,
        scope: PromoScope.all);
    final p = applyPromotions([_item('shirt', 1100, 2)], [tenPct, _twoFor2000],
        now: now);
    // 2-for-2000 saves 200; 10% saves 220 → 10% wins, not both.
    expect(p.savings, closeTo(220, 0.001));
    expect(p.lines.single.promoName, '10%');
  });

  test('off, not started and ended offers are ignored', () {
    final cart = [_item('shirt', 1100, 2)];
    Promotion withDates({DateTime? s, DateTime? e, bool active = true}) =>
        Promotion(
          name: 'x', kind: PromoKind.bundle, buyQty: 2, value: 2000,
          scope: PromoScope.all, startsAt: s, endsAt: e, active: active,
        );
    expect(applyPromotions(cart, [withDates(active: false)], now: now).savings,
        0);
    expect(
        applyPromotions(cart, [withDates(s: DateTime(2026, 11, 13))], now: now)
            .savings,
        0);
    expect(
        applyPromotions(cart, [withDates(e: DateTime(2026, 11, 11))], now: now)
            .savings,
        0);
    // End date is inclusive (whole day).
    expect(
        applyPromotions(cart, [withDates(e: DateTime(2026, 11, 12))], now: now)
            .savings,
        200);
  });

  test('bundle that is not cheaper does nothing', () {
    const bad = Promotion(
        name: 'bad', kind: PromoKind.bundle, buyQty: 2, value: 5000,
        scope: PromoScope.all);
    expect(applyPromotions([_item('a', 1100, 2)], [bad], now: now).savings, 0);
  });

  test('promotions save and load from the database', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await deleteDatabase(join(await getDatabasesPath(), 'pos_app.db'));
    final db = DatabaseHelper.instance;

    await db.savePromotion(Promotion(
      name: 'Eid sale', kind: PromoKind.bundle, buyQty: 2, value: 2000,
      scope: PromoScope.products, barcodes: const ['a', 'b'],
      startsAt: DateTime(2026, 11, 1), endsAt: DateTime(2026, 11, 30),
    ));
    final loaded = (await db.getPromotions()).single;
    expect(loaded.name, 'Eid sale');
    expect(loaded.barcodes, ['a', 'b']);
    expect(loaded.endsAt, DateTime(2026, 11, 30));
    expect(loaded.summary, 'Buy 2 for Rs 2000');

    // Bill items keep the promo price through save/load. (Checkout needs
    // the product in stock.)
    await db.insertProduct(
        Product(barcode: 'a', name: 'A', price: 1100, quantity: 5));
    final bi =applyPromotions([_item('a', 1100, 2)], [loaded], now: now)
        .lines
        .single
        .toBillItem();
    await db.checkout(Bill(
        billNumber: 'P1', items: [bi], totalAmount: bi.subtotal,
        createdAt: now));
    final saved = (await db.getAllBills()).single;
    expect(saved.items.single.price, 1000);
    expect(saved.items.single.listPrice, 1100);
    expect(saved.promoSavings, 200);
  });
}
