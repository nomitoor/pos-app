import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/insights/insights_data.dart';
import 'package:pos_app/models/bill.dart';
import 'package:pos_app/models/expense.dart';
import 'package:pos_app/models/product.dart';

Bill _bill(DateTime at, List<BillItem> items) => Bill(
      billNumber: 'B',
      items: items,
      totalAmount: items.fold(0, (s, i) => s + i.subtotal),
      createdAt: at,
    );

void main() {
  final now = DateTime(2026, 11, 12, 15);
  final hoodieS = Product(
      barcode: 'h-s', name: 'Hoodie', price: 1000, quantity: 3,
      size: 'Small', type: 'Hoodie');
  final hoodieL = Product(
      barcode: 'h-l', name: 'Hoodie', price: 1000, quantity: 50,
      size: 'Large', type: 'Hoodie');
  final trouser = Product(
      barcode: 't', name: 'Trouser', price: 500, quantity: 10,
      type: 'Trouser');
  final products = [hoodieS, hoodieL, trouser];

  BillItem item(Product p, int qty) => BillItem(
      barcode: p.barcode, name: p.name, price: p.price, quantity: qty,
      size: p.size, type: p.type);

  final bills = [
    _bill(DateTime(2026, 11, 12, 11), [item(hoodieS, 2), item(trouser, 1)]),
    _bill(DateTime(2026, 11, 12, 14), [item(hoodieS, 1)]),
    _bill(DateTime(2026, 11, 11, 10), [item(hoodieL, 4)]), // yesterday
    _bill(DateTime(2026, 9, 1, 10), [item(trouser, 9)]), // > 30 days ago
  ];

  test('today: totals, comparison and rankings', () {
    final d = computeInsights(
        bills: bills, products: products, period: InsightPeriod.today,
        now: now);
    expect(d.revenue, 3500);
    expect(d.billCount, 2);
    expect(d.itemsSold, 4);
    expect(d.previousRevenue, 4000);
    expect(d.bestSeller!.key, 'h-s');
    expect(d.bestSize!.label, 'Small');
    expect(d.bestType!.label, 'Hoodie');
    expect(d.bySize.map((s) => s.label), contains(noSizeLabel));
    expect(d.peakHour!.label, '11am');
  });

  test('all time includes old bills and has no comparison', () {
    final d = computeInsights(
        bills: bills, products: products, period: InsightPeriod.all,
        now: now);
    expect(d.billCount, 4);
    expect(d.previousRevenue, isNull);
    expect(d.bestSeller!.key, 't'); // 10 trousers
    expect(d.trend, hasLength(12));
  });

  test('restock and slow movers use the last 30 days', () {
    final d = computeInsights(
        bills: bills, products: products, period: InsightPeriod.week,
        now: now);
    // Small hoodie: 3 sold in 30 days, 3 left → 30 days; Large: 4 sold,
    // 50 left → long way off. Neither is under 14 days.
    expect(d.restock, isEmpty);
    expect(d.slowMovers, isEmpty);
    expect(d.trend, hasLength(7));
    expect(d.stockValue, 3000 + 50000 + 5000);
  });

  test('profit, margin, discounts and payment methods', () {
    final shirt = Product(
        barcode: 's', name: 'Shirt', price: 1000, quantity: 10,
        type: 'Shirt', costPrice: 600);
    final noCost = Product(
        barcode: 'n', name: 'Cap', price: 200, quantity: 10, type: 'Other');
    final items = [
      BillItem(barcode: 's', name: 'Shirt', price: 1000, quantity: 2,
          costPrice: 600),
      BillItem(barcode: 'n', name: 'Cap', price: 200, quantity: 1),
    ];
    // Subtotal 2200, discount 220 (10%) spread over items.
    final b1 = Bill(
        billNumber: 'B1', items: items, totalAmount: 1980,
        createdAt: DateTime(2026, 11, 12, 10), discount: 220,
        paymentMethod: 'Cash');
    final b2 = Bill(
        billNumber: 'B2',
        items: [BillItem(barcode: 's', name: 'Shirt', price: 1000,
            quantity: 1, costPrice: 600)],
        totalAmount: 1000, createdAt: DateTime(2026, 11, 12, 12),
        paymentMethod: 'JazzCash');

    final d = computeInsights(
        bills: [b1, b2], products: [shirt, noCost],
        period: InsightPeriod.today, now: now);

    // Shirts: b1 net 2000*0.9=1800 - 1200 = 600; b2 1000 - 600 = 400.
    expect(d.profit, closeTo(1000, 0.001));
    expect(d.costedRevenue, closeTo(2800, 0.001));
    expect(d.marginPct, closeTo(1000 / 2800 * 100, 0.001));
    expect(d.uncostedQty, 1);
    expect(d.discountTotal, 220);
    expect(d.topByProfit.single.key, 's');
    expect(d.byPayment.map((p) => p.label), ['Cash', 'JazzCash']);
    expect(d.byPayment.first.qty, 1);
    expect(d.stockCostValue, 6000);
  });

  test('expenses in the period give net profit', () {
    final item = BillItem(barcode: 's', name: 'Shirt', price: 1000,
        quantity: 10, costPrice: 600);
    final d = computeInsights(
      bills: [
        Bill(billNumber: 'B', items: [item], totalAmount: 10000,
            createdAt: DateTime(2026, 11, 12, 10)),
      ],
      products: const [],
      expenses: [
        Expense(category: 'Rent', amount: 3000, paidFrom: 'Bank / Card',
            date: DateTime(2026, 11, 12, 9)),
        Expense(category: 'Tea / Food', amount: 200,
            paidFrom: Expense.cashDrawer, date: DateTime(2026, 11, 12, 11)),
        Expense(category: 'Rent', amount: 9999, paidFrom: 'Bank / Card',
            date: DateTime(2026, 10, 1)), // other month
      ],
      period: InsightPeriod.today,
      now: now,
    );
    expect(d.profit, 4000);
    expect(d.expenses, 3200);
    expect(d.netProfit, 800);
    expect(d.expensesByCategory.first.label, 'Rent');
  });

  test('size/type fall back to the product for old bill items', () {
    final old = [
      _bill(DateTime(2026, 11, 12, 9),
          [BillItem(barcode: 'h-l', name: 'Hoodie', price: 1000, quantity: 1)]),
    ];
    final d = computeInsights(
        bills: old, products: products, period: InsightPeriod.today,
        now: now);
    expect(d.bestSize!.label, 'Large');
    expect(d.bestType!.label, 'Hoodie');
  });
}
