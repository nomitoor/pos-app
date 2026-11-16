import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/bill.dart';
import '../../../models/customer.dart';
import '../../../models/shop_settings.dart';
import '../../../shared/services/pdf_service.dart';
import '../../../shared/services/whatsapp_service.dart';
import '../../customers/ledger.dart';
import '../../customers/providers/customers_provider.dart';
import '../../printing/printer_settings.dart';
import '../../printing/thermal_printer.dart';
import '../../printing/thermal_receipt.dart';

/// Shown right after checkout and when opening a past bill.
class InvoicePreviewScreen extends ConsumerWidget {
  final Bill bill;
  final ShopSettings settings;

  const InvoicePreviewScreen({
    super.key,
    required this.bill,
    required this.settings,
  });

  /// Sends the bill on WhatsApp: as a PDF in the Android app, as a text
  /// receipt in the browser. Uses the bill's customer number when there is
  /// one; otherwise asks (walk-in customers).
  Future<void> _sendWhatsApp(
    BuildContext context,
    double unpaid,
    double paidOnBill,
  ) async {
    final asPdf = WhatsAppService.canSendPdf;
    var phone = bill.customerPhone ?? '';
    if (phone.isEmpty) {
      final entered = await showDialog<String>(
        context: context,
        builder: (_) => _PhoneDialog(allowPickInWhatsApp: asPdf),
      );
      if (entered == null) return; // cancelled
      phone = entered; // '' = choose the chat inside WhatsApp
    }

    void fail(String msg) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.danger),
      );
    }

    if (asPdf) {
      final result = await WhatsAppService.sendPdf(
        bytes: await PdfService.buildBillPdf(bill, settings, paidOnBill),
        fileName: '${bill.billNumber}.pdf',
        phone: phone,
        caption: WhatsAppService.pdfCaption(bill, settings),
      );
      switch (result) {
        case PdfShareResult.sent:
          break;
        case PdfShareResult.notInstalled:
          fail('WhatsApp is not installed on this phone.');
        case PdfShareResult.failed:
          fail("Couldn't open WhatsApp. Try Share PDF instead.");
      }
      return;
    }

    final ok = await WhatsAppService.open(
      phone,
      WhatsAppService.receiptText(
        bill,
        settings,
        unpaid: bill.isUdhaar ? unpaid : null,
      ),
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "WhatsApp didn't open. Check it's installed and try again.",
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  /// Prints the receipt on the Bluetooth thermal printer.
  Future<void> _print(
    BuildContext context,
    WidgetRef ref,
    double unpaid,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final printer = await ref.read(printerSettingsProvider.future);
    final bytes = await ThermalReceipt.bill(
      bill,
      settings,
      printer.paper,
      unpaid: bill.isUdhaar ? unpaid : null,
    );
    final error = await ThermalPrinter.printBytes(printer, bytes);
    messenger.showSnackBar(
      SnackBar(
        content: Text(error ?? 'Receipt printed'),
        backgroundColor: error == null ? null : AppTheme.danger,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(customerPaymentsProvider).value ?? const [];
    final unpaid = unpaidOnBill(bill, payments);
    final paidOnBill = bill.totalAmount - unpaid;
    final hasPhone = (bill.customerPhone ?? '').isNotEmpty;
    final canPrint = ThermalPrinter.supported;

    final whatsApp = canPrint
        ? OutlinedButton.icon(
            style: OutlinedButton.styleFrom(backgroundColor: AppTheme.surface),
            onPressed: () => _sendWhatsApp(context, unpaid, paidOnBill),
            icon: const Icon(Icons.chat_outlined),
            label: Text(
              hasPhone
                  ? 'WhatsApp ${bill.customerName ?? ''}'.trim()
                  : 'WhatsApp',
              overflow: TextOverflow.ellipsis,
            ),
          )
        : FilledButton.icon(
            onPressed: () => _sendWhatsApp(context, unpaid, paidOnBill),
            icon: const Icon(Icons.chat_outlined),
            label: Text(
              hasPhone
                  ? 'Send to ${bill.customerName ?? bill.customerPhone}'
                  : 'Send on WhatsApp',
              overflow: TextOverflow.ellipsis,
            ),
          );

    return Scaffold(
      appBar: AppBar(title: Text(bill.billNumber)),
      body: PdfPreview(
        build: (format) => PdfService.buildBillPdf(bill, settings, paidOnBill),
        pdfFileName: '${bill.billNumber}.pdf',
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        // Our own Share/WhatsApp buttons sit below; keep the print one.
        allowSharing: false,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // At the counter, printing is the usual next step.
                if (canPrint) ...[
                  _PrintButton(onPrint: () => _print(context, ref, unpaid)),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(flex: 3, child: whatsApp),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: AppTheme.surface,
                        ),
                        onPressed: () async => Printing.sharePdf(
                          bytes: await PdfService.buildBillPdf(
                            bill,
                            settings,
                            paidOnBill,
                          ),
                          filename: '${bill.billNumber}.pdf',
                        ),
                        icon: const Icon(Icons.ios_share_rounded),
                        label: const Text('Share PDF'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Print receipt", with a spinner while the printer works so it isn't
/// tapped twice.
class _PrintButton extends StatefulWidget {
  final Future<void> Function() onPrint;
  const _PrintButton({required this.onPrint});

  @override
  State<_PrintButton> createState() => _PrintButtonState();
}

class _PrintButtonState extends State<_PrintButton> {
  bool _printing = false;

  Future<void> _run() async {
    setState(() => _printing = true);
    try {
      await widget.onPrint();
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: _printing ? null : _run,
      icon: _printing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.print_rounded),
      label: Text(_printing ? 'Printing…' : 'Print receipt'),
    );
  }
}

/// Asks for the customer's WhatsApp number. Returns it, '' to pick the chat
/// inside WhatsApp, or null if cancelled. Owns its controller so it is
/// disposed after the dialog closes.
class _PhoneDialog extends StatefulWidget {
  /// Offer "Choose chat in WhatsApp" (only possible when sending the PDF).
  final bool allowPickInWhatsApp;
  const _PhoneDialog({this.allowPickInWhatsApp = false});

  @override
  State<_PhoneDialog> createState() => _PhoneDialogState();
}

class _PhoneDialogState extends State<_PhoneDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final digits = Customer.whatsappNumber(_controller.text);
    // International numbers are 11–15 digits (Pakistan: 92 + 10).
    if (digits.length < 11 || digits.length > 15) {
      setState(() => _error = 'Enter a mobile number, like 0300 1234567');
      return;
    }
    Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send bill on WhatsApp'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]')),
        ],
        decoration: InputDecoration(
          labelText: "Customer's mobile number",
          hintText: '0300 1234567',
          prefixIcon: const Icon(Icons.phone_outlined),
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        if (widget.allowPickInWhatsApp)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Choose chat in WhatsApp'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Send')),
      ],
    );
  }
}
