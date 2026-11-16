import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../models/bill.dart';
import '../../../models/product.dart';
import '../../../models/promotion.dart';
import '../../inventory/providers/inventory_provider.dart';
import '../promo_engine.dart';
import '../providers/promotions_provider.dart';

class PromotionFormScreen extends ConsumerStatefulWidget {
  final Promotion? existing;
  const PromotionFormScreen({super.key, this.existing});

  @override
  ConsumerState<PromotionFormScreen> createState() =>
      _PromotionFormScreenState();
}

class _PromotionFormScreenState extends ConsumerState<PromotionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _buy = TextEditingController(text: '2');
  final _free = TextEditingController(text: '1');
  final _value = TextEditingController();

  PromoKind _kind = PromoKind.bundle;
  PromoScope _scope = PromoScope.products;
  String? _type;
  List<String> _barcodes = [];
  DateTime? _start;
  DateTime? _end;
  bool _active = true;
  bool _saving = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    if (p != null) {
      _name.text = p.name;
      _kind = p.kind;
      _buy.text = '${p.buyQty}';
      _free.text = '${p.freeQty == 0 ? 1 : p.freeQty}';
      _value.text = _num(p.value);
      _scope = p.scope;
      _type = p.scopeType;
      _barcodes = [...p.barcodes];
      _start = p.startsAt;
      _end = p.endsAt;
      _active = p.active;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _buy, _free, _value]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  void _setKind(PromoKind k) => setState(() {
    _kind = k;
    if (k == PromoKind.percentOff && _buy.text == '2') _buy.text = '1';
    if (k != PromoKind.percentOff && _buy.text == '1') _buy.text = '2';
  });

  /// The promotion as currently entered (may be incomplete).
  Promotion _draft() => Promotion(
    id: widget.existing?.id,
    name: _name.text.trim(),
    kind: _kind,
    buyQty: int.tryParse(_buy.text.trim()) ?? 0,
    freeQty: _kind == PromoKind.buyGetFree
        ? int.tryParse(_free.text.trim()) ?? 0
        : 0,
    value: _kind == PromoKind.buyGetFree
        ? 0
        : double.tryParse(_value.text.trim()) ?? 0,
    scope: _scope,
    scopeType: _scope == PromoScope.type ? _type : null,
    barcodes: _scope == PromoScope.products ? _barcodes : const [],
    startsAt: _start,
    endsAt: _end,
    active: _active,
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_scope == PromoScope.type && _type == null) {
      _snack('Choose a product type');
      return;
    }
    if (_scope == PromoScope.products && _barcodes.isEmpty) {
      _snack('Choose at least one product');
      return;
    }
    if (_start != null && _end != null && _end!.isBefore(_start!)) {
      _snack('End date is before the start date');
      return;
    }
    var p = _draft();
    if (p.name.isEmpty) {
      p = Promotion(
        id: p.id,
        name: p.summary,
        kind: p.kind,
        buyQty: p.buyQty,
        freeQty: p.freeQty,
        value: p.value,
        scope: p.scope,
        scopeType: p.scopeType,
        barcodes: p.barcodes,
        startsAt: p.startsAt,
        endsAt: p.endsAt,
        active: p.active,
      );
    }
    setState(() => _saving = true);
    await ref.read(promotionsProvider.notifier).save(p);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete offer?'),
        content: const Text(
          'Past bills keep the prices they were sold at. To pause an offer '
          'instead, switch it off.',
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
    if (ok != true) return;
    await ref.read(promotionsProvider.notifier).delete(widget.existing!.id!);
    if (mounted) Navigator.pop(context);
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Color(0xFFA8432F)),
  );

  Future<void> _pickProducts(List<Product> products) async {
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _ProductMultiPicker(products: products, selected: _barcodes),
    );
    if (picked != null) setState(() => _barcodes = picked);
  }

  Future<void> _pickDate(bool start) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: (start ? _start : _end) ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (d != null) setState(() => start ? _start = d : _end = d);
  }

  InputDecoration _dec(String label, {String? prefix, String? suffix}) =>
      InputDecoration(
        labelText: label,
        prefixText: prefix,
        suffixText: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  String? _intAtLeast(String? v, int min) {
    final n = int.tryParse(v?.trim() ?? '');
    if (n == null || n < min) return 'Min $min';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(inventoryProvider).value ?? const <Product>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit offer' : 'New offer'),
        actions: [
          if (_editing)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Offer type ──
            const _Label('Offer type'),
            Wrap(
              spacing: 8,
              children: [
                for (final k in PromoKind.values)
                  ChoiceChip(
                    label: Text(k.label),
                    selected: _kind == k,
                    onSelected: (_) => _setKind(k),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Numbers, phrased like the offer ──
            ..._numberFields(),
            const SizedBox(height: 20),

            // ── Applies to ──
            const _Label('Applies to'),
            Wrap(
              spacing: 8,
              children: [
                for (final s in PromoScope.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _scope == s,
                    onSelected: (_) => setState(() => _scope = s),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_scope == PromoScope.type)
              DropdownButtonFormField<String>(
                initialValue: _type,
                hint: const Text('Select type'),
                decoration: _dec('Type'),
                items: [
                  for (final t in Product.types)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => setState(() => _type = v),
              ),
            if (_scope == PromoScope.products)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  alignment: Alignment.centerLeft,
                ),
                onPressed: () => _pickProducts(products),
                icon: const Icon(Icons.checklist),
                label: Text(
                  _barcodes.isEmpty
                      ? 'Choose products'
                      : '${_barcodes.length} product${_barcodes.length == 1 ? '' : 's'} selected — change',
                ),
              ),
            if (_scope != PromoScope.all)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Customers can mix and match any of these to make up the offer.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            const SizedBox(height: 20),

            // ── Dates ──
            const _Label('When (optional)'),
            Row(
              children: [
                Expanded(child: _dateButton(true)),
                const SizedBox(width: 12),
                Expanded(child: _dateButton(false)),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Offer is on'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _name,
              decoration: _dec(
                'Name on receipt (optional)',
              ).copyWith(hintText: _draft().summary),
            ),
            const SizedBox(height: 20),

            _Example(promo: _draft(), products: products),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4E7448),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _saving ? null : _save,
                child: Text(
                  _editing ? 'Save offer' : 'Create offer',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _numberFields() {
    void changed(String _) => setState(() {});
    switch (_kind) {
      case PromoKind.bundle:
        return [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _buy,
                  keyboardType: TextInputType.number,
                  decoration: _dec('Buy', suffix: 'pieces'),
                  validator: (v) => _intAtLeast(v, 2),
                  onChanged: changed,
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(10, 16, 10, 0),
                child: Text('for', style: TextStyle(fontSize: 16)),
              ),
              Expanded(
                child: TextFormField(
                  controller: _value,
                  keyboardType: TextInputType.number,
                  decoration: _dec('Price', prefix: 'Rs '),
                  validator: (v) => (double.tryParse(v?.trim() ?? '') ?? 0) > 0
                      ? null
                      : 'Enter price',
                  onChanged: changed,
                ),
              ),
            ],
          ),
        ];
      case PromoKind.buyGetFree:
        return [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _buy,
                  keyboardType: TextInputType.number,
                  decoration: _dec('Buy', suffix: 'pieces'),
                  validator: (v) => _intAtLeast(v, 1),
                  onChanged: changed,
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(10, 16, 10, 0),
                child: Text('get', style: TextStyle(fontSize: 16)),
              ),
              Expanded(
                child: TextFormField(
                  controller: _free,
                  keyboardType: TextInputType.number,
                  decoration: _dec('Free', suffix: 'pieces'),
                  validator: (v) => _intAtLeast(v, 1),
                  onChanged: changed,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'The cheapest piece(s) in each group are free.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ];
      case PromoKind.percentOff:
        return [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _value,
                  keyboardType: TextInputType.number,
                  decoration: _dec('Discount', suffix: '% off'),
                  validator: (v) {
                    final n = double.tryParse(v?.trim() ?? '');
                    return n == null || n <= 0 || n > 100 ? '1–100' : null;
                  },
                  onChanged: changed,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _buy,
                  keyboardType: TextInputType.number,
                  decoration: _dec('When buying at least', suffix: 'pcs'),
                  validator: (v) => _intAtLeast(v, 1),
                  onChanged: changed,
                ),
              ),
            ],
          ),
        ];
    }
  }

  Widget _dateButton(bool start) {
    final d = start ? _start : _end;
    return OutlinedButton(
      onPressed: () => _pickDate(start),
      onLongPress: d == null
          ? null
          : () => setState(() => start ? _start = null : _end = null),
      child: Row(
        children: [
          Icon(start ? Icons.play_arrow : Icons.stop, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              d == null
                  ? (start ? 'Starts now' : 'No end date')
                  : '${start ? 'From' : 'Until'} ${DateFormat('d MMM y').format(d)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (d != null)
            GestureDetector(
              onTap: () => setState(() => start ? _start = null : _end = null),
              child: const Icon(Icons.close, size: 16),
            ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
    ),
  );
}

/// Worked example using a real covered product, so the shopkeeper can see
/// exactly what the customer will pay.
class _Example extends StatelessWidget {
  final Promotion promo;
  final List<Product> products;
  const _Example({required this.promo, required this.products});

  @override
  Widget build(BuildContext context) {
    final sample = products
        .where((p) => promo.covers(p.barcode, p.type))
        .firstOrNull;
    final qty = switch (promo.kind) {
      PromoKind.bundle => promo.buyQty,
      PromoKind.buyGetFree => promo.buyQty + promo.freeQty,
      PromoKind.percentOff => promo.buyQty < 1 ? 1 : promo.buyQty,
    };

    String text;
    var good = false;
    if (sample == null || qty < 1) {
      text = 'Choose what the offer applies to, to see an example.';
    } else {
      final live = Promotion(
        name: promo.name,
        kind: promo.kind,
        buyQty: promo.buyQty,
        freeQty: promo.freeQty,
        value: promo.value,
        scope: PromoScope.all,
      );
      final cart = [
        BillItem(
          barcode: sample.barcode,
          name: sample.name,
          price: sample.price,
          quantity: qty,
        ),
      ];
      final priced = applyPromotions(cart, [live]);
      final f = NumberFormat('#,##0.##');
      if (priced.savings <= 0) {
        text =
            '$qty × ${sample.name} at Rs ${f.format(sample.price)} = '
            'Rs ${f.format(priced.listTotal)}. This offer would not lower '
            'the price. Check the numbers.';
      } else {
        good = true;
        text =
            '$qty × ${sample.name} (Rs ${f.format(sample.price)} each): '
            'Rs ${f.format(priced.listTotal)} → Rs ${f.format(priced.total)}. '
            'Customer saves Rs ${f.format(priced.savings)}.';
        if (sample.costPrice != null) {
          final profit = priced.total - sample.costPrice! * qty;
          text += profit >= 0
              ? ' Your profit: Rs ${f.format(profit)}.'
              : ' ⚠ You lose Rs ${f.format(-profit)} vs cost!';
          if (profit < 0) good = false;
        }
      }
    }

    final color = good ? const Color(0xFF4E7448) : Color(0xFF8A5F17);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(good ? Icons.calculate : Icons.info_outline, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}

class _ProductMultiPicker extends StatefulWidget {
  final List<Product> products;
  final List<String> selected;
  const _ProductMultiPicker({required this.products, required this.selected});

  @override
  State<_ProductMultiPicker> createState() => _ProductMultiPickerState();
}

class _ProductMultiPickerState extends State<_ProductMultiPicker> {
  late final Set<String> _sel = {...widget.selected};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = widget.products
        .where(
          (p) =>
              q.isEmpty ||
              p.name.toLowerCase().contains(q) ||
              (p.type?.toLowerCase().contains(q) ?? false) ||
              (p.size?.toLowerCase().contains(q) ?? false),
        )
        .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search products',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (v) => setState(() => _q = v.trim()),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final p in list)
                      CheckboxListTile(
                        value: _sel.contains(p.barcode),
                        title: Text(p.name),
                        subtitle: Text(
                          [
                            ?p.type,
                            ?p.size,
                            'Rs ${p.price.toStringAsFixed(0)}',
                          ].join(' • '),
                        ),
                        onChanged: (v) => setState(
                          () => v == true
                              ? _sel.add(p.barcode)
                              : _sel.remove(p.barcode),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _sel.toList()),
                    child: Text('Done (${_sel.length} selected)'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
