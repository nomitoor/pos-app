import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../models/expense.dart';
import '../providers/expenses_provider.dart';

final _money = NumberFormat('#,##0', 'en_US');
String _rs(double v) => 'Rs ${_money.format(v)}';

IconData _iconFor(String category) => switch (category) {
  'Rent' => Icons.home_work,
  'Salaries' => Icons.badge,
  'Electricity' => Icons.bolt,
  'Gas / Water' => Icons.water_drop,
  'Internet / Phone' => Icons.wifi,
  'Transport' => Icons.local_shipping,
  'Repairs / Maintenance' => Icons.build,
  'Marketing' => Icons.campaign,
  'Packaging / Supplies' => Icons.inventory,
  'Tea / Food' => Icons.local_cafe,
  _ => Icons.receipt,
};

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  Future<void> _edit([Expense? e]) async {
    final result = await showModalBottomSheet<Expense>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ExpenseForm(existing: e),
    );
    if (result != null) {
      await ref.read(expensesProvider.notifier).save(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(expensesProvider);
    final nextMonth = DateTime(_month.year, _month.month + 1);
    final isCurrent = !nextMonth.isBefore(
      DateTime(DateTime.now().year, DateTime.now().month + 1),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (all) {
          final list = all
              .where(
                (e) => !e.date.isBefore(_month) && e.date.isBefore(nextMonth),
              )
              .toList();
          final total = list.fold<double>(0, (s, e) => s + e.amount);
          final byCat = <String, double>{};
          for (final e in list) {
            byCat[e.category] = (byCat[e.category] ?? 0) + e.amount;
          }
          final cats = byCat.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              // ── Month picker ──
              Row(
                children: [
                  IconButton(
                    onPressed: () => setState(
                      () => _month = DateTime(_month.year, _month.month - 1),
                    ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      DateFormat('MMMM yyyy').format(_month),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: isCurrent
                        ? null
                        : () => setState(() => _month = nextMonth),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7ECE9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Spent this month',
                      style: TextStyle(color: Colors.black54),
                    ),
                    Text(
                      _rs(total),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFA8432F),
                      ),
                    ),
                    if (cats.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      for (final c in cats)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(c.key)),
                                  Text(
                                    _rs(c.value),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: total == 0 ? 0 : c.value / total,
                                  minHeight: 6,
                                  color: Color(0xFFA8432F),
                                  backgroundColor: Color(
                                    0xFFA8432F,
                                  ).withValues(alpha: 0.12),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No expenses this month',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              for (final e in list)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFF7ECE9),
                      child: Icon(
                        _iconFor(e.category),
                        color: Color(0xFFA8432F),
                      ),
                    ),
                    title: Text(e.category),
                    subtitle: Text(
                      [
                        DateFormat('d MMM, h:mm a').format(e.date),
                        e.paidFrom,
                        ?e.note,
                      ].join(' • '),
                    ),
                    trailing: Text(
                      _rs(e.amount),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onTap: () => _edit(e),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ExpenseForm extends ConsumerStatefulWidget {
  final Expense? existing;
  const _ExpenseForm({this.existing});

  @override
  ConsumerState<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<_ExpenseForm> {
  late final _amount = TextEditingController(
    text: widget.existing?.amount.toStringAsFixed(0) ?? '',
  );
  late final _note = TextEditingController(text: widget.existing?.note);
  late String _category = widget.existing?.category ?? Expense.categories.first;
  late String _from = widget.existing?.paidFrom ?? Expense.cashDrawer;
  late DateTime _date = widget.existing?.date ?? DateTime.now();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete expense?'),
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
      await ref.read(expensesProvider.notifier).delete(widget.existing!.id!);
      if (mounted) Navigator.pop(context);
    }
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing == null ? 'Add expense' : 'Edit expense',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (widget.existing != null)
                    IconButton(
                      onPressed: _delete,
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Color(0xFFA8432F),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                autofocus: widget.existing == null,
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
              const Text(
                'Category',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in Expense.categories)
                    ChoiceChip(
                      avatar: Icon(_iconFor(c), size: 16),
                      label: Text(c),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Paid from',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in Expense.sources)
                    ChoiceChip(
                      label: Text(s),
                      selected: _from == s,
                      onSelected: (_) => setState(() => _from = s),
                    ),
                ],
              ),
              if (_from == Expense.cashDrawer)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Taken from the shop till; day close will expect '
                    'this much less cash.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _note,
                      decoration: InputDecoration(
                        labelText: 'Note (optional)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 56),
                    ),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) {
                        final now = DateTime.now();
                        setState(
                          () => _date = DateTime(
                            d.year,
                            d.month,
                            d.day,
                            now.hour,
                            now.minute,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(DateFormat('d MMM').format(_date)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFA8432F),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: amount <= 0
                      ? null
                      : () => Navigator.pop(
                          context,
                          Expense(
                            id: widget.existing?.id,
                            category: _category,
                            amount: amount,
                            paidFrom: _from,
                            note: _note.text.trim().isEmpty
                                ? null
                                : _note.text.trim(),
                            date: _date,
                          ),
                        ),
                  child: Text('Save ${_rs(amount)}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
