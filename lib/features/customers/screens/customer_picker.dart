import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../models/customer.dart';
import '../providers/customers_provider.dart';

final _money = NumberFormat('#,##0', 'en_US');

/// Bottom sheet to choose a customer or add a new one. Pops with the
/// chosen [Customer] (saved, with id), or null.
Future<Customer?> pickCustomer(BuildContext context) =>
    showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CustomerPicker(),
    );

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker();

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  final _search = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider).value ?? const [];
    final accounts = ref.watch(customerAccountsProvider).value ?? const {};
    final q = _search.text.trim().toLowerCase();
    final digits = q.replaceAll(RegExp(r'\D'), '');
    final list = customers
        .where(
          (c) =>
              q.isEmpty ||
              c.name.toLowerCase().contains(q) ||
              (digits.isNotEmpty &&
                  c.phone.replaceAll(RegExp(r'\D'), '').contains(digits)),
        )
        .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: _adding
              ? CustomerForm(
                  initialQuery: _search.text.trim(),
                  onCancel: () => setState(() => _adding = false),
                  onSaved: (c) => Navigator.pop(context, c),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                        controller: _search,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Search name or phone',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFF16171B),
                        child: Icon(Icons.person_add, color: Colors.white),
                      ),
                      title: Text(
                        q.isEmpty
                            ? 'New customer'
                            : 'Add "${_search.text.trim()}" as new customer',
                      ),
                      onTap: () => setState(() => _adding = true),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final c in list)
                            ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  c.name.isEmpty
                                      ? '?'
                                      : c.name[0].toUpperCase(),
                                ),
                              ),
                              title: Text(c.name),
                              subtitle: Text(c.phone),
                              trailing: (accounts[c.id]?.balance ?? 0) > 0.5
                                  ? Text(
                                      'owes Rs ${_money.format(accounts[c.id]!.balance)}',
                                      style: const TextStyle(
                                        color: Color(0xFFA8432F),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  : null,
                              onTap: () => Navigator.pop(context, c),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Add/edit customer form, used in the picker and the customers screen.
class CustomerForm extends ConsumerStatefulWidget {
  final Customer? existing;

  /// Pre-fills name or phone from what was typed in the search box.
  final String initialQuery;
  final VoidCallback onCancel;
  final ValueChanged<Customer> onSaved;

  const CustomerForm({
    super.key,
    this.existing,
    this.initialQuery = '',
    required this.onCancel,
    required this.onSaved,
  });

  @override
  ConsumerState<CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends ConsumerState<CustomerForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _note = TextEditingController(text: widget.existing?.note);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuery;
    if (widget.existing == null && q.isNotEmpty) {
      (RegExp(r'^[\d\s+\-]+$').hasMatch(q) ? _phone : _name).text = q;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final phone = _phone.text.trim();
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final others = (ref.read(customersProvider).value ?? const <Customer>[])
        .where((c) => c.id != widget.existing?.id);
    final dup = digits.isEmpty
        ? null
        : others
              .where((c) => c.phone.replaceAll(RegExp(r'\D'), '') == digits)
              .firstOrNull;
    if (dup != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${dup.name} already has this phone number.'),
          backgroundColor: Color(0xFFA8432F),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final saved = await ref
        .read(customersProvider.notifier)
        .save(
          Customer(
            id: widget.existing?.id,
            name: _name.text.trim(),
            phone: phone,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            createdAt: widget.existing?.createdAt ?? DateTime.now(),
          ),
        );
    widget.onSaved(saved);
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  );

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.existing == null ? 'New customer' : 'Edit customer',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: _dec('Name', Icons.person),
            validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: _dec('Phone (for WhatsApp)', Icons.phone),
            validator: (v) {
              final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
              if (d.isEmpty) return 'Required';
              if (d.length < 10) return 'Too short';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _note,
            decoration: _dec('Note (optional)', Icons.notes),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: widget.onCancel,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16171B),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _saving ? null : _save,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
