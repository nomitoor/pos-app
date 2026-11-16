import '../../models/bill.dart';
import '../../models/customer.dart';
import '../../models/expense.dart';
import '../../models/sale_return.dart';

/// Figures for one closing period (since the last day close).
class ZReport {
  final DateTime from;
  final DateTime to;
  final double openingFloat;

  final int billCount;
  final int itemsSold;

  /// Money value of bills (after offers and discounts).
  final double sales;
  final double offers;
  final double discounts;
  final double refunds;
  final int returnCount;

  /// Bill totals by payment method (incl. Udhaar).
  final Map<String, double> salesByMethod;

  /// Refunds by method (incl. Udhaar = credited to account).
  final Map<String, double> refundsByMethod;

  final double udhaarGiven; // credit sales
  final double udhaarCollected; // customer payments, any method
  final double udhaarCollectedCash;

  final double expenses;
  final double drawerExpenses; // paid from the cash drawer
  final Map<String, double> expensesByCategory;

  final List<(String, int, double)> topItems; // name, qty, amount

  const ZReport({
    required this.from,
    required this.to,
    required this.openingFloat,
    required this.billCount,
    required this.itemsSold,
    required this.sales,
    required this.offers,
    required this.discounts,
    required this.refunds,
    required this.returnCount,
    required this.salesByMethod,
    required this.refundsByMethod,
    required this.udhaarGiven,
    required this.udhaarCollected,
    required this.udhaarCollectedCash,
    required this.expenses,
    required this.drawerExpenses,
    required this.expensesByCategory,
    required this.topItems,
  });

  double get netSales => sales - refunds;
  double get cashSales => salesByMethod[Bill.cash] ?? 0;
  double get cashRefunds => refundsByMethod[Bill.cash] ?? 0;

  /// What should be in the drawer now.
  double get expectedCash =>
      openingFloat +
      cashSales -
      cashRefunds +
      udhaarCollectedCash -
      drawerExpenses;

  Map<String, dynamic> toMap() => {
    'from': from.toIso8601String(),
    'to': to.toIso8601String(),
    'opening_float': openingFloat,
    'bill_count': billCount,
    'items_sold': itemsSold,
    'sales': sales,
    'offers': offers,
    'discounts': discounts,
    'refunds': refunds,
    'return_count': returnCount,
    'sales_by_method': salesByMethod,
    'refunds_by_method': refundsByMethod,
    'udhaar_given': udhaarGiven,
    'udhaar_collected': udhaarCollected,
    'udhaar_collected_cash': udhaarCollectedCash,
    'expenses': expenses,
    'drawer_expenses': drawerExpenses,
    'expenses_by_category': expensesByCategory,
    'top_items': [
      for (final (n, q, a) in topItems) {'name': n, 'qty': q, 'amount': a},
    ],
  };

  factory ZReport.fromMap(Map<String, dynamic> m) {
    Map<String, double> money(Object? v) => {
      for (final e in ((v as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toDouble(),
    };
    double d(String k) => (m[k] as num?)?.toDouble() ?? 0;
    return ZReport(
      from: DateTime.parse(m['from'] as String),
      to: DateTime.parse(m['to'] as String),
      openingFloat: d('opening_float'),
      billCount: m['bill_count'] as int? ?? 0,
      itemsSold: m['items_sold'] as int? ?? 0,
      sales: d('sales'),
      offers: d('offers'),
      discounts: d('discounts'),
      refunds: d('refunds'),
      returnCount: m['return_count'] as int? ?? 0,
      salesByMethod: money(m['sales_by_method']),
      refundsByMethod: money(m['refunds_by_method']),
      udhaarGiven: d('udhaar_given'),
      udhaarCollected: d('udhaar_collected'),
      udhaarCollectedCash: d('udhaar_collected_cash'),
      expenses: d('expenses'),
      drawerExpenses: d('drawer_expenses'),
      expensesByCategory: money(m['expenses_by_category']),
      topItems: [
        for (final t in (m['top_items'] as List? ?? const []))
          (
            t['name'] as String,
            t['qty'] as int,
            (t['amount'] as num).toDouble(),
          ),
      ],
    );
  }
}

bool _inRange(DateTime t, DateTime from, DateTime to) =>
    !t.isBefore(from) && !t.isAfter(to);

ZReport computeZReport({
  required DateTime from,
  required DateTime to,
  required double openingFloat,
  required List<Bill> bills,
  required List<SaleReturn> returns,
  required List<Expense> expenses,
  required List<CustomerPayment> payments,
}) {
  final b = bills.where((x) => _inRange(x.createdAt, from, to)).toList();
  final r = returns.where((x) => _inRange(x.createdAt, from, to)).toList();
  final e = expenses.where((x) => _inRange(x.date, from, to)).toList();
  final p = payments.where((x) => _inRange(x.createdAt, from, to)).toList();

  final salesByMethod = <String, double>{};
  final items = <String, (String, int, double)>{};
  var itemsSold = 0;
  for (final bill in b) {
    final m = bill.paymentMethod ?? 'Not recorded';
    salesByMethod[m] = (salesByMethod[m] ?? 0) + bill.totalAmount;
    for (final i in bill.items) {
      itemsSold += i.quantity;
      final cur = items[i.barcode] ?? (i.name, 0, 0.0);
      items[i.barcode] = (cur.$1, cur.$2 + i.quantity, cur.$3 + i.subtotal);
    }
  }
  final refundsByMethod = <String, double>{};
  for (final ret in r) {
    refundsByMethod[ret.refundMethod] =
        (refundsByMethod[ret.refundMethod] ?? 0) + ret.refundAmount;
  }
  final byCategory = <String, double>{};
  for (final x in e) {
    byCategory[x.category] = (byCategory[x.category] ?? 0) + x.amount;
  }
  final top = items.values.toList()
    ..sort((a, b) => b.$2 != a.$2 ? b.$2 - a.$2 : b.$3.compareTo(a.$3));

  double sum<T>(Iterable<T> xs, double Function(T) f) =>
      xs.fold(0.0, (s, x) => s + f(x));

  return ZReport(
    from: from,
    to: to,
    openingFloat: openingFloat,
    billCount: b.length,
    itemsSold: itemsSold,
    sales: sum(b, (x) => x.totalAmount),
    offers: sum(b, (x) => x.promoSavings),
    discounts: sum(b, (x) => x.discount),
    refunds: sum(r, (x) => x.refundAmount),
    returnCount: r.length,
    salesByMethod: salesByMethod,
    refundsByMethod: refundsByMethod,
    udhaarGiven: salesByMethod[Bill.udhaar] ?? 0,
    udhaarCollected: sum(p, (x) => x.amount),
    udhaarCollectedCash: sum(
      p.where((x) => x.method == Bill.cash),
      (x) => x.amount,
    ),
    expenses: sum(e, (x) => x.amount),
    drawerExpenses: sum(e.where((x) => x.fromDrawer), (x) => x.amount),
    expensesByCategory: byCategory,
    topItems: top.take(5).toList(),
  );
}
