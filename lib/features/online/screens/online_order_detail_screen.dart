import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/online_order.dart';
import '../../../shared/services/whatsapp_service.dart';
import '../../../shared/widgets/text_prompt_dialog.dart';
import '../../bills/screens/bills_history_screen.dart' show openBillByCode;
import '../../settings/providers/settings_provider.dart';
import '../online_orders.dart';
import 'online_orders_screen.dart' show statusColor, timeAgo;

final _money = NumberFormat('#,##0', 'en_US');
String _rs(double v) => 'Rs ${_money.format(v)}';

class OnlineOrderDetailScreen extends ConsumerStatefulWidget {
  final int orderId;
  const OnlineOrderDetailScreen({super.key, required this.orderId});

  @override
  ConsumerState<OnlineOrderDetailScreen> createState() =>
      _OnlineOrderDetailScreenState();
}

class _OnlineOrderDetailScreenState
    extends ConsumerState<OnlineOrderDetailScreen> {
  bool _busy = false;
  List<String>? _stockProblems;

  OnlineOrdersNotifier get _orders => ref.read(onlineOrdersProvider.notifier);

  void _snack(String msg, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: error ? Color(0xFFA8432F) : null,
        ),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkStock());
  }

  Future<void> _checkStock() async {
    final o = _order;
    if (o == null || !o.isNew) return;
    final p = await _orders.stockProblems(o);
    if (mounted) setState(() => _stockProblems = p);
  }

  OnlineOrder? get _order => ref
      .read(onlineOrdersProvider)
      .value
      ?.where((o) => o.id == widget.orderId)
      .firstOrNull;

  /// Runs an action with a spinner; afterwards offers the WhatsApp update.
  Future<void> _run(
    Future<OnlineOrder> Function() action, {
    bool offerWhatsApp = true,
  }) async {
    setState(() => _busy = true);
    try {
      final o = await action();
      if (!mounted) return;
      _snack('Order ${o.orderNo}: ${o.statusLabel}');
      if (offerWhatsApp) await _offerWhatsApp(o);
    } catch (e) {
      if (mounted) {
        _snack(e is StateError ? e.message : 'Failed: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── WhatsApp ──────────────────────────────────────────────

  Future<String> _message(OnlineOrder o) async {
    final shop = (await ref.read(shopSettingsProvider.future)).shopName;
    final hi = 'Assalam-o-Alaikum ${o.customerName}!';
    return switch (o.status) {
      OnlineOrder.confirmed =>
        '$hi Your $shop order *${o.orderNo}* is confirmed ✅\n'
            'Total: *${_rs(o.total)}* (cash on delivery).\n'
            "We'll let you know when it's on the way.",
      OnlineOrder.packed =>
        '$hi Your order *${o.orderNo}* is packed and will be on its way soon 📦',
      OnlineOrder.outForDelivery =>
        '$hi Your order *${o.orderNo}* is out for delivery 🚚\n'
            'Please keep *${_rs(o.total)}* ready. Thank you!',
      OnlineOrder.delivered =>
        'Thank you for shopping with $shop, ${o.customerName}! 🙏\n'
            'We hope you love your order *${o.orderNo}*.',
      OnlineOrder.rejected || OnlineOrder.cancelled =>
        '$hi Sorry, your order *${o.orderNo}* has been cancelled.'
            '${o.statusNote == null ? '' : '\nReason: ${o.statusNote}'}\n'
            'Please message us if you have any questions.',
      _ => '$hi About your $shop order ${o.orderNo}:',
    };
  }

  Future<void> _sendWhatsApp(OnlineOrder o) async {
    final ok = await WhatsAppService.open(o.phone, await _message(o));
    if (!ok && mounted) _snack('Could not open WhatsApp', error: true);
  }

  Future<void> _offerWhatsApp(OnlineOrder o) async {
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tell the customer?'),
        content: Text(
          'Send ${o.customerName} a WhatsApp update: '
          '"${o.statusLabel}".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.chat),
            label: const Text('WhatsApp'),
          ),
        ],
      ),
    );
    if (send == true) await _sendWhatsApp(o);
  }

  // ── Actions ───────────────────────────────────────────────

  Future<void> _accept(OnlineOrder o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Accept ${o.orderNo}?'),
        content: Text(
          '${o.pieces} item${o.pieces == 1 ? '' : 's'} will be '
          'taken out of stock and a bill created for ${o.customerName}. '
          'The ${_rs(o.subtotal)} is recorded as cash-on-delivery owed '
          'until you mark it delivered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(() => _orders.accept(o));
  }

  Future<void> _cancel(OnlineOrder o) async {
    final reason = (await promptText(
      context,
      title: o.isNew ? 'Reject order' : 'Cancel order',
      hint: o.isNew
          ? 'e.g. Size sold out, outside delivery area'
          : 'e.g. Customer not reachable, customer cancelled',
      okLabel: o.isNew ? 'Reject' : 'Cancel order',
    ))?.trim();
    if (reason == null || reason.isEmpty) return;
    await _run(() => _orders.cancel(o, reason));
  }

  Future<void> _delivered(OnlineOrder o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark delivered?'),
        content: Text(
          'Confirm you collected ${_rs(o.total)} in cash '
          '(${_rs(o.subtotal)} goods + ${_rs(o.deliveryFee)} delivery). '
          'The ${_rs(o.subtotal)} goes into today\'s cash drawer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delivered & paid'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(() => _orders.markDelivered(o));
  }

  // ── UI ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final o = ref
        .watch(onlineOrdersProvider)
        .value
        ?.where((x) => x.id == widget.orderId)
        .firstOrNull;
    if (o == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Order not found')),
      );
    }
    final color = statusColor(o.status);

    return Scaffold(
      appBar: AppBar(title: Text(o.orderNo)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // ── Status ──
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.circle, size: 12, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.statusLabel,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Ordered ${timeAgo(o.createdAt)} · '
                        '${DateFormat('d MMM, h:mm a').format(o.createdAt)}',
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 12,
                        ),
                      ),
                      if (o.statusNote != null)
                        Text(
                          'Reason: ${o.statusNote}',
                          style: const TextStyle(fontSize: 13),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Customer ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    o.customerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(o.phone, style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 8),
                  Text(
                    [o.address, o.area, o.city].whereType<String>().join(', '),
                  ),
                  if (o.notes != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Note: ${o.notes}',
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => launchUrl(Uri.parse('tel:${o.phone}')),
                        icon: const Icon(Icons.call, size: 18),
                        label: const Text('Call'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _sendWhatsApp(o),
                        icon: const Icon(Icons.chat, size: 18),
                        label: const Text('WhatsApp'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse(
                            'https://www.google.com/maps/search/?api=1'
                            '&query=${Uri.encodeComponent([o.address, o.area, o.city].whereType<String>().join(', '))}',
                          ),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: const Text('Map'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(
                              text:
                                  '${o.customerName}\n${o.phone}\n'
                                  '${[o.address, o.area, o.city].whereType<String>().join(', ')}\n'
                                  'COD ${_rs(o.total)} · ${o.orderNo}',
                            ),
                          );
                          _snack('Delivery details copied');
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy for rider'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Items ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  for (final i in o.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${i.quantity} × ${i.name}'
                              '${i.size == null ? '' : ' (${i.size})'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(_rs(i.subtotal)),
                        ],
                      ),
                    ),
                  const Divider(height: 20),
                  _line('Subtotal', _rs(o.subtotal)),
                  _line('Delivery', _rs(o.deliveryFee)),
                  _line('Total (COD)', _rs(o.total), bold: true),
                ],
              ),
            ),
          ),

          // ── Stock warning (new orders) ──
          if (o.isNew && (_stockProblems?.isNotEmpty ?? false))
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7ECE9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Not enough stock to accept:\n${_stockProblems!.join('\n')}\n\n'
                'Restock in the POS, or reject the order with a reason.',
                style: const TextStyle(color: Color(0xFF7E3021)),
              ),
            ),

          const SizedBox(height: 20),
          ..._actions(o),

          if (o.posBillNumber != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => openBillByCode(context, ref, o.posBillNumber!),
              icon: const Icon(Icons.receipt_long),
              label: Text('View POS bill ${o.posBillNumber}'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(String a, String b, {bool bold = false}) {
    final s = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
      fontSize: bold ? 16 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(a, style: s)),
          Text(b, style: s),
        ],
      ),
    );
  }

  List<Widget> _actions(OnlineOrder o) {
    Widget primary(String label, IconData icon, VoidCallback onTap) => SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _busy ? null : onTap,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon),
        label: Text(label),
      ),
    );
    Widget cancel(String label) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(foregroundColor: Color(0xFFA8432F)),
        onPressed: _busy ? null : () => _cancel(o),
        child: Text(label),
      ),
    );

    return switch (o.status) {
      OnlineOrder.pending => [
        primary('Accept order', Icons.check_circle, () => _accept(o)),
        cancel('Reject'),
      ],
      OnlineOrder.confirmed => [
        primary(
          'Mark packed',
          Icons.inventory_2,
          () => _run(() => _orders.markPacked(o)),
        ),
        cancel('Cancel order'),
      ],
      OnlineOrder.packed => [
        primary(
          'Out for delivery',
          Icons.local_shipping,
          () => _run(() => _orders.markOutForDelivery(o)),
        ),
        cancel('Cancel order'),
      ],
      OnlineOrder.outForDelivery => [
        primary('Delivered & paid', Icons.payments, () => _delivered(o)),
        cancel('Cancel order'),
      ],
      _ => const [],
    };
  }
}
