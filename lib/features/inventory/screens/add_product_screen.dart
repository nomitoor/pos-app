import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../providers/inventory_provider.dart';
import '../../../models/product.dart';

class AddProductScreen extends ConsumerStatefulWidget {
  final Product? existingProduct;
  const AddProductScreen({super.key, this.existingProduct});

  @override
  ConsumerState<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ConsumerState<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _barcodeController = TextEditingController();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _quantityController = TextEditingController();
  final _costController = TextEditingController();

  MobileScannerController? _scannerController;
  bool _isScanning = false;
  bool _isSaving = false;
  String? _barcodeError; // set when the barcode belongs to another product
  String? _selectedSize;
  String? _selectedType;

  bool get isEditing => widget.existingProduct != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      final p = widget.existingProduct!;
      if (p.hasRealBarcode) _barcodeController.text = p.barcode;
      _nameController.text = p.name;
      _priceController.text = p.price.toString();
      _quantityController.text = p.quantity.toString();
      if (p.costPrice != null) _costController.text = p.costPrice.toString();
      _selectedSize = p.size; // may be a custom size like "32"
      _selectedType = Product.types.contains(p.type) ? p.type : null;
    }
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _barcodeController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    _costController.dispose();
    super.dispose();
  }

  void _toggleScanner() {
    if (_isScanning) {
      _scannerController?.dispose();
      _scannerController = null;
      setState(() => _isScanning = false);
    } else {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
        torchEnabled: false,
      );
      setState(() => _isScanning = true);
    }
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode != null && barcode.isNotEmpty) {
      _scannerController?.dispose();
      _scannerController = null;
      setState(() {
        _barcodeController.text = barcode;
        _isScanning = false;
      });
    }
  }

  Future<void> _save() async {
    final typed = _barcodeController.text.trim();
    final existing = widget.existingProduct;

    // Refuse a barcode that already belongs to a different product.
    _barcodeError = null;
    if (typed.isNotEmpty) {
      final owner = await ref
          .read(inventoryProvider.notifier)
          .getByBarcode(typed);
      if (owner != null && owner.id != existing?.id) {
        _barcodeError = 'Already used by "${owner.name}"';
      }
    }
    if (!mounted) return;
    if (!_formKey.currentState!.validate()) {
      setState(() {});
      return;
    }
    setState(() => _isSaving = true);

    // Barcode is optional. When blank, keep the product's existing internal
    // code (so past bills still match it) or generate a new one.
    final barcode = typed.isNotEmpty
        ? typed
        : (existing != null && !existing.hasRealBarcode)
        ? existing.barcode
        : Product.generateAutoCode();

    final product = Product(
      id: widget.existingProduct?.id,
      barcode: barcode,
      name: _nameController.text.trim(),
      price: double.parse(_priceController.text.trim()),
      quantity: int.parse(_quantityController.text.trim()),
      size: _selectedSize,
      type: _selectedType,
      costPrice: double.tryParse(_costController.text.trim()),
      designId: widget.existingProduct?.designId,
    );

    if (isEditing) {
      await ref.read(inventoryProvider.notifier).updateProduct(product);
    } else {
      await ref.read(inventoryProvider.notifier).addProduct(product);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit Product' : 'Add Product')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Barcode field ──────────────────────────
              const Text(
                'Barcode (optional)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _barcodeController,
                      decoration: InputDecoration(
                        hintText: 'Scan, type, or leave blank',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: const Icon(Icons.qr_code),
                      ),
                      onChanged: (_) {
                        if (_barcodeError != null) {
                          setState(() => _barcodeError = null);
                        }
                      },
                      validator: (_) => _barcodeError,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16171B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _toggleScanner,
                    child: Icon(
                      _isScanning ? Icons.close : Icons.qr_code_scanner,
                    ),
                  ),
                ],
              ),

              // ── Scanner view ──────────────────────────
              if (_isScanning) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 220,
                    child: _scannerController == null
                        ? const Center(child: CircularProgressIndicator())
                        : MobileScanner(
                            controller: _scannerController!,
                            onDetect: _onBarcodeDetected,
                            errorBuilder: (context, error) {
                              return Container(
                                color: Colors.black,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.error,
                                        color: Color(0xFFA8432F),
                                        size: 40,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        error.errorDetails?.message ??
                                            'Camera error. Check permissions.',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 12),
                                      ElevatedButton(
                                        onPressed: () {
                                          _scannerController?.dispose();
                                          _scannerController =
                                              MobileScannerController(
                                                detectionSpeed:
                                                    DetectionSpeed.noDuplicates,
                                                facing: CameraFacing.back,
                                              );
                                          setState(() {});
                                        },
                                        child: const Text('Retry'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                const Center(
                  child: Text(
                    'Point camera at barcode',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // ── Name field ────────────────────────────
              const Text(
                'Product Name',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: 'e.g. Coca Cola 500ml',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.label),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),

              const SizedBox(height: 16),

              // ── Type dropdown ─────────────────────────
              const Text('Type', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                hint: const Text('Select type'),
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.checkroom),
                ),
                items: [
                  for (final t in Product.types)
                    DropdownMenuItem<String>(value: t, child: Text(t)),
                ],
                validator: (v) => v == null ? 'Required' : null,
                onChanged: (v) => setState(() => _selectedType = v),
              ),

              const SizedBox(height: 16),

              // ── Size dropdown ─────────────────────────
              const Text(
                'Size (optional)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                initialValue: _selectedSize,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.straighten),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No size'),
                  ),
                  for (final s in [
                    ...Product.sizes,
                    // Keep a custom size (e.g. waist "32") selectable.
                    if (widget.existingProduct?.size != null &&
                        !Product.sizes.contains(widget.existingProduct!.size))
                      widget.existingProduct!.size!,
                  ])
                    DropdownMenuItem<String?>(value: s, child: Text(s)),
                ],
                onChanged: (v) => setState(() => _selectedSize = v),
              ),

              const SizedBox(height: 16),

              // ── Price & Quantity ──────────────────────
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Price (Rs.)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _priceController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: '0.00',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            prefixIcon: const Icon(Icons.attach_money),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Required';
                            if (double.tryParse(v) == null) return 'Invalid';
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Quantity',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _quantityController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: '0',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            prefixIcon: const Icon(Icons.numbers),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Required';
                            if (int.tryParse(v) == null) return 'Invalid';
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Cost price (for profit) ───────────────
              const Text(
                'Cost Price (optional)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _costController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'What you paid per piece',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.shopping_cart_checkout),
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  if (double.tryParse(v.trim()) == null) return 'Invalid';
                  return null;
                },
              ),
              _ProfitHint(
                price: double.tryParse(_priceController.text.trim()),
                cost: double.tryParse(_costController.text.trim()),
              ),

              const SizedBox(height: 32),

              // ── Save button ───────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16171B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          isEditing ? 'Update Product' : 'Save Product',
                          style: const TextStyle(fontSize: 16),
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

/// Shows profit and margin per piece once both price and cost are entered.
class _ProfitHint extends StatelessWidget {
  final double? price;
  final double? cost;
  const _ProfitHint({required this.price, required this.cost});

  @override
  Widget build(BuildContext context) {
    final p = price;
    final c = cost;
    if (p == null || c == null || p <= 0) return const SizedBox.shrink();
    final profit = p - c;
    final margin = profit / p * 100;
    final color = profit >= 0 ? const Color(0xFF4E7448) : Color(0xFFA8432F);
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Text(
        profit >= 0
            ? 'Profit Rs. ${profit.toStringAsFixed(0)} per piece '
                  '(${margin.toStringAsFixed(0)}% margin)'
            : 'Loss of Rs. ${(-profit).toStringAsFixed(0)} per piece',
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
