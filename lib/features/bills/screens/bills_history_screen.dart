import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/bills_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/bill.dart';
import '../../settings/providers/settings_provider.dart';
import 'edit_bill_screen.dart';
import 'invoice_preview_screen.dart';
import '../../../core/navigation.dart';
import '../../returns/providers/returns_provider.dart';
import '../../returns/screens/return_screen.dart';
import '../../returns/screens/returns_history_screen.dart';
import '../../../shared/widgets/scan_code_screen.dart';
import '../bill_lookup.dart';

final _money = NumberFormat('#,##0', 'en_US');
String _rs(double v) => 'Rs ${_money.format(v)}';

/// How many days the list shows at first, and adds per "Show more".
const _pageDays = 30;

/// 0 = nothing returned, 1 = partly, 2 = fully returned.
int _returnState(Bill bill, Map<String, int>? returned) {
  if (returned == null || returned.isEmpty) return 0;
  final sold = bill.items.fold<int>(0, (s, i) => s + i.quantity);
  final back = returned.values.fold<int>(0, (s, q) => s + q);
  return back >= sold ? 2 : 1;
}

Future<void> _previewBill(
  BuildContext context,
  WidgetRef ref,
  Bill bill,
) async {
  final settings = await ref.read(shopSettingsProvider.future);
  if (!context.mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => InvoicePreviewScreen(bill: bill, settings: settings),
    ),
  );
}

/// Opens the bill for an invoice or credit-note number (as scanned from a
/// receipt barcode). Returns false, after telling the user, if not found.
Future<bool> openBillByCode(
  BuildContext context,
  WidgetRef ref,
  String code,
) async {
  final returns = await ref.read(returnsProvider.future);
  final found = await lookupBillByCode(code, returns);
  if (!context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);

  if (found.bill == null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          found.viaReturn != null
              ? 'Credit note ${found.viaReturn!.returnNumber} found, but its '
                    'bill ${found.viaReturn!.billNumber} is no longer on record.'
              : 'No bill found for "$code".',
        ),
        backgroundColor: AppTheme.warning,
      ),
    );
    return false;
  }
  if (found.viaReturn != null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Credit note ${found.viaReturn!.returnNumber}: '
          'showing original bill ${found.bill!.billNumber}',
        ),
      ),
    );
  }
  await _BillDetail.show(context, ref, found.bill!);
  return true;
}

class BillsHistoryScreen extends ConsumerStatefulWidget {
  const BillsHistoryScreen({super.key});

  @override
  ConsumerState<BillsHistoryScreen> createState() => _BillsHistoryScreenState();
}

class _BillsHistoryScreenState extends ConsumerState<BillsHistoryScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  int _days = _pageDays;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Search runs against the database, so wait for a pause in typing.
  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = v);
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    setState(() {
      _search.clear();
      _query = '';
    });
  }

  /// Opens the camera, then the bill whose invoice or credit-note barcode
  /// was scanned.
  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanCodeScreen(
          title: 'Scan receipt',
          hint: 'Scan the barcode at the bottom of the invoice or credit note',
        ),
      ),
    );
    if (code == null || !mounted) return;
    openBillByCode(context, ref, code);
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.trim().isNotEmpty;
    final billsAsync = ref.watch(
      billHistoryProvider((days: _days, search: _query)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bills'),
        actions: [
          IconButton(
            tooltip: 'Scan receipt',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _scan,
          ),
          IconButton(
            tooltip: 'Returns & refunds',
            icon: const Icon(Icons.assignment_return_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReturnsHistoryScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(billsProvider.notifier).refresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search all bills: number, item, customer or amount',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? IconButton(
                        tooltip: 'Scan receipt',
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: _scan,
                      )
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: _clearSearch,
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (v) {
                setState(() {}); // swap the scan / clear icon
                _onSearchChanged(v);
              },
              // Enter on an exact number (e.g. from a USB/Bluetooth
              // barcode scanner, which types it) opens that bill.
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) openBillByCode(context, ref, v);
              },
            ),
          ),
          Expanded(
            child: billsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text("Bills couldn't load: $e")),
              data: (all) {
                final bills = searching
                    ? all.where((b) => billMatches(b, _query)).toList()
                    : all;
                final hasOlder =
                    !searching &&
                    (ref.watch(hasOlderBillsProvider(_days)).value ?? false);

                if (bills.isEmpty && !hasOlder) {
                  return _Empty(
                    searching
                        ? 'No bills match "$_query".'
                        : (ref.watch(billsProvider).value ?? 0) == 0
                        ? 'No bills yet. They appear here after checkout.'
                        : 'No bills in the last $_days days.',
                  );
                }
                return _BillList(
                  bills: bills,
                  footer: hasOlder
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  setState(() => _days += _pageDays),
                              icon: const Icon(Icons.history),
                              label: Text(
                                bills.isEmpty
                                    ? 'No bills in the last $_days days. '
                                          'Show older'
                                    : 'Show $_pageDays more days',
                              ),
                            ),
                          ),
                        )
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.receipt_long_outlined,
            size: 56,
            color: AppTheme.muted,
          ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.muted),
          ),
        ],
      ),
    ),
  );
}

