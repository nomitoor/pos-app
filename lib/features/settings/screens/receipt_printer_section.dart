import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../printing/printer_settings.dart';
import '../../printing/thermal_printer.dart';
import '../../printing/thermal_receipt.dart';
import '../providers/settings_provider.dart';

/// Settings → Receipt printer: pick the paired Bluetooth printer, set the
/// roll width and print a test slip. Changes save immediately.
class ReceiptPrinterSection extends ConsumerStatefulWidget {
  const ReceiptPrinterSection({super.key});

  @override
  ConsumerState<ReceiptPrinterSection> createState() =>
      _ReceiptPrinterSectionState();
}

class _ReceiptPrinterSectionState extends ConsumerState<ReceiptPrinterSection> {
  bool _busy = false;

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppTheme.danger : null,
      ),
    );
  }

  Future<void> _choosePrinter(PrinterSettings current) async {
    setState(() => _busy = true);
    final (devices, error) = await ThermalPrinter.paired();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) return _snack(error, error: true);

    final picked = await showModalBottomSheet<PairedDevice>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                'Choose your printer',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                "Not listed? Turn the printer on and pair it in your phone's "
                'Bluetooth settings first (the PIN is usually 0000 or 1234).',
                style: TextStyle(color: AppTheme.muted),
              ),
            ),
            if (devices.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Text('No paired Bluetooth devices yet.'),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final d in devices)
                      ListTile(
                        leading: const Icon(Icons.print_outlined),
                        title: Text(d.name.isEmpty ? 'Unnamed device' : d.name),
                        subtitle: Text(d.address),
                        trailing: d.address == current.address
                            ? const Icon(
                                Icons.check_rounded,
                                color: AppTheme.ink,
                              )
                            : null,
                        onTap: () => Navigator.pop(ctx, d),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await ThermalPrinter.disconnect(); // drop any link to the old printer
    await ref
        .read(printerSettingsProvider.notifier)
        .save(current.copyWith(address: picked.address, name: picked.name));
    _snack('${picked.name} is now your receipt printer');
  }

  Future<void> _testPrint(PrinterSettings printer) async {
    setState(() => _busy = true);
    final shop = ref.read(shopSettingsProvider).value?.shopName ?? '';
    final error = await ThermalPrinter.printBytes(
      printer,
      await ThermalReceipt.test(printer.paper, shop),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(error ?? 'Test slip sent to ${printer.name}', error: error != null);
  }

  @override
  Widget build(BuildContext context) {
    final printer = ref.watch(printerSettingsProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Text(
          'Receipt printer',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Bluetooth thermal printer for till receipts.',
          style: TextStyle(color: AppTheme.muted),
        ),
        const SizedBox(height: 12),
        if (!ThermalPrinter.supported)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Set up the receipt printer in the Android app. In the '
                'browser, use Share PDF on a bill instead.',
                style: TextStyle(color: AppTheme.muted),
              ),
            ),
          )
        else if (printer == null)
          const LinearProgressIndicator()
        else
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  leading: const Icon(Icons.print_outlined),
                  title: Text(
                    printer.isSet
                        ? (printer.name ?? 'Printer')
                        : 'No printer chosen',
                  ),
                  subtitle: Text(
                    printer.isSet
                        ? printer.address!
                        : 'Tap to choose a paired Bluetooth printer',
                  ),
                  trailing: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: _busy ? null : () => _choosePrinter(printer),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Paper width',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<PaperWidth>(
                        segments: [
                          for (final p in PaperWidth.values)
                            ButtonSegment(value: p, label: Text(p.label)),
                        ],
                        selected: {printer.paper},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) => ref
                            .read(printerSettingsProvider.notifier)
                            .save(printer.copyWith(paper: s.first)),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Not sure? Print a test slip: it tells you which '
                        'width to pick.',
                        style: TextStyle(color: AppTheme.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: (!printer.isSet || _busy)
                            ? null
                            : () => _testPrint(printer),
                        icon: const Icon(Icons.receipt_outlined),
                        label: const Text('Print test slip'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
