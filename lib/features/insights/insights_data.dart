import '../../models/bill.dart';
import '../../models/product.dart';
import '../../models/sale_return.dart';
import '../../models/expense.dart';

enum InsightPeriod {
  today('Today'),
  week('7 Days'),
  month('30 Days'),
  all('All Time');

  final String label;
  const InsightPeriod(this.label);
}

/// Sales totals for one product, size, type, etc.
class SalesStat {
  final String key;
  final String label;
  final String? subtitle;
  int qty = 0;
  double revenue = 0;

  /// Profit from the units whose cost price is known (after discounts).
  double profit = 0;
  int costedQty = 0;

  /// Units returned in the period, and the money refunded for them.
  int returnedQty = 0;
  double refunded = 0;

  /// Returned units as % of units sold; null when nothing sold.
  double? get returnRatePct => qty == 0 ? null : returnedQty / qty * 100;

  SalesStat(this.key, this.label, {this.subtitle});

  bool get hasProfit => costedQty > 0;
}

/// One bar in a chart.
class ChartPoint {
  final String label;
  final double value;
  const ChartPoint(this.label, this.value);
}

/// A selling product that will run out soon at its current sales rate.
class RestockAlert {
  final Product product;
  final double perDay;
  final double daysLeft;
  const RestockAlert(this.product, this.perDay, this.daysLeft);
}

class Insights {
  final InsightPeriod period;
  final double revenue;
  final int billCount;
  final int itemsSold;

  /// Revenue of the equal-length period just before this one; null for
  /// [InsightPeriod.all].
  final double? previousRevenue;

  /// Profit on items with a known cost price, after their share of discounts.
  final double profit;

  /// Revenue (after discounts) of the items counted in [profit].
  final double costedRevenue;

  /// Units sold whose cost price is unknown, so they're left out of profit.
  final int uncostedQty;

  final double discountTotal;

  /// Money customers saved through promotions.
  final double promoSavings;

  /// Shop expenses (rent, salaries, …) dated in the period.
  final double expenses;
  final List<SalesStat> expensesByCategory; // revenue = amount

  /// Profit on goods minus expenses.
  double get netProfit => profit - expenses;

  /// Per promotion: qty = pieces sold on it, revenue = what they paid,
  /// profit = what the promotion gave away (savings).
  final List<SalesStat> byPromo;

  // ── Returns made in the period ──
  final int returnCount;
  final int returnedQty;
  final double refundTotal;

  /// qty = units returned, revenue = refunded.
  final List<SalesStat> returnsByReason;
  final List<SalesStat> mostReturned;

  /// Per payment method: qty = number of bills, revenue = amount paid.
  final List<SalesStat> byPayment;

  final List<SalesStat> topByQty;
  final List<SalesStat> topByRevenue;
  final List<SalesStat> topByProfit;
  final List<SalesStat> bySize;
  final List<SalesStat> byType;
  final List<ChartPoint> trend;
  final String trendTitle;
  final List<ChartPoint> byHour; // revenue per hour of day, 0–23
  final List<ChartPoint> byWeekday; // revenue per weekday, Mon–Sun

  // Inventory-wide (independent of the selected period).
  final List<RestockAlert> restock;
  final List<Product> slowMovers; // in stock, no sales in last 30 days
  final double stockValue;

  /// Stock valued at cost, for products with a cost price; null if none.
  final double? stockCostValue;
  final int outOfStock;

  Insights({
    required this.period,
    required this.revenue,
    required this.billCount,
    required this.itemsSold,
    required this.previousRevenue,
    required this.profit,
    required this.costedRevenue,
    required this.uncostedQty,
    required this.discountTotal,
    required this.promoSavings,
    required this.byPromo,
    this.expenses = 0,
    this.expensesByCategory = const [],
    required this.returnCount,
    required this.returnedQty,
    required this.refundTotal,
    required this.returnsByReason,
    required this.mostReturned,
    required this.byPayment,
    required this.topByQty,
    required this.topByRevenue,
    required this.topByProfit,
    required this.bySize,
    required this.byType,
    required this.trend,
    required this.trendTitle,
    required this.byHour,
    required this.byWeekday,
    required this.restock,
    required this.slowMovers,
    required this.stockValue,
    required this.stockCostValue,
    required this.outOfStock,
  });

  double get avgBill => billCount == 0 ? 0 : revenue / billCount;

  /// Sales minus refunds.
  double get netRevenue => revenue - refundTotal;

  /// Units returned as % of units sold in the period.
  double? get returnRatePct =>
      itemsSold == 0 ? null : returnedQty / itemsSold * 100;

