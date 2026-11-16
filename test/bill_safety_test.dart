import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:pos_app/core/database/database_helper.dart';
import 'package:pos_app/features/bills/bill_lookup.dart';
import 'package:pos_app/models/bill.dart';
import 'package:pos_app/models/day_close.dart';
import 'package:pos_app/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Unpredictable invoice numbers with an internal serial, stock checks at
/// checkout, voiding instead of deleting, closed-day protection and range
/// loading.
void main() {
  final db = DatabaseHelper.instance;
  final invFormat = RegExp(
    r'^INV-[2-9A-HJKMNP-TV-Z]{4}-[2-9A-HJKMNP-TV-Z]{4}$',
  );

  BillItem shirt(int qty) => BillItem(
    barcode: 's-m',
    name: 'Shirt',
    price: 1000,
    quantity: qty,
    size: 'M',
  );

  Bill draft(
    List<BillItem> items, {
    String number = '',
    DateTime? at,
    String method = 'Cash',
  }) => Bill(
    billNumber: number,
    items: items,
    totalAmount: items.fold(0, (s, i) => s + i.subtotal),
    createdAt: at ?? DateTime.now(),
    paymentMethod: method,
  );

  Future<int> stock() async => (await db.getProductByBarcode('s-m'))!.quantity;

  // Bills made by the tests below, in order.
  late Bill first, second, third;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await deleteDatabase(join(await getDatabasesPath(), 'pos_app.db'));
    await db.insertProduct(
      Product(
        barcode: 's-m',
        name: 'Shirt',
        price: 1000,
        quantity: 10,
        size: 'M',
      ),
    );
  });

  test('random numbers look right and are not sequential', () {
    final seen = <String>{};
    for (var i = 0; i < 2000; i++) {
      final n = Bill.randomNumber();
      expect(n, matches(invFormat));
      seen.add(n);
    }
    expect(seen.length, 2000, reason: 'no repeats in 2000 draws');
    // Same seed → same code; different seed → different code.
    expect(Bill.randomNumber(Random(1)), Bill.randomNumber(Random(1)));
    expect(Bill.randomNumber(Random(1)), isNot(Bill.randomNumber(Random(2))));
  });

  test('new bills get random INV numbers and running serials', () async {
    // Given numbers (online orders, older bills) are kept as they are.
    final online = await db.checkout(
      draft([shirt(1)], number: 'UT-251113-4821'),
    );
    expect(online.billNumber, 'UT-251113-4821');
    expect(online.serial, 1);

    first = await db.checkout(draft([shirt(1)]));
    second = await db.checkout(draft([shirt(1)]));
    expect(first.billNumber, matches(invFormat));
    expect(second.billNumber, matches(invFormat));
    expect(first.billNumber, isNot(second.billNumber));
    expect(first.serial, 2);
    expect(second.serial, 3);
    expect((await db.getBillById(second.id!))!.serial, 3);
    expect(await stock(), 7);
  });

  test('lookup ignores case, spaces and dashes', () async {
    final typed = first.billNumber.toLowerCase().replaceAll('-', ' ');
    expect((await db.getBillByNumber(typed))!.id, first.id);
    expect(
      (await db.getBillByNumber('UT2511134821'))!.billNumber,
      'UT-251113-4821',
    );
  });

  test(
    'checkout refuses more than is in stock, with a clear message',
    () async {
      await expectLater(
        db.checkout(draft([shirt(8)])),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Only 7 of "Shirt (M)" left in stock.',
          ),
        ),
      );
      expect(await stock(), 7, reason: 'nothing deducted');
      expect(await db.countBills(), 3, reason: 'bill not saved');

      // A product deleted while still in a cart.
      await expectLater(
        db.checkout(
          draft([
            BillItem(barcode: 'gone', name: 'Cap', price: 1, quantity: 1),
          ]),
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('voiding puts stock back and stops the bill counting', () async {
    await db.voidBill(second, 'Wrong items rung up');

    expect(await stock(), 8);
    expect(await db.countBills(), 2);
    expect((await db.getBills()).map((b) => b.id), isNot(contains(second.id)));

    final voided = (await db.getBillById(second.id!))!;
    expect(voided.isVoided, true);
    expect(voided.voidReason, 'Wrong items rung up');
    expect((await db.getBills(includeVoided: true)).length, 3);

    // Can't void twice, edit a voided bill, or void without a reason.
    await expectLater(db.voidBill(voided, 'again'), throwsA(isA<StateError>()));
    await expectLater(
      db.updateBill(voided, [shirt(1)]),
      throwsA(isA<StateError>()),
    );
    await expectLater(db.voidBill(first, '  '), throwsA(isA<StateError>()));

    // Serials keep running after a void (the voided one keeps its serial).
    third = await db.checkout(draft([shirt(1)]));
    expect(third.serial, 4);
  });

  test('editing checks stock in plain words', () async {
    final left = await stock();
    await expectLater(
      db.updateBill(third, [shirt(1 + left + 1)]),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('left in stock'),
        ),
      ),
    );
    await db.updateBill(third, [shirt(2)]);
    expect(await stock(), left - 1);
  });

  test('bills from a closed day cannot be edited or voided', () async {
    await db.saveDayClose(
      DayClose(
        periodStart: DateTime(2020),
        closedAt: DateTime.now(),
        openingFloat: 0,
        expectedCash: 0,
        countedCash: 0,
        floatKept: 0,
        summary: const {},
      ),
    );
    expect(await db.isInClosedDay(first), true);
    await expectLater(
      db.voidBill(first, 'Customer cancelled'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      db.updateBill(first, [shirt(1)]),
      throwsA(isA<StateError>()),
    );

    // A sale after the close is still changeable.
    await Future.delayed(const Duration(milliseconds: 5));
    final after = await db.checkout(draft([shirt(1)]));
    expect(await db.isInClosedDay(after), false);
    await db.voidBill(after, 'Test bill');
  });

  test('bills load by date range and search', () async {
    final old = await db.checkout(
      draft([shirt(1)], at: DateTime.now().subtract(const Duration(days: 40))),
    );
    final since30 = await db.getBills(
      from: DateTime.now().subtract(const Duration(days: 30)),
    );
    expect(since30.map((b) => b.id), isNot(contains(old.id)));
    expect((await db.getBills()).map((b) => b.id), contains(old.id));

    final q = first.billNumber.toLowerCase();
    final hits = await db.getBills(search: q, includeVoided: true);
    expect(hits.where((b) => billMatches(b, q)).single.id, first.id);
    expect((await db.getBills(search: 'shirt')).isNotEmpty, true);
  });

  test('lookup by code finds voided bills too (to show them)', () async {
    final r = await lookupBillByCode(second.billNumber, const []);
    expect(r.bill!.isVoided, true);
    expect((await lookupBillByCode('nope', const [])).bill, isNull);
  });

  test('older bills without serials get them, oldest first', () async {
    final raw = await db.database;
    await raw.update('bills', {'serial': null});
    // Restoring a backup re-runs the numbering.
    await db.restoreAll(await db.exportAll());
    final bills = await db.getBills(includeVoided: true);
    final byDate = [...bills]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    expect(byDate.first.serial, 1, reason: 'the 40-day-old bill');
    expect(bills.map((b) => b.serial).toSet().length, bills.length);
  });
}
