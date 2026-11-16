import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/database_helper.dart';
import '../bills/providers/bills_provider.dart';
import '../inventory/providers/inventory_provider.dart';
import '../returns/providers/returns_provider.dart';
import '../expenses/providers/expenses_provider.dart';
import 'insights_data.dart';

final insightsPeriodProvider = StateProvider<InsightPeriod>(
  (ref) => InsightPeriod.today,
);

/// Insights for a period, recomputed whenever bills, returns or inventory
/// change.
final insightsProvider = FutureProvider.family<Insights, InsightPeriod>((
  ref,
  period,
) async {
  await ref.watch(billsProvider.future); // recompute when bills change
  // Load only what the report reads: the period, the one before it (for
  // the comparison) and the last 30 days (restock alerts).
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final start = periodStart(period, now);
  DateTime? from;
  if (start != null) {
    final length = today.difference(start).inDays + 1;
    final prevStart = start.subtract(Duration(days: length));
    final last30 = today.subtract(const Duration(days: 29));
    from = prevStart.isBefore(last30) ? prevStart : last30;
  }
  final bills = await DatabaseHelper.instance.getBills(from: from);
  final products = await ref.watch(inventoryProvider.future);
  final returns = await ref.watch(returnsProvider.future);
  final expenses = await ref.watch(expensesProvider.future);
  return computeInsights(
    bills: bills,
    products: products,
    returns: returns,
    expenses: expenses,
    period: period,
  );
});
