import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../models/bill.dart';
import '../../../models/customer.dart';
import '../../../shared/services/whatsapp_service.dart';
import '../../bills/screens/bills_history_screen.dart' show openBillByCode;
import '../../settings/providers/settings_provider.dart';
import '../ledger.dart';
import '../providers/customers_provider.dart';
import 'customer_picker.dart';

final _money = NumberFormat('#,##0', 'en_US');
String _rs(double v) => 'Rs ${_money.format(v)}';

class CustomerDetailScreen extends ConsumerWidget {
  final int customerId;
  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(customerAccountsProvider);

    return accountsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (accounts) {
        final acc = accounts[customerId];
        if (acc == null) {
          return const Scaffold(
            body: Center(child: Text('Customer not found')),
          );
        }
        return _Body(account: acc);
      },
    );
  }
}

class _Body extends ConsumerWidget {
  final CustomerAccount account;
  const _Body({required this.account});

  Customer get c => account.customer;

  void _snack(BuildContext context, String msg, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: error ? Color(0xFFA8432F) : null,
        ),
      );

  Future<void> _edit(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.6,
        child: CustomerForm(
          existing: c,
          onCancel: () => Navigator.pop(ctx),
          onSaved: (_) => Navigator.pop(ctx),
        ),
      ),
    ),
  );

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(customersProvider.notifier).delete(c.id!);
      if (context.mounted) Navigator.pop(context);
    } on StateError catch (e) {
      if (context.mounted) _snack(context, e.message, error: true);
    }
  }

  Future<void> _receivePayment(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<CustomerPayment>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PaymentSheet(customer: c, balance: account.balance),
    );
    if (result == null) return;
    await ref.read(customerPaymentsProvider.notifier).add(result);
    if (context.mounted) {
      _snack(context, 'Payment of ${_rs(result.amount)} recorded');
    }
  }

  Future<void> _remind(BuildContext context, WidgetRef ref) async {
    final settings = await ref.read(shopSettingsProvider.future);
    final ok = await WhatsAppService.open(
      c.phone,
      WhatsAppService.reminderText(c.name, account.balance, settings),
    );
    if (!ok && context.mounted) {
      _snack(context, 'Could not open WhatsApp', error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bal = account.balance;
    final last = account.lastVisit;

    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          IconButton(
            tooltip: 'Edit',
            onPressed: () => _edit(context),
            icon: const Icon(Icons.edit),
          ),
          if (account.bills.isEmpty && account.ledger.isEmpty)
            IconButton(
              tooltip: 'Delete',
              onPressed: () => _delete(context, ref),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Icon(Icons.phone, size: 18, color: Colors.grey),
              const SizedBox(width: 6),
              Text(c.phone, style: const TextStyle(fontSize: 15)),
              if (c.note != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    c.note!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // ── Balance ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bal > 0.5
                  ? const Color(0xFFF7ECE9)
                  : const Color(0xFFEEF3EC),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bal > 0.5
                      ? 'Udhaar balance (owes you)'
                      : bal < -0.5
                      ? 'Store credit (you owe them)'
                      : 'Udhaar balance',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 4),
                Text(
                  _rs(bal.abs()),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: bal > 0.5 ? Color(0xFFA8432F) : Color(0xFF4E7448),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4E7448),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _receivePayment(context, ref),
                        icon: const Icon(Icons.payments),
                        label: const Text('Receive payment'),
                      ),
                    ),
                    if (bal > 0.5) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _remind(context, ref),
                          icon: const Icon(Icons.chat),
                          label: const Text('Remind'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Stats ──
          Row(
            children: [
              _Stat('Spent', _rs(account.totalSpent)),
              _Stat('Bills', '${account.bills.length}'),
              _Stat(
                'Last visit',
                last == null ? '—' : DateFormat('d MMM').format(last),
              ),
            ],
          ),

          // ── Account history ──
          if (account.ledger.isNotEmpty) ...[
            const _Heading('Udhaar history'),
            for (final e in account.ledger)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  e.amount > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                  color: e.amount > 0 ? Color(0xFFA8432F) : Color(0xFF4E7448),
                ),
                title: Text(e.description),
                subtitle: Text(
                  DateFormat('dd MMM yyyy, hh:mm a').format(e.at) +
                      (e.payment?.note == null ? '' : ' • ${e.payment!.note}'),
                ),
                trailing: Text(
                  '${e.amount > 0 ? '+' : '−'} ${_rs(e.amount.abs())}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: e.amount > 0 ? Color(0xFFA8432F) : Color(0xFF4E7448),
                  ),
                ),
                onTap: e.bill == null
                    ? null
                    : () => openBillByCode(context, ref, e.bill!.billNumber),
                onLongPress: e.payment?.id == null
                    ? null
                    : () => _confirmDeletePayment(context, ref, e.payment!),
              ),
          ],

          // ── Purchases ──
          const _Heading('Purchases'),
          if (account.bills.isEmpty)
            const Text(
              'No purchases yet',
              style: TextStyle(color: Colors.grey),
            ),
          for (final b in account.bills)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.receipt_long, color: Color(0xFF16171B)),
              title: Text(b.billNumber),
              subtitle: Text(
                '${DateFormat('dd MMM yyyy').format(b.createdAt)} • '
                '${b.items.fold<int>(0, (s, i) => s + i.quantity)} items • '
                '${b.paymentMethod ?? ''}',
              ),
              trailing: Text(
                _rs(b.totalAmount),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () => openBillByCode(context, ref, b.billNumber),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDeletePayment(
    BuildContext context,
    WidgetRef ref,
    CustomerPayment p,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete payment?'),
        content: Text(
          'Remove the ${_rs(p.amount)} payment from '
          '${DateFormat('d MMM yyyy').format(p.createdAt)}? '
          'Their balance will go up by that amount.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFA8432F)),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(customerPaymentsProvider.notifier).delete(p.id!);
    }
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    ),
  );
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 4),
    child: Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    ),
  );
}

class _PaymentSheet extends StatefulWidget {
  final Customer customer;
  final double balance;
  const _PaymentSheet({required this.customer, required this.balance});

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  late final _amount = TextEditingController(
    text: widget.balance > 0 ? widget.balance.toStringAsFixed(0) : '',
  );
  final _note = TextEditingController();
  String _method = Bill.cash;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payment from ${widget.customer.name}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (widget.balance > 0)
              Text(
                'Balance due: ${_rs(widget.balance)}',
                style: const TextStyle(color: Color(0xFFA8432F)),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: 'Rs ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in Bill.moneyMethods)
                  ChoiceChip(
                    label: Text(m),
                    selected: _method == m,
                    onSelected: (_) => setState(() => _method = m),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4E7448),
                  foregroundColor: Colors.white,
                ),
                onPressed: amount <= 0
                    ? null
                    : () => Navigator.pop(
                        context,
                        CustomerPayment(
                          customerId: widget.customer.id!,
                          amount: amount,
                          method: _method,
                          note: _note.text.trim().isEmpty
                              ? null
                              : _note.text.trim(),
                          createdAt: DateTime.now(),
                        ),
                      ),
                child: Text('Record ${_rs(amount)} • $_method'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
