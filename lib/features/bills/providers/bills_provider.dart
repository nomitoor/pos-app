import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_helper.dart';
import '../../../models/bill.dart';
import '../../customers/providers/customers_provider.dart';
import '../../day_close/providers/day_close_provider.dart';
import '../../inventory/providers/inventory_provider.dart';

/// Number of bills that count (voided ones left out).
///
/// It doubles as the "bills changed" signal: screens and reports watch it
/// and then load only the bills they need (a date range, a customer's,
/// one bill by number), instead of the whole history every time.
/// Invalidate it after anything that adds or changes bills.
final billsProvider = AsyncNotifierProvider<BillsNotifier, int>(
  BillsNotifier.new,
);

class BillsNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() => DatabaseHelper.instance.countBills();

  /// Cancels [bill]: stock goes back, it stops counting. See
  /// [DatabaseHelper.voidBill] for the rules.
  Future<void> voidBill(Bill bill, String reason) async {
    await DatabaseHelper.instance.voidBill(bill, reason);
    ref.invalidateSelf();
    ref.invalidate(inventoryProvider);
    ref.invalidate(customerPaymentsProvider);
  }

  // Replaces [bill]'s items and reconciles product stock for the change.
  Future<void> editBill(Bill bill, List<BillItem> newItems) async {
    await DatabaseHelper.instance.updateBill(bill, newItems);
    ref.invalidateSelf();
    ref.invalidate(inventoryProvider);
  }

  void refresh() => ref.invalidateSelf();
}

/// What the Bills screen shows: the last [days] days, or a search across
/// all history when [search] is set. Voided bills are included (marked).
typedef BillHistoryQuery = ({int days, String search});

final billHistoryProvider = FutureProvider.family<List<Bill>, BillHistoryQuery>(
  (ref, q) async {
    await ref.watch(billsProvider.future); // reload when bills change
    final db = DatabaseHelper.instance;
    if (q.search.trim().isNotEmpty) {
      return db.getBills(search: q.search, includeVoided: true, limit: 300);
    }
    final now = DateTime.now();
    final from = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: q.days - 1));
    return db.getBills(from: from, includeVoided: true);
  },
);

/// Whether there are bills older than the Bills screen's window.
final hasOlderBillsProvider = FutureProvider.family<bool, int>((
  ref,
  days,
) async {
  await ref.watch(billsProvider.future);
  final now = DateTime.now();
  final from = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: days - 1));
  final older = await DatabaseHelper.instance.getBills(
    to: from,
    includeVoided: true,
    limit: 1,
  );
  return older.isNotEmpty;
});

/// Last day close time; bills on or before it can't be edited or voided.
final lastDayCloseProvider = FutureProvider<DateTime?>((ref) async {
  final closes = await ref.watch(dayClosesProvider.future); // newest first
  return closes.isEmpty ? null : closes.first.closedAt;
});
