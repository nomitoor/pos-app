// Renders key screens to PNG for visual review. Skipped unless SHOTS_OUT
// is set, e.g.:
//   SHOTS_OUT=/tmp/shots flutter test test/screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:pos_app/core/database/database_helper.dart';
import 'package:pos_app/core/navigation.dart';
import 'package:pos_app/core/theme/app_theme.dart';
import 'package:pos_app/features/billing/providers/billing_provider.dart';
import 'package:pos_app/features/customers/screens/customers_screen.dart';
import 'package:pos_app/features/insights/screens/insights_screen.dart';
import 'package:pos_app/main.dart' show MainShell;
import 'package:pos_app/features/splash/splash_screen.dart';
import 'package:pos_app/features/inventory/providers/inventory_provider.dart';
import 'package:pos_app/features/inventory/screens/design_detail_screen.dart';
import 'package:pos_app/features/inventory/screens/design_form_screen.dart';
import 'package:pos_app/models/bill.dart';
import 'package:pos_app/models/customer.dart';
import 'package:pos_app/models/expense.dart';
import 'package:pos_app/models/held_bill.dart';
import 'package:pos_app/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _out = Platform.environment['SHOTS_OUT'];
final _fonts = Platform.environment['FONTS_DIR'];

Future<void> _loadFonts() async {
  Future<ByteData> f(String name) async =>
      ByteData.sublistView(await File('$_fonts/$name').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold', 'Black', 'Light']) {
    roboto.addFont(f('Roboto-$w.ttf'));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(f('MaterialIcons-Regular.otf'));
  await icons.load();
}

Future<void> _seed() async {
  final db = DatabaseHelper.instance;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final products = [
    Product(barcode: 'p1', name: 'Classic Hoodie', price: 2200, quantity: 14,
        size: 'Large', type: 'Hoodie', costPrice: 1400),
    Product(barcode: 'p2', name: 'Slim Fit Trouser', price: 1800, quantity: 3,
        size: 'Medium', type: 'Trouser', costPrice: 1100),
    Product(barcode: 'p3', name: 'Graphic Tee', price: 950, quantity: 0,
        size: 'Small', type: 'T-Shirt', costPrice: 500),
  ];
  for (final p in products) {
    await db.insertProduct(p);
  }
  // More sizes of the hoodie, so it shows as one design with sizes.
  for (final (code, size, qty) in [
    ('p1s', 'Small', 6),
    ('p1m', 'Medium', 0),
    ('p1xl', 'Extra Large', 2),
  ]) {
    await db.insertProduct(Product(barcode: code, name: 'Classic Hoodie',
        price: 2200, quantity: qty, size: size, type: 'Hoodie',
        costPrice: 1400));
  }
  BillItem item(Product p, int q) => BillItem(
      barcode: p.barcode, name: p.name, price: p.price, quantity: q,
      size: p.size, type: p.type, costPrice: p.costPrice);
  await db.checkout(Bill(billNumber: 'BILL-A1', items: [item(products[0], 2)],
      totalAmount: 4400, createdAt: today.add(const Duration(hours: 11)),
      paymentMethod: 'Cash'));
  await db.checkout(Bill(billNumber: 'BILL-A2',
      items: [item(products[1], 1), item(products[0], 1)],
      totalAmount: 4000, createdAt: today.add(const Duration(hours: 13)),
      paymentMethod: 'JazzCash'));
  await db.checkout(Bill(billNumber: 'BILL-Y1', items: [item(products[0], 1)],
      totalAmount: 2200,
      createdAt: today.subtract(const Duration(hours: 5)),
      paymentMethod: 'Cash'));
  final ali = await db.saveCustomer(
      Customer(name: 'Ali Raza', phone: '0300-7654321', createdAt: today));
  await db.checkout(
      Bill(billNumber: 'BILL-U1', items: [item(products[1], 1)],
          totalAmount: 1800, createdAt: today.add(const Duration(hours: 9)),
          paymentMethod: Bill.udhaar, customerId: ali, customerName: 'Ali Raza',
          customerPhone: '0300-7654321'),
      paidNow: 500);
  await db.saveCustomer(
      Customer(name: 'Sara Khan', phone: '0321-1112223', createdAt: today));
  await db.saveExpense(Expense(category: 'Tea / Food', amount: 300,
      paidFrom: Expense.cashDrawer, date: today.add(const Duration(hours: 12))));
  await db.holdBill(HeldBill(label: 'Lady in blue',
      items: [item(products[0], 1)], createdAt: now));
}

void main() {
  setUpAll(() async {
    if (_out == null) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await deleteDatabase(join(await getDatabasesPath(), 'pos_app.db'));
    await _seed();
  });

  Future<void> shoot(WidgetTester tester, ProviderContainer c, Widget home,
      String name) async {
    final key = GlobalKey();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: home,
        ),
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  testWidgets('screenshots', skip: _out == null, (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final c = ProviderContainer();
    addTearDown(c.dispose);

    // Held open (long minimum) so the splash itself is captured.
    await shoot(tester, c,
        const SplashGate(minDuration: Duration(hours: 1), child: SizedBox()),
        'splash');
    await shoot(tester, c, const MainShell(), 'dashboard');

    await tester.runAsync(() async {
      final p = (await DatabaseHelper.instance.getAllProducts())
          .firstWhere((p) => p.barcode == 'p1');
      await c.read(cartProvider.notifier).addItem(p);
      await c.read(cartProvider.notifier).addItem(p);
    });
    c.read(navIndexProvider.notifier).state = Tabs.billing;
    await shoot(tester, c, const MainShell(), 'billing');

    c.read(navIndexProvider.notifier).state = Tabs.inventory;
    await shoot(tester, c, const MainShell(), 'inventory');

    final hoodieDesign = await tester.runAsync(() async =>
        (await DatabaseHelper.instance.getAllProducts())
            .firstWhere((p) => p.barcode == 'p1')
            .designId!);
    await shoot(tester, c, DesignDetailScreen(designId: hoodieDesign!),
        'design_detail');
    final group = await tester.runAsync(() async =>
        (await c.read(designGroupsProvider.future))
            .firstWhere((g) => g.design.id == hoodieDesign));
    await shoot(tester, c, DesignFormScreen(existing: group), 'design_form');

    await shoot(tester, c, const InsightsScreen(), 'insights');
    await shoot(tester, c, const CustomersScreen(), 'customers');

    // Let the held-open splash timer expire so no timer is left pending.
    await tester.pump(const Duration(hours: 2));
  });
}