  bool get hasProfit => costedRevenue > 0;

  /// Profit as % of the revenue it was earned on; null when no cost data.
  double? get marginPct => hasProfit ? profit / costedRevenue * 100 : null;

  /// Percent change vs the previous period, or null when not comparable.
  double? get revenueChangePct {
    final prev = previousRevenue;
    if (prev == null || prev == 0) return null;
    return (revenue - prev) / prev * 100;
  }

  SalesStat? get bestSeller => topByQty.isEmpty ? null : topByQty.first;
  SalesStat? get bestSize => bySize.isEmpty ? null : bySize.first;
  SalesStat? get bestType => byType.isEmpty ? null : byType.first;

  ChartPoint? get peakHour => _maxPoint(byHour);
  ChartPoint? get bestWeekday => _maxPoint(byWeekday);

  static ChartPoint? _maxPoint(List<ChartPoint> pts) {
    ChartPoint? best;
    for (final p in pts) {
      if (p.value > 0 && (best == null || p.value > best.value)) best = p;
    }
    return best;
  }
}

const noSizeLabel = 'No size';
const noTypeLabel = 'Uncategorised';
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

String _hourLabel(int h) {
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12${h < 12 ? 'am' : 'pm'}';
}

/// Start of [period] (inclusive) relative to [now]; null for all time.
DateTime? periodStart(InsightPeriod period, DateTime now) {
  final today = _day(now);
  switch (period) {
    case InsightPeriod.today:
      return today;
    case InsightPeriod.week:
      return today.subtract(const Duration(days: 6));
    case InsightPeriod.month:
      return today.subtract(const Duration(days: 29));
    case InsightPeriod.all:
      return null;
  }
}

