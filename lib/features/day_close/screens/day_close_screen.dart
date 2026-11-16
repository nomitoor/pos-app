import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../../models/day_close.dart';
import '../../../models/shop_settings.dart';
import '../../../shared/services/pdf_service.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/day_close_provider.dart';
import '../z_report.dart';

final _money = NumberFormat('#,##0', 'en_US');
String _rs(double v) => 'Rs ${_money.format(v)}';

class DayCloseScreen extends ConsumerStatefulWidget {
  const DayCloseScreen({super.key});

  @override
  ConsumerState<DayCloseScreen> createState() => _DayCloseScreenState();
}

class _DayCloseScreenState extends ConsumerState<DayCloseScreen> {
  final _counted = TextEditingController();
  final _float = TextEditingController();
  final _note = TextEditingController();
  bool _floatTouched = false;
  bool _saving = false;

  @override
  void dispose() {
    _counted.dispose();
    _float.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _close(ZReport z) async {
    final counted = double.tryParse(_counted.text.trim());
    if (counted == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Count the cash in the drawer and enter it first'),
          backgroundColor: Color(0xFFA8432F),
        ),
      );
      return;
    }
    final floatKept = (double.tryParse(_float.text.trim()) ?? z.openingFloat)
        .clamp(0, counted)
        .toDouble();
    final diff = counted - z.expectedCash;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close the day?'),
        content: Text(
          'Expected ${_rs(z.expectedCash)}, counted ${_rs(counted)}'
          '${diff.abs() < 0.5
              ? ' — balanced.'
              : diff > 0
              ? ' — ${_rs(diff)} extra.'
              : ' — ${_rs(-diff)} short.'}\n\n'
          'Keep ${_rs(floatKept)} in the drawer for tomorrow and take out '
          '${_rs(counted - floatKept)}.\n\n'
          'Sales after this will count towards the next day.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Close day'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    final closedAt = DateTime.now();
    final close = DayClose(
      periodStart: z.from,
      closedAt: closedAt,
      openingFloat: z.openingFloat,
      expectedCash: z.expectedCash,
      countedCash: counted,
      floatKept: floatKept,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      summary: z.toMap(),
    );
    await ref.read(dayClosesProvider.notifier).save(close);
    final settings = await ref.read(shopSettingsProvider.future);
    if (!mounted) return;
    _counted.clear();
    _note.clear();
    _floatTouched = false;
    setState(() => _saving = false);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ZReportPreview(close: close, settings: settings),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zAsync = ref.watch(currentZReportProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Day close'),
        actions: [
          IconButton(
            tooltip: 'Past closes',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DayCloseHistoryScreen()),
            ),
          ),
        ],
      ),
      body: zAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (z) {
          if (!_floatTouched && _float.text.isEmpty) {
            _float.text = z.openingFloat.toStringAsFixed(0);
          }
          final counted = double.tryParse(_counted.text.trim());
          final diff = counted == null ? null : counted - z.expectedCash;
          final methods = {
            ...z.salesByMethod.keys,
            ...z.refundsByMethod.keys,
          }.toList()..sort();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Since ${DateFormat('EEE d MMM, h:mm a').format(z.from)}',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 12),

              // ── Headline ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF16171B), Color(0xFF16171B)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Net sales',
                      style: TextStyle(color: Colors.white70),
                    ),
                    Text(
                      _rs(z.netSales),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${z.billCount} bills • ${z.itemsSold} items • '
                      '${z.returnCount} returns',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              _Section('Sales', [
                _Line('Sales', _rs(z.sales)),
                _Line('Offers given', '− ${_rs(z.offers)}'),
                _Line('Discounts given', '− ${_rs(z.discounts)}'),
                _Line(
                  'Refunds',
                  '− ${_rs(z.refunds)}',
                  color: Color(0xFFA8432F),
                ),
              ]),
              _Section('By payment method', [
                for (final m in methods)
                  _Line(
                    m,
                    _rs(z.salesByMethod[m] ?? 0) +
                        ((z.refundsByMethod[m] ?? 0) > 0
                            ? '  (−${_money.format(z.refundsByMethod[m])} refunds)'
                            : ''),
                  ),
                if (methods.isEmpty) const _Line('No sales yet', ''),
              ]),
              _Section('Udhaar', [
                _Line('Given on credit', _rs(z.udhaarGiven)),
                _Line('Collected', _rs(z.udhaarCollected)),
              ]),
              _Section('Expenses', [
                for (final e in z.expensesByCategory.entries)
                  _Line(e.key, _rs(e.value)),
                _Line('Total', _rs(z.expenses), bold: true),
              ]),

              // ── Cash drawer ──
              _Section('Cash drawer', [
                _Line('Opening float', _rs(z.openingFloat)),
                _Line('+ Cash sales', _rs(z.cashSales)),
                _Line('− Cash refunds', _rs(z.cashRefunds)),
                _Line('+ Udhaar collected in cash', _rs(z.udhaarCollectedCash)),
                _Line('− Expenses from drawer', _rs(z.drawerExpenses)),
                _Line('Expected in drawer', _rs(z.expectedCash), bold: true),
              ]),
              const SizedBox(height: 4),
              TextField(
                controller: _counted,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  labelText: 'Cash counted in drawer',
                  prefixText: 'Rs ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (diff != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: diff.abs() < 0.5
                        ? const Color(0xFFEEF3EC)
                        : diff > 0
                        ? const Color(0xFFF6EFE2)
                        : const Color(0xFFF7ECE9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        diff.abs() < 0.5
                            ? Icons.check_circle
                            : Icons.warning_amber,
                        color: diff.abs() < 0.5
                            ? Color(0xFF4E7448)
                            : diff > 0
                            ? Color(0xFFB07A1E)
                            : Color(0xFFA8432F),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          diff.abs() < 0.5
                              ? 'Balanced. The drawer matches.'
                              : diff > 0
                              ? '${_rs(diff)} EXTRA in the drawer'
                              : '${_rs(-diff)} SHORT in the drawer',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _float,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Keep in drawer for tomorrow',
                        prefixText: 'Rs ',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (_) => setState(() => _floatTouched = true),
                    ),
                  ),
                ],
              ),
              if (counted != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    'Take out ${_rs((counted - (double.tryParse(_float.text) ?? 0)).clamp(0, double.infinity).toDouble())} '
                    '(to bank / owner)',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                decoration: InputDecoration(
                  labelText: 'Note (optional), e.g. reason for shortage',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16171B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _saving ? null : () => _close(z),
                  icon: const Icon(Icons.lock_clock),
                  label: const Text(
                    'Close day & print report',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> lines;
  const _Section(this.title, this.lines);

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: Colors.grey.shade300),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 6),
        ...lines,
      ],
    ),
  );
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color;
  const _Line(this.label, this.value, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// PDF preview of a saved day close, with share.
class ZReportPreview extends StatelessWidget {
  final DayClose close;
  final ShopSettings settings;
  const ZReportPreview({
    super.key,
    required this.close,
    required this.settings,
  });

  Future<Uint8List> _build() => PdfService.buildZReportPdf(
    ZReport.fromMap(close.summary),
    settings,
    countedCash: close.countedCash,
    floatKept: close.floatKept,
    note: close.note,
    closedAt: close.closedAt,
  );

  @override
  Widget build(BuildContext context) {
    final name =
        'day_close_${DateFormat('yyyy-MM-dd_HHmm').format(close.closedAt)}.pdf';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Day close ${DateFormat('d MMM yyyy').format(close.closedAt)}',
        ),
        actions: [
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share),
            onPressed: () async =>
                Printing.sharePdf(bytes: await _build(), filename: name),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) => _build(),
        pdfFileName: name,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
      ),
    );
  }
}

class DayCloseHistoryScreen extends ConsumerWidget {
  const DayCloseHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final closes = ref.watch(dayClosesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Past day closes')),
      body: closes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? const Center(
                child: Text(
                  'No day closes yet',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final c = list[i];
                  final z = ZReport.fromMap(c.summary);
                  final d = c.difference;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      DateFormat('EEE d MMM yyyy, h:mm a').format(c.closedAt),
                    ),
                    subtitle: Text(
                      'Net ${_rs(z.netSales)} • ${z.billCount} bills',
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (d.abs() < 0.5
                                    ? Color(0xFF4E7448)
                                    : d > 0
                                    ? Color(0xFFB07A1E)
                                    : Color(0xFFA8432F))
                                .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        d.abs() < 0.5
                            ? 'Balanced'
                            : d > 0
                            ? '+${_money.format(d)}'
                            : '−${_money.format(-d)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: d.abs() < 0.5
                              ? Color(0xFF4E7448)
                              : d > 0
                              ? Color(0xFF8A5F17)
                              : Color(0xFFA8432F),
                        ),
                      ),
                    ),
                    onTap: () async {
                      final settings = await ref.read(
                        shopSettingsProvider.future,
                      );
                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ZReportPreview(close: c, settings: settings),
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}
