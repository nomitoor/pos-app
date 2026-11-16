import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/design.dart';
import '../../../models/product.dart';
import '../../../shared/widgets/scan_code_screen.dart';
import '../../../shared/widgets/text_prompt_dialog.dart';
import '../providers/inventory_provider.dart';
import 'design_detail_screen.dart';

/// Add a new design with its sizes, or edit an existing one.
class DesignFormScreen extends ConsumerStatefulWidget {
  final DesignGroup? existing;

  /// A barcode scanned before opening the form (e.g. from the Stock
  /// screen); the user is asked which size it belongs to.
  final String? initialBarcode;
  const DesignFormScreen({super.key, this.existing, this.initialBarcode});

  @override
  ConsumerState<DesignFormScreen> createState() => _DesignFormScreenState();
}

/// One size row in the form.
class _SizeRow {
  final int? productId; // null = new size
  final String? size; // null = "One size"
  final String? originalBarcode;
  final TextEditingController qty;
  final TextEditingController price;
  final TextEditingController barcode;
  bool priceTouched;

  _SizeRow({
    this.productId,
    required this.size,
    this.originalBarcode,
    required String qty,
    required String price,
    String barcode = '',
    this.priceTouched = false,
  }) : qty = TextEditingController(text: qty),
       price = TextEditingController(text: price),
       barcode = TextEditingController(text: barcode);

  void dispose() {
    qty.dispose();
    price.dispose();
    barcode.dispose();
  }
}