Insights computeInsights({
  required List<Bill> bills,
  required List<Product> products,
  required InsightPeriod period,
  List<SaleReturn> returns = const [],
  List<Expense> expenses = const [],
  DateTime? now,
}) {
  now ??= DateTime.now();
  final today = _day(now);
  final start = periodStart(period, now);
  final productsByCode = {for (final p in products) p.barcode: p};

  final inPeriod = start == null
      ? bills
      : bills.where((b) => !b.createdAt.isBefore(start)).toList();

  // Previous equal-length period, for the revenue comparison.
  double? previousRevenue;
  if (start != null) {
    final length = today.difference(start).inDays + 1;
    final prevStart = start.subtract(Duration(days: length));
    previousRevenue = bills
        .where(
          (b) =>
              !b.createdAt.isBefore(prevStart) && b.createdAt.isBefore(start),
        )
        .fold<double>(0, (s, b) => s + b.totalAmount);
  }

  final byItem = <String, SalesStat>{};
  final bySize = <String, SalesStat>{};
  final byType = <String, SalesStat>{};
  final byPayment = <String, SalesStat>{};
  final hourly = List<double>.filled(24, 0);
  final weekday = List<double>.filled(7, 0);
  var revenue = 0.0;
  var itemsSold = 0;
  var profit = 0.0;
  var costedRevenue = 0.0;
  var uncostedQty = 0;
  var discountTotal = 0.0;
  var promoSavings = 0.0;
  final byPromo = <String, SalesStat>{};

  for (final bill in inPeriod) {
    revenue += bill.totalAmount;
    discountTotal += bill.discount;
    hourly[bill.createdAt.hour] += bill.totalAmount;
    weekday[bill.createdAt.weekday - 1] += bill.totalAmount;

    final method = bill.paymentMethod ?? 'Not recorded';
    byPayment.putIfAbsent(method, () => SalesStat(method, method))
      ..qty += 1
      ..revenue += bill.totalAmount;

    // Spread the bill discount over its items in proportion to their value.
    final billSubtotal = bill.subtotal;
    final keepRatio = billSubtotal > 0
        ? (billSubtotal - bill.discount) / billSubtotal
        : 1.0;

    for (final item in bill.items) {
      final product = productsByCode[item.barcode];
      // Prefer what was recorded at sale time; fall back to the product.
      final size = item.size ?? product?.size ?? noSizeLabel;
      final type = item.type ?? product?.type ?? noTypeLabel;
      final cost = item.costPrice ?? product?.costPrice;
      final netRevenue = item.subtotal * keepRatio;
      final itemProfit = cost == null
          ? null
          : netRevenue - cost * item.quantity;

      itemsSold += item.quantity;
      if (item.promo != null && item.promoSavings > 0) {
        promoSavings += item.promoSavings;
        byPromo.putIfAbsent(
            item.promo!,
            () => SalesStat(item.promo!, item.promo!),
          )
          ..qty += item.quantity
          ..revenue += item.subtotal
          ..profit += item.promoSavings;
      }
      if (itemProfit == null) {
        uncostedQty += item.quantity;
      } else {
        profit += itemProfit;
        costedRevenue += netRevenue;
      }

      final detail = [
        if (type != noTypeLabel) type,
        if (size != noSizeLabel) size,
      ].join(' • ');
      final stat = byItem.putIfAbsent(
        item.barcode,
        () => SalesStat(
          item.barcode,
          item.name,
          subtitle: detail.isEmpty ? null : detail,
        ),
      );
      for (final s in [
        stat,
        bySize.putIfAbsent(size, () => SalesStat(size, size)),
        byType.putIfAbsent(type, () => SalesStat(type, type)),
      ]) {
        s.qty += item.quantity;
        s.revenue += item.subtotal;
        if (itemProfit != null) {
          s.profit += itemProfit;
          s.costedQty += item.quantity;
        }
      }
    }
  }

  // ── Returns made in this period (whenever the original sale was) ──
  final returnsInPeriod = start == null
      ? returns
      : returns.where((r) => !r.createdAt.isBefore(start)).toList();
  final byReason = <String, SalesStat>{};
  final returnedItems = <String, SalesStat>{};
  var refundTotal = 0.0;
  var returnedQty = 0;

  for (final r in returnsInPeriod) {
    for (final i in r.items) {
      refundTotal += i.refund;
      returnedQty += i.quantity;

      final product = productsByCode[i.barcode];
      final size = i.size ?? product?.size ?? noSizeLabel;
      final type = i.type ?? product?.type ?? noTypeLabel;

      // Undo the sale's profit. A restocked piece can be sold again, so we
      // only lose its margin; a written-off piece also loses its cost.
      final cost = i.costPrice ?? product?.costPrice;
      final profitLost = cost == null
          ? null
          : i.refund - (i.restocked ? cost * i.quantity : 0);
      if (profitLost != null) {
        profit -= profitLost;
        costedRevenue -= i.refund;
      }

      final detail = [
        if (type != noTypeLabel) type,
        if (size != noSizeLabel) size,
      ].join(' • ');
      for (final s in [
        byReason.putIfAbsent(r.reason, () => SalesStat(r.reason, r.reason)),
        returnedItems.putIfAbsent(
          i.barcode,
          () => SalesStat(
            i.barcode,
            i.name,
            subtitle: detail.isEmpty ? null : detail,
          ),
        ),
        // Only annotate sizes/types/items that also sold in the period, so
        // their return rate is meaningful.
        ?bySize[size],
        ?byType[type],
        ?byItem[i.barcode],
      ]) {
        s.returnedQty += i.quantity;
        s.refunded += i.refund;
      }
      if (profitLost != null) byItem[i.barcode]?.profit -= profitLost;
    }
  }
  // In these returns-only lists, qty/revenue already mean "returned" and
  // "refunded"; clear the extra fields so no "100% returned" is shown.
  for (final s in [...byReason.values, ...returnedItems.values]) {
    s.qty = s.returnedQty;
    s.revenue = s.refunded;
    s.returnedQty = 0;
    s.refunded = 0;
  }

  // ── Expenses in the period ──
  final expenseCats = <String, SalesStat>{};
  var expenseTotal = 0.0;
  for (final e in expenses) {
    if (start != null && e.date.isBefore(start)) continue;
    if (e.date.isAfter(now)) continue;
    expenseTotal += e.amount;
    expenseCats.putIfAbsent(e.category, () => SalesStat(e.category, e.category))
      ..qty += 1
      ..revenue += e.amount;
  }

  List<SalesStat> sorted(
    Iterable<SalesStat> stats,
    int Function(SalesStat, SalesStat) cmp,
  ) {
    final list = stats.toList()..sort(cmp);
    return list;
  }

  int byQty(SalesStat a, SalesStat b) =>
      b.qty != a.qty ? b.qty - a.qty : b.revenue.compareTo(a.revenue);
  int byRev(SalesStat a, SalesStat b) => b.revenue.compareTo(a.revenue);

  // ── Trend chart ──
  final List<ChartPoint> trend;
  final String trendTitle;
  switch (period) {
    case InsightPeriod.today:
      trendTitle = 'Sales by hour (today)';
      // Show the shop's active hours only (first to last sale, min 8am–8pm).
      final active = [
        for (var h = 0; h < 24; h++)
          if (hourly[h] > 0) h,
      ];
      final from = active.isEmpty ? 8 : (active.first < 8 ? active.first : 8);
      final to = active.isEmpty ? 20 : (active.last > 20 ? active.last : 20);
      trend = [
        for (var h = from; h <= to; h++) ChartPoint(_hourLabel(h), hourly[h]),
      ];
    case InsightPeriod.week:
    case InsightPeriod.month:
      trendTitle = 'Daily sales';
      final days = period == InsightPeriod.week ? 7 : 30;
      final perDay = <DateTime, double>{};
      for (final b in inPeriod) {
        final d = _day(b.createdAt);
        perDay[d] = (perDay[d] ?? 0) + b.totalAmount;
      }
      trend = [
        for (var i = days - 1; i >= 0; i--)
          () {
            final d = today.subtract(Duration(days: i));
            final label = days == 7 ? _weekdays[d.weekday - 1] : '${d.day}';
            return ChartPoint(label, perDay[d] ?? 0);
          }(),
      ];
    case InsightPeriod.all:
      trendTitle = 'Monthly sales (last 12 months)';
      final perMonth = <String, double>{};
      for (final b in inPeriod) {
        final k = '${b.createdAt.year}-${b.createdAt.month}';
        perMonth[k] = (perMonth[k] ?? 0) + b.totalAmount;
      }
      trend = [
        for (var i = 11; i >= 0; i--)
          () {
            final m = DateTime(now!.year, now.month - i);
            return ChartPoint(
              _months[m.month - 1],
              perMonth['${m.year}-${m.month}'] ?? 0,
            );
          }(),
      ];
  }

  // ── Inventory health, based on the last 30 days of sales ──
  final last30Start = today.subtract(const Duration(days: 29));
  final sold30 = <String, int>{};
  for (final b in bills) {
    if (b.createdAt.isBefore(last30Start)) continue;
    for (final i in b.items) {
      sold30[i.barcode] = (sold30[i.barcode] ?? 0) + i.quantity;
    }
  }

  final restock = <RestockAlert>[];
  final slowMovers = <Product>[];
  var stockValue = 0.0;
  double? stockCostValue;
  var outOfStock = 0;
  for (final p in products) {
    stockValue += p.price * p.quantity;
    if (p.costPrice != null) {
      stockCostValue = (stockCostValue ?? 0) + p.costPrice! * p.quantity;
    }
    if (p.quantity <= 0) outOfStock++;
    final sold = sold30[p.barcode] ?? 0;
    if (sold > 0) {
      final perDay = sold / 30;
      final daysLeft = p.quantity / perDay;
      if (daysLeft <= 14) restock.add(RestockAlert(p, perDay, daysLeft));
    } else if (p.quantity > 0) {
      slowMovers.add(p);
    }
  }
  restock.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
  // Most money tied up first.
  slowMovers.sort(
    (a, b) => (b.price * b.quantity).compareTo(a.price * a.quantity),
  );

  return Insights(
    period: period,
    revenue: revenue,
    billCount: inPeriod.length,
    itemsSold: itemsSold,
    previousRevenue: previousRevenue,
    profit: profit,
    costedRevenue: costedRevenue,
    uncostedQty: uncostedQty,
    discountTotal: discountTotal,
    promoSavings: promoSavings,
    byPromo: sorted(byPromo.values, byQty),
    expenses: expenseTotal,
    expensesByCategory: sorted(expenseCats.values, byRev),
    returnCount: returnsInPeriod.length,
    returnedQty: returnedQty,
    refundTotal: refundTotal,
    returnsByReason: sorted(byReason.values, byQty),
    mostReturned: sorted(returnedItems.values, byQty),
    byPayment: sorted(byPayment.values, byRev),
    topByQty: sorted(byItem.values, byQty),
    topByRevenue: sorted(byItem.values, byRev),
    topByProfit: sorted(
      byItem.values.where((s) => s.hasProfit),
      (a, b) => b.profit.compareTo(a.profit),
    ),
    bySize: sorted(bySize.values, byQty),
    byType: sorted(byType.values, byQty),
    trend: trend,
    trendTitle: trendTitle,
    byHour: [for (var h = 0; h < 24; h++) ChartPoint(_hourLabel(h), hourly[h])],
    byWeekday: [
      for (var d = 0; d < 7; d++) ChartPoint(_weekdays[d], weekday[d]),
    ],
    restock: restock,
    slowMovers: slowMovers,
    stockValue: stockValue,
    stockCostValue: stockCostValue,
    outOfStock: outOfStock,
  );
}
