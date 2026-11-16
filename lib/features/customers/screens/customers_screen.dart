import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../ledger.dart';
import '../providers/customers_provider.dart';
import 'customer_detail_screen.dart';
import 'customer_picker.dart';

final _money = NumberFormat('#,##0', 'en_US');

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _q = '';
  bool _owingOnly = false;

  void _add() => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.6,
        child: CustomerForm(
          onCancel: () => Navigator.pop(ctx),
          onSaved: (_) => Navigator.pop(ctx),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(customerAccountsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add),
        label: const Text('Add'),
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (accounts) {
          final all = accounts.values.toList();
          final owed = all.fold<double>(
            0,
            (s, a) => s + (a.balance > 0 ? a.balance : 0),
          );
          final owingCount = all.where((a) => a.balance > 0.5).length;
          final q = _q.toLowerCase();
          final list =
              all
                  .where(
                    (a) =>
                        (!_owingOnly || a.balance > 0.5) &&
                        (q.isEmpty ||
                            a.customer.name.toLowerCase().contains(q) ||
                            a.customer.phone.contains(q)),
                  )
                  .toList()
                ..sort(
                  (a, b) => _owingOnly
                      ? b.balance.compareTo(a.balance)
                      : a.customer.name.toLowerCase().compareTo(
                          b.customer.name.toLowerCase(),
                        ),
                );

          return Column(
            children: [
              // ── Udhaar summary ──
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: owed > 0
                      ? const Color(0xFFF7ECE9)
                      : const Color(0xFFEEF3EC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet,
                      color: owed > 0 ? Color(0xFFA8432F) : Color(0xFF4E7448),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        owed > 0
                            ? 'Rs ${_money.format(owed)} udhaar outstanding '
                                  'from $owingCount customer${owingCount == 1 ? '' : 's'}'
                            : 'No udhaar outstanding',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search name or phone',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onChanged: (v) => setState(() => _q = v.trim()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Owes'),
                      selected: _owingOnly,
                      onSelected: (v) => setState(() => _owingOnly = v),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const Center(
                        child: Text(
                          'No customers yet',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: list.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, i) => _Row(account: list[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final CustomerAccount account;
  const _Row({required this.account});

  @override
  Widget build(BuildContext context) {
    final c = account.customer;
    final bal = account.balance;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFF4F4F1),
        child: Text(
          c.name.isEmpty ? '?' : c.name[0].toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF16171B),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${c.phone} • ${account.bills.length} bill${account.bills.length == 1 ? '' : 's'}'
        ' • Rs ${_money.format(account.totalSpent)} spent',
      ),
      trailing: bal.abs() < 0.5
          ? null
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Rs ${_money.format(bal.abs())}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: bal > 0 ? Color(0xFFA8432F) : Color(0xFF4E7448),
                  ),
                ),
                Text(
                  bal > 0 ? 'owes' : 'credit',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CustomerDetailScreen(customerId: c.id!),
        ),
      ),
    );
  }
}
