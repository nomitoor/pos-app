import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:pos_app/core/database/database_helper.dart';
import 'package:pos_app/features/billing/providers/billing_provider.dart';
import 'package:pos_app/features/billing/providers/held_bills_provider.dart';
import 'package:pos_app/features/billing/screens/billing_screen.dart';
import 'package:pos_app/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Runs animations (dialogs, sheets) to completion without waiting for
/// endless ones like spinners, which would hang pumpAndSettle.
Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Lets real (isolate-backed) database work finish inside a widget test.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await pumpFrames(tester);
}

void main() {
  late Product shirt;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await deleteDatabase(join(await getDatabasesPath(), 'pos_app.db'));
    shirt = Product(barcode: 'HOLD-1', name: 'Shirt', price: 1500, quantity: 5);
    await DatabaseHelper.instance.insertProduct(shirt);
  });

  testWidgets('hold a bill, see it in the list and resume it',
      timeout: const Timeout(Duration(minutes: 2)), (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: BillingScreen()),
    ));
    await settle(tester);

    // Put 2 shirts in the cart.
    await tester.runAsync(() async {
      await container.read(cartProvider.notifier).addItem(shirt);
      await container.read(cartProvider.notifier).addItem(shirt);
    });
    await settle(tester);
    expect(find.text('Shirt'), findsOneWidget);

    // Hold it with a name.
    await tester.tap(find.byTooltip('Hold this bill'));
    await pumpFrames(tester);
    await tester.enterText(find.byType(TextField), 'Lady in blue');
    await tester.tap(find.text('Hold'));
    await settle(tester); // the closing animation used to crash here

    expect(tester.takeException(), isNull);
    expect(container.read(cartProvider), isEmpty);
    final held = await tester
        .runAsync(() => container.read(heldBillsProvider.future));
    expect(held!.single.label, 'Lady in blue');

    // Open the held list and resume it.
    await tester.tap(find.byTooltip('Held bills'));
    await pumpFrames(tester);
    expect(find.text('Lady in blue'), findsOneWidget);
    await tester.tap(find.text('Lady in blue'));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(container.read(cartProvider).single.quantity, 2);
    final after = await tester
        .runAsync(() => container.read(heldBillsProvider.future));
    expect(after, isEmpty);
  });
}
