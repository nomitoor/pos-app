import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../models/bill.dart';
import '../../../models/sale_return.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/returns_provider.dart';
import 'refund_slip_screen.dart';

/// Pick items from [bill] to return, the reason and how to refund.
class ReturnScreen extends ConsumerStatefulWidget {
  final Bill bill;

  /// Called after an exchange is saved, to open billing for the new sale.
  final VoidCallback? onStartExchange;

  const ReturnScreen({super.key, required this.bill, this.onStartExchange});

  @override
  ConsumerState<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends ConsumerState<ReturnScreen> {
  // Per bill line (same index as bill.items).
  late final List<int> _qty;
  late final List<bool> _restock;
  String _reason = SaleReturn.reasons.first;
  late String _method;
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _qty = List.filled(widget.bill.items.length, 0);
    _restock = List.filled(widget.bill.items.length, true);
    _method = widget.bill.paymentMethod ?? Bill.paymentMethods.first;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _setReason(String r) => setState(() {
    _reason = r;
    // Damaged goods shouldn't go back on the shelf by default.
    final damaged = r == 'Defective / damaged';
    for (var i = 0; i < _restock.length; i++) {
      _restock[i] = !damaged;
    }
  });

  /// How many of line [i] can still be returned.
  int _left(int i, Map<String, int> already) {
    final item = widget.bill.items[i];
    // Several lines can share a barcode; split "already returned" across
    // them in order.
    var used = already[item.barcode] ?? 0;
    for (var j = 0; j < i; j++) {
      final other = widget.bill.items[j];
      if (other.barcode == item.barcode) {
        used -= other.quantity;
      }
    }
    return (item.quantity - used.clamp(0, item.quantity)).clamp(
      0,
      item.quantity,
    );
  }

  double get _refund {
    var total = 0.0;
    for (var i = 0; i < _qty.length; i++) {
      if (_qty[i] > 0) {
        total += refundFor(widget.bill, widget.bill.items[i], _qty[i]);
      }
    }
    return total;
  }

  Future<void> _save({required bool exchange}) async {
    final bill = widget.bill;
    final items = <ReturnItem>[
      for (var i = 0; i < _qty.length; i++)
        if (_qty[i] > 0)
          ReturnItem(
            barcode: bill.items[i].barcode,
            name: bill.items[i].name,
            price: bill.items[i].price,
            quantity: _qty[i],
            refund: refundFor(bill, bill.items[i], _qty[i]),
            restocked: _restock[i],
            size: bill.items[i].size,
            type: bill.items[i].type,
            costPrice: bill.items[i].costPrice,
          ),
    ];
    if (items.isEmpty) return;

    final ret = SaleReturn(
      returnNumber: 'RET-${const Uuid().v4().substring(0, 8).toUpperCase()}',
      billId: bill.id,
      billNumber: bill.billNumber,
      items: items,
      reason: _reason,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      refundMethod: _method,
      isExchange: exchange,
      createdAt: DateTime.now(),
    );

    setState(() => _saving = true);
    try {
      await ref.read(returnsProvider.notifier).addReturn(bill, ret);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is StateError ? e.message : 'Return failed: $e'),
            backgroundColor: Color(0xFFA8432F),
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    if (exchange) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      widget.onStartExchange?.call();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Return saved (credit Rs. ${ret.refundAmount.toStringAsFixed(0)}). '
            'Add the new items to the cart.',
          ),
          backgroundColor: Color(0xFF4E7448),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    final settings = await ref.read(shopSettingsProvider.future);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => RefundSlipScreen(ret: ret, settings: settings),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    final already = ref.watch(returnedQtyByBillProvider)[bill.id] ?? const {};
    final refund = _refund;
    final anySelected = _qty.any((q) => q > 0);

    return Scaffold(
      appBar: AppBar(title: Text('Return • ${bill.billNumber}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Sold ${DateFormat('d MMM yyyy, h:mm a').format(bill.createdAt)}'
            '${bill.discount > 0 ? ' • Rs. ${bill.discount.toStringAsFixed(0)} discount (refunds are reduced to match)' : ''}',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          const _Heading('Items to return'),
          for (var i = 0; i < bill.items.length; i++)
            _ItemRow(
              item: bill.items[i],
              left: _left(i, already),
              qty: _qty[i],
              restock: _restock[i],
              refund: _qty[i] == 0
                  ? 0
                  : refundFor(bill, bill.items[i], _qty[i]),
              onQty: (q) => setState(() => _qty[i] = q),
              onRestock: (v) => setState(() => _restock[i] = v),
            ),
          const SizedBox(height: 16),
          const _Heading('Reason'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in SaleReturn.reasons)
                ChoiceChip(
                  label: Text(r),
                  selected: _reason == r,
                  onSelected: (_) => _setReason(r),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: InputDecoration(
              hintText: 'Note (optional)',
              prefixIcon: const Icon(Icons.notes),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _Heading('Refund method'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in [
                ...Bill.moneyMethods,
                // Credit the customer's account (only if there is one).
                if (bill.customerId != null) Bill.udhaar,
              ])
                ChoiceChip(
                  label: Text(m == Bill.udhaar ? 'Reduce udhaar' : m),
                  selected: _method == m,
                  onSelected: (_) => setState(() => _method = m),
                ),
            ],
          ),
          const SizedBox(height: 100),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Refund',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Rs. ${refund.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFA8432F),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: !anySelected || _saving
                          ? null
                          : () => _save(exchange: true),
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Exchange'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFFA8432F),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: !anySelected || _saving
                          ? null
                          : () => _save(exchange: false),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.undo),
                      label: const Text('Refund'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    ),
  );
}

class _ItemRow extends StatelessWidget {
  final BillItem item;
  final int left;
  final int qty;
  final bool restock;
  final double refund;
  final ValueChanged<int> onQty;
  final ValueChanged<bool> onRestock;

  const _ItemRow({
    required this.item,
    required this.left,
    required this.qty,
    required this.restock,
    required this.refund,
    required this.onQty,
    required this.onRestock,
  });

  @override
  Widget build(BuildContext context) {
    final details = [
      ?item.type,
      ?item.size,
      'Rs. ${item.price.toStringAsFixed(0)} each',
      left == item.quantity
          ? '${item.quantity} sold'
          : '$left of ${item.quantity} returnable',
    ].join(' • ');

    return Card(
      elevation: 0,
      color: qty > 0 ? const Color(0xFFF7ECE9) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: qty > 0 ? Color(0xFFE3B5AB) : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: left == 0 ? Colors.grey : null,
                        ),
                      ),
                      Text(
                        left == 0 ? 'Already fully returned' : details,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: qty > 0 ? () => onQty(qty - 1) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                  color: Color(0xFFA8432F),
                ),
                SizedBox(
                  width: 24,
                  child: Text(
                    '$qty',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: qty < left ? () => onQty(qty + 1) : null,
                  icon: const Icon(Icons.add_circle_outline),
                  color: Color(0xFF4E7448),
                ),
              ],
            ),
            if (qty > 0)
              Row(
                children: [
                  SizedBox(
                    height: 32,
                    child: Checkbox(
                      value: restock,
                      onChanged: (v) => onRestock(v ?? true),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => onRestock(!restock),
                      child: Text(
                        restock
                            ? 'Put back in stock'
                            : 'Not restocked (damaged / written off)',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      '- Rs. ${refund.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFFA8432F),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
