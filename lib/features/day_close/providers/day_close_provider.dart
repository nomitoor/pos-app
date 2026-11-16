import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_helper.dart';
import '../../../models/day_close.dart';
import '../../bills/providers/bills_provider.dart';
import '../../customers/providers/customers_provider.dart';
import '../../expenses/providers/expenses_provider.dart';
import '../../returns/providers/returns_provider.dart';
import '../z_report.dart';

final dayClosesProvider =
    AsyncNotifierProvider<DayClosesNotifier, List<DayClose>>(
      DayClosesNotifier.new,
    );

class DayClosesNotifier extends AsyncNotifier<List<DayClose>> {
  @override
  Future<List<DayClose>> build() => DatabaseHelper.instance.getDayCloses();

  Future<void> save(DayClose d) async {
    await DatabaseHelper.instance.saveDayClose(d);
    ref.invalidateSelf();
  }
}

/// Live report for the period since the last close (or since the start of
/// today if the day has never been closed). Recomputed on every change.
final currentZReportProvider = FutureProvider<ZReport>((ref) async {
  final closes = await ref.watch(dayClosesProvider.future);
  final now = DateTime.now();
  final last = closes.isEmpty ? null : closes.first;
  final from =
      last?.closedAt.add(const Duration(milliseconds: 1)) ??
      DateTime(now.year, now.month, now.day);
  await ref.watch(billsProvider.future); // recompute when bills change
  return computeZReport(
    from: from,
    to: now,
    openingFloat: last?.floatKept ?? 0,
    // Only this period's bills (voided ones never count).
    bills: await DatabaseHelper.instance.getBills(from: from),
    returns: await ref.watch(returnsProvider.future),
    expenses: await ref.watch(expensesProvider.future),
    payments: await ref.watch(customerPaymentsProvider.future),
  );
});