/// Bills grouped by day, each day headed by its bill count and total.
class _BillList extends StatelessWidget {
  final List<Bill> bills; // newest first
  final Widget? footer;
  const _BillList({required this.bills, this.footer});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    DateTime? day;
    for (var i = 0; i < bills.length; i++) {
      final b = bills[i];
      final d = DateTime(b.createdAt.year, b.createdAt.month, b.createdAt.day);
      if (d != day) {
        day = d;
        final sameDay = bills.where(
          (x) =>
              !x.isVoided &&
              x.createdAt.year == d.year &&
              x.createdAt.month == d.month &&
              x.createdAt.day == d.day,
        );
        rows.add(
          _DayHeader(
            day: d,
            count: sameDay.length,
            total: sameDay.fold(0, (s, x) => s + x.totalAmount),
          ),
        );
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _BillCard(bill: b),
        ),
      );
    }
    if (footer != null) rows.add(footer!);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: rows,
    );
  }
}

class _DayHeader extends StatelessWidget {
  final DateTime day;
  final int count;
  final double total;
  const _DayHeader({
    required this.day,
    required this.count,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final label = day == today
        ? 'Today'
        : day == today.subtract(const Duration(days: 1))
        ? 'Yesterday'
        : DateFormat('EEE d MMM yyyy').format(day);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const Spacer(),
          Text(
            '$count bill${count == 1 ? '' : 's'}, ${_rs(total)}',
            style: const TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
    ),
  );
}

class _BillCard extends ConsumerWidget {
  final Bill bill;
  const _BillCard({required this.bill});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final time = DateFormat('hh:mm a').format(bill.createdAt);
    final itemCount = bill.items.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );
    final returnState = _returnState(
      bill,
      ref.watch(returnedQtyByBillProvider)[bill.id],
    );
    final voided = bill.isVoided;

    return Card(
      child: InkWell(
        onTap: () => _BillDetail.show(context, ref, bill),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            bill.billNumber,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: voided ? AppTheme.muted : null,
                            ),
                          ),
                        ),
                        if (voided) ...[
                          const SizedBox(width: 6),
                          const _Tag('Voided', AppTheme.danger),
                        ] else if (returnState > 0) ...[
                          const SizedBox(width: 6),
                          _Tag(
                            returnState == 2 ? 'Returned' : 'Part returned',
                            AppTheme.warning,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        time,
                        '$itemCount item${itemCount == 1 ? '' : 's'}',
                        ?bill.customerName,
                        ?bill.paymentMethod,
                      ].join(', '),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _rs(bill.totalAmount),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: voided ? AppTheme.muted : AppTheme.ink,
                  decoration: voided ? TextDecoration.lineThrough : null,
                ),
              ),
              if (!voided)
                IconButton(
                  tooltip: 'Invoice PDF',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: () => _previewBill(context, ref, bill),
                )
              else
                const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet with a bill's lines and what can be done with it.