class _DesignFormScreenState extends ConsumerState<DesignFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _cost = TextEditingController();
  final _description = TextEditingController();
  String? _type;
  final List<_SizeRow> _rows = [];
  final List<_SizeRow> _removed = []; // existing sizes the user removed
  bool _saving = false;

  bool get _editing => widget.existing != null;

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    if (g != null) {
      final d = g.design;
      _name.text = d.name;
      _type = Product.types.contains(d.type) ? d.type : null;
      _price.text = _num(d.price);
      if (d.costPrice != null) _cost.text = _num(d.costPrice!);
      _description.text = d.description ?? '';
      for (final v in g.variants) {
        _rows.add(
          _SizeRow(
            productId: v.id,
            size: v.size,
            originalBarcode: v.barcode,
            qty: '${v.quantity}',
            price: _num(v.price),
            barcode: v.hasRealBarcode ? v.barcode : '',
            priceTouched: v.price != d.price,
          ),
        );
      }
    }
    final scanned = widget.initialBarcode;
    if (scanned != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => mounted ? _useBarcode(scanned) : null,
      );
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _price, _cost, _description]) {
      c.dispose();
    }
    for (final r in [..._rows, ..._removed]) {
      r.dispose();
    }
    super.dispose();
  }

  bool _has(String? size) => _rows.any((r) => r.size == size);

  void _toggleSize(String? size) {
    setState(() {
      final i = _rows.indexWhere((r) => r.size == size);
      if (i >= 0) {
        final r = _rows.removeAt(i);
        if (r.productId != null) {
          _removed.add(r);
        } else {
          r.dispose();
        }
        return;
      }
      // Re-adding a size removed in this session restores it.
      final back = _removed.indexWhere((r) => r.size == size);
      if (back >= 0) {
        _rows.add(_removed.removeAt(back));
      } else {
        _rows.add(_SizeRow(size: size, qty: '0', price: _price.text.trim()));
      }
      _rows.sort((a, b) => compareSizes(a.size, b.size));
    });
  }

  Future<String?> _askCustomSize() async {
    final s = (await promptText(
      context,
      title: 'Custom size',
      hint: 'e.g. 32 (waist), 9 (shoe), Free size',
      okLabel: 'Add',
    ))?.trim();
    return s == null || s.isEmpty ? null : s;
  }

  Future<void> _addCustomSize() async {
    final s = await _askCustomSize();
    if (s == null || _has(s)) return;
    _toggleSize(s);
  }

  // ── Scan-first: put a scanned barcode on a size ─────────

  Future<void> _scanTop() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanCodeScreen(
          title: 'Scan product barcode',
          hint: 'Scan the barcode on the tag',
        ),
      ),
    );
    if (code != null && mounted) await _useBarcode(code);
  }

  /// Puts [code] on a size: an existing size without a barcode, or a new
  /// size. If another product already has this barcode, offers to open it.
  Future<void> _useBarcode(String code) async {
    code = code.trim();
    if (code.isEmpty) return;
    if (_rows.any((r) => r.barcode.text.trim() == code)) {
      _snack('This barcode is already on one of the sizes below');
      return;
    }

    final owner = await ref.read(inventoryProvider.notifier).getByBarcode(code);
    if (!mounted) return;
    final ours = _rows.any(
      (r) => r.productId != null && r.productId == owner?.id,
    );
    if (owner != null && !ours) {
      final open = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Barcode already in use'),
          content: Text(
            '$code belongs to "${owner.name}"'
            '${owner.size == null ? '' : ' (${shortSize(owner.size)})'}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open that product'),
            ),
          ],
        ),
      );
      if (open == true && owner.designId != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DesignDetailScreen(designId: owner.designId!),
          ),
        );
      }
      return;
    }

    // Which size does this tag belong to?
    final emptyRows = _rows
        .where((r) => r.barcode.text.trim().isEmpty)
        .toList();
    final newSizes = [
      for (final s in Product.sizes)
        if (!_has(s)) s,
    ];
    const custom = '\u0000custom';
    const oneSize = '\u0000one';
    final choice = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Barcode $code is for which size?',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              for (final r in emptyRows)
                ListTile(
                  leading: const Icon(Icons.qr_code_2),
                  title: Text('Size ${shortSize(r.size)}'),
                  subtitle: const Text('Already added, no barcode yet'),
                  onTap: () => Navigator.pop(ctx, r),
                ),
              if (emptyRows.isNotEmpty) const Divider(),
              for (final s in newSizes)
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text('Add size ${shortSize(s)}'),
                  onTap: () => Navigator.pop(ctx, s),
                ),
              if (!_has(null))
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Add as "One size"'),
                  onTap: () => Navigator.pop(ctx, oneSize),
                ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Custom size…'),
                onTap: () => Navigator.pop(ctx, custom),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    _SizeRow? target;
    if (choice is _SizeRow) {
      target = choice;
    } else {
      String? size;
      if (choice == custom) {
        size = await _askCustomSize();
        if (size == null || !mounted) return;
      } else if (choice != oneSize) {
        size = choice as String;
      }
      if (!_has(size)) _toggleSize(size);
      target = _rows.firstWhere((r) => r.size == size);
    }
    setState(() => target!.barcode.text = code);
    _snack('Barcode added to size ${shortSize(target.size)}', error: false);
  }

  /// Keep sizes that still use the design price in step with it.
  void _onDesignPrice(String v) {
    for (final r in _rows) {
      if (!r.priceTouched) r.price.text = v.trim();
    }
    setState(() {});
  }

  Future<void> _scanInto(_SizeRow r) async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanCodeScreen()),
    );
    if (code != null) setState(() => r.barcode.text = code);
  }

  void _snack(String msg, {bool error = true}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: error ? Color(0xFFA8432F) : null,
        ),
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_rows.isEmpty) {
      _snack('Add at least one size');
      return;
    }

    // Barcodes must be unique, within the form and across the shop.
    final typed = <String>{};
    for (final r in _rows) {
      final b = r.barcode.text.trim();
      if (b.isEmpty) continue;
      if (!typed.add(b)) {
        _snack('Barcode $b is used for two sizes');
        return;
      }
      final owner = await ref.read(inventoryProvider.notifier).getByBarcode(b);
      if (!mounted) return;
      if (owner != null && owner.id != r.productId) {
        _snack('Barcode $b already belongs to "${owner.name}"');
        return;
      }
    }

    if (_removed.isNotEmpty) {
      final names = _removed.map((r) => shortSize(r.size)).join(', ');
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remove sizes?'),
          content: Text(
            '$names will be deleted, with their stock. '
            'Past bills are not affected.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Remove',
                style: TextStyle(color: Color(0xFFA8432F)),
              ),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    final price = double.parse(_price.text.trim());
    final design = Design(
      id: widget.existing?.design.id,
      name: _name.text.trim(),
      type: _type,
      price: price,
      costPrice: double.tryParse(_cost.text.trim()),
      description: _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
      photos: widget.existing?.design.photos ?? const [],
      online: widget.existing?.design.online ?? false,
      createdAt: widget.existing?.design.createdAt ?? DateTime.now(),
    );
    final sizes = [
      for (final r in _rows)
        Product(
          id: r.productId,
          barcode: r.barcode.text.trim().isNotEmpty
              ? r.barcode.text.trim()
              // Keep an existing internal code; new sizes get a fresh one.
              : (r.originalBarcode != null &&
                        r.originalBarcode!.startsWith(Product.autoCodePrefix)
                    ? r.originalBarcode!
                    : Product.generateAutoCode()),
          name: design.name,
          price: double.tryParse(r.price.text.trim()) ?? price,
          quantity: int.tryParse(r.qty.text.trim()) ?? 0,
          size: r.size,
          type: design.type,
          costPrice: design.costPrice,
        ),
    ];

    setState(() => _saving = true);
    try {
      await ref
          .read(designsProvider.notifier)
          .save(
            design,
            sizes,
            removeIds: [for (final r in _removed) r.productId!],
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('Could not save: $e');
      }
    }
  }

  InputDecoration _dec(String label, {String? prefix, IconData? icon}) =>
      InputDecoration(
        labelText: label,
        prefixText: prefix,
        prefixIcon: icon == null ? null : Icon(icon),
      );

  @override
  Widget build(BuildContext context) {
    final price = double.tryParse(_price.text.trim());
    final cost = double.tryParse(_cost.text.trim());
    final customSizes = _rows
        .where((r) => r.size != null && !Product.sizes.contains(r.size))
        .map((r) => r.size!)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit product' : 'New product')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // ── Scan first ──
            Material(
              color: AppTheme.brand,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _scanTop,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.qr_code_scanner,
                        color: Colors.white,
                        size: 30,
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Scan barcode',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Scan a tag and choose its size',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: _dec(
                'Product name',
                icon: Icons.label_outline,
              ).copyWith(hintText: 'e.g. Classic Hoodie'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              hint: const Text('Select type'),
              decoration: _dec('Type', icon: Icons.checkroom),
              items: [
                for (final t in Product.types)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              validator: (v) => v == null ? 'Required' : null,
              onChanged: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    decoration: _dec('Price', prefix: 'Rs '),
                    validator: (v) =>
                        (double.tryParse(v?.trim() ?? '') ?? 0) > 0
                        ? null
                        : 'Required',
                    onChanged: _onDesignPrice,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _cost,
                    keyboardType: TextInputType.number,
                    decoration: _dec('Cost (optional)', prefix: 'Rs '),
                    validator: (v) =>
                        v == null ||
                            v.trim().isEmpty ||
                            double.tryParse(v.trim()) != null
                        ? null
                        : 'Invalid',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            if (price != null && cost != null && price > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  price >= cost
                      ? 'Profit Rs ${_num(price - cost)} per piece '
                            '(${((price - cost) / price * 100).toStringAsFixed(0)}% margin)'
                      : 'Loss of Rs ${_num(cost - price)} per piece',
                  style: TextStyle(
                    color: price >= cost
                        ? const Color(0xFF4E7448)
                        : Color(0xFFA8432F),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 2,
              decoration: _dec('Description (optional, for online store)'),
            ),

            // ── Sizes ──
            const SizedBox(height: 24),
            Text('Sizes', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'Tap the sizes you stock.',
              style: TextStyle(color: AppTheme.muted),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in Product.sizes)
                  FilterChip(
                    label: Text(shortSize(s)),
                    selected: _has(s),
                    onSelected: (_) => _toggleSize(s),
                  ),
                for (final s in customSizes)
                  FilterChip(
                    label: Text(s),
                    selected: true,
                    onSelected: (_) => _toggleSize(s),
                  ),
                FilterChip(
                  label: const Text('One size'),
                  selected: _has(null),
                  onSelected: (_) => _toggleSize(null),
                ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Custom'),
                  onPressed: _addCustomSize,
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final r in _rows) _sizeCard(r),
            if (_removed.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Will be removed: ${_removed.map((r) => shortSize(r.size)).join(', ')}',
                  style: const TextStyle(color: Color(0xFFA8432F)),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(_editing ? 'Save changes' : 'Save product'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sizeCard(_SizeRow r) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  constraints: const BoxConstraints(minWidth: 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.brand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    shortSize(r.size),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.brand,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: r.qty,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Stock',
                      isDense: true,
                    ),
                    validator: (v) =>
                        int.tryParse(v?.trim() ?? '') == null ? 'Number' : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: r.price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Price',
                      prefixText: 'Rs ',
                      isDense: true,
                    ),
                    onChanged: (_) => r.priceTouched = true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: r.barcode,
              decoration: InputDecoration(
                labelText: 'Barcode (optional)',
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: 'Scan',
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: () => _scanInto(r),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