class _BillDetail {
  static Future<void> show(
    BuildContext context,
    WidgetRef ref,
    Bill bill,
  ) async {
    final returnState = _returnState(
      bill,
      ref.read(returnedQtyByBillProvider)[bill.id],
    );
    final closedAt = await ref.read(lastDayCloseProvider.future);
    if (!context.mounted) return;
    final dayClosed = closedAt != null && !bill.createdAt.isAfter(closedAt);

    // Why Edit / Void aren't offered, if they aren't.
    final String? lockReason = bill.isVoided
        ? null
        : dayClosed
        ? 'This day was closed on '
              '${DateFormat('d MMM, hh:mm a').format(closedAt)}, so the bill '
              "can't be edited or voided. Use Return to refund items."
        : returnState > 0
        ? "This bill has returns, so it can't be edited or voided. "
              'Return the remaining items instead.'
        : null;
    final canChange = !bill.isVoided && lockReason == null;

    void go(Widget screen) {
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    bill.billNumber,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (bill.isVoided) const _Tag('Voided', AppTheme.danger),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                DateFormat('dd MMM yyyy, hh:mm a').format(bill.createdAt),
                // Internal running number; not printed on the invoice.
                if (bill.serial != null) 'Serial ${bill.serial}',
              ].join(', '),
              style: const TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
            if (bill.isVoided) ...[
              const SizedBox(height: 12),
              _Notice(
                icon: Icons.block,
                color: AppTheme.danger,
                text:
                    'Voided on '
                    '${DateFormat('d MMM yyyy, hh:mm a').format(bill.voidedAt!)}'
                    '${bill.voidReason == null ? '' : ': ${bill.voidReason}'}. '
                    "It doesn't count in sales, stock or udhaar.",
              ),
            ],
            const Divider(height: 24),
            for (final item in bill.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.size == null
                            ? item.name
                            : '${item.name} (${item.size})',
                      ),
                    ),
                    Text(
                      'x${item.quantity}',
                      style: const TextStyle(color: AppTheme.muted),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _rs(item.subtotal),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            const Divider(),
            if (bill.discount > 0) ...[
              _row('Subtotal', _rs(bill.subtotal)),
              _row(
                'Discount',
                '- ${_rs(bill.discount)}',
                color: AppTheme.danger,
              ),
            ],
            if (bill.customerName != null)
              _row('Customer', bill.customerName!, color: AppTheme.muted),
            if (bill.paymentMethod != null)
              _row('Paid by', bill.paymentMethod!, color: AppTheme.muted),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text(
                  'Total',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const Spacer(),
                Text(
                  _rs(bill.totalAmount),
                  style: AppTheme.figure(
                    20,
                    color: bill.isVoided ? AppTheme.muted : AppTheme.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (!bill.isVoided) ...[
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _previewBill(context, ref, bill);
                },
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Invoice: print, WhatsApp or PDF'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: canChange
                          ? () => go(EditBillScreen(bill: bill))
                          : null,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: returnState == 2
                          ? null
                          : () => go(
                              ReturnScreen(
                                bill: bill,
                                onStartExchange: () =>
                                    ref.read(navIndexProvider.notifier).state =
                                        Tabs.billing,
                              ),
                            ),
                      icon: const Icon(Icons.assignment_return_outlined),
                      label: Text(
                        returnState == 2 ? 'Fully returned' : 'Return',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                  side: BorderSide(
                    color: canChange
                        ? AppTheme.danger.withValues(alpha: 0.5)
                        : AppTheme.border,
                  ),
                ),
                onPressed: canChange
                    ? () async {
                        Navigator.pop(sheetContext);
                        await _voidBill(context, ref, bill);
                      }
                    : null,
                icon: const Icon(Icons.block),
                label: const Text('Void bill'),
              ),
              if (lockReason != null) ...[
                const SizedBox(height: 12),
                _Notice(
                  icon: Icons.lock_outline,
                  color: AppTheme.muted,
                  text: lockReason,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static Widget _row(String label, String value, {Color? color}) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Text(label, style: TextStyle(color: color)),
        const Spacer(),
        Text(value, style: TextStyle(color: color)),
      ],
    ),
  );

  static Future<void> _voidBill(
    BuildContext context,
    WidgetRef ref,
    Bill bill,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _VoidDialog(bill: bill),
    );
    if (reason == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(billsProvider.notifier).voidBill(bill, reason);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${bill.billNumber} voided. Its items are back in stock.',
          ),
        ),
      );
    } on StateError catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppTheme.danger),
      );
    }
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Notice({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}

/// Asks why a bill is being voided. Returns the reason, or null.
class _VoidDialog extends StatefulWidget {
  final Bill bill;
  const _VoidDialog({required this.bill});

  @override
  State<_VoidDialog> createState() => _VoidDialogState();
}

class _VoidDialogState extends State<_VoidDialog> {
  static const _reasons = [
    'Wrong items rung up',
    'Customer cancelled',
    'Duplicate bill',
    'Test bill',
  ];
  final _other = TextEditingController();
  String? _picked;

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  String get _reason =>
      _other.text.trim().isNotEmpty ? _other.text.trim() : (_picked ?? '');

  @override
  Widget build(BuildContext context) {
    final b = widget.bill;
    return AlertDialog(
      title: Text('Void ${b.billNumber}?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Its ${b.items.fold<int>(0, (s, i) => s + i.quantity)} item(s) '
              'go back into stock and ${_rs(b.totalAmount)} comes off '
              "today's sales${b.isUdhaar ? ' and the customer\'s udhaar' : ''}. "
              'The bill stays in history, marked Voided.',
            ),
            const SizedBox(height: 16),
            const Text('Reason', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in _reasons)
                  ChoiceChip(
                    label: Text(r),
                    selected: _picked == r && _other.text.trim().isEmpty,
                    onSelected: (_) => setState(() {
                      _picked = r;
                      _other.clear();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _other,
              decoration: const InputDecoration(hintText: 'Or type a reason'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Keep bill'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
          onPressed: _reason.isEmpty
              ? null
              : () => Navigator.pop(context, _reason),
          child: const Text('Void bill'),
        ),
      ],
    );
  }
}
