import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../providers/billing_provider.dart';
import '../../inventory/providers/inventory_provider.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/bill.dart';
import '../../../models/product.dart';
import '../../../models/design.dart' show compareSizes;
import '../../settings/providers/settings_provider.dart';
import '../../bills/screens/invoice_preview_screen.dart';
import '../../bills/providers/bills_provider.dart';
import '../../settings/cloud_backup_service.dart';
import '../../promotions/promo_engine.dart';
import '../../bills/bill_lookup.dart';
import '../../bills/screens/bills_history_screen.dart' show openBillByCode;
import '../../returns/providers/returns_provider.dart';
import '../../customers/providers/customers_provider.dart';
import '../../customers/screens/customer_picker.dart';
import '../../../models/customer.dart';
import '../../../models/held_bill.dart';
import '../providers/held_bills_provider.dart';

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  bool _isScanning = false;
  bool _isProcessing = false;
  MobileScannerController? _scannerController;
  String? _lastScanned;

  @override
  void dispose() {
    _scannerController?.dispose();
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

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null || barcode == _lastScanned || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _lastScanned = barcode;
    });

    final product = await ref
        .read(inventoryProvider.notifier)
        .getByBarcode(barcode);

    if (!mounted) return;

    if (product == null) {
      final returns = await ref.read(returnsProvider.future);
      final found = await lookupBillByCode(barcode, returns);
      if (!mounted) return;
      if (found.bill != null) {
        // A receipt was scanned (e.g. customer returning something):
        // close the camera and show that bill.
        if (_isScanning) _toggleScanner();
        await openBillByCode(context, ref, barcode);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Product not found for barcode: $barcode'),
            backgroundColor: Color(0xFFA8432F),
          ),
        );
      }
    } else {
      await _addToCart(product);
    }

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() {
        _isProcessing = false;
        _lastScanned = null;
      });
    }
  }

  Future<void> _addToCart(Product product) async {
    if (product.quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product.name} is out of stock!'),
          backgroundColor: Color(0xFFB07A1E),
        ),
      );
      return;
    }
    // addItem returns false if stock limit reached
    final added = await ref.read(cartProvider.notifier).addItem(product);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      added
          ? SnackBar(
              content: Text('${product.name} added to cart'),
              backgroundColor: Color(0xFF4E7448),
              duration: const Duration(seconds: 1),
            )
          : SnackBar(
              content: Text(
                '${product.name} — max stock reached (${product.quantity})',
              ),
              backgroundColor: Color(0xFFB07A1E),
              duration: const Duration(seconds: 2),
            ),
    );
  }

  // Lets products be added without scanning (e.g. ones with no barcode).
  Future<void> _pickProduct() async {
    final picked = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ManualEntrySheet(),
    );
    if (picked != null && mounted) await _addToCart(picked);
  }

  // ── Hold / resume ───────────────────────────────────────

  /// Parks the current cart under a label and empties it.
  Future<bool> _holdCurrent({bool ask = true}) async {
    final items = ref.read(cartProvider);
    if (items.isEmpty) return true;
    final held = ref.read(heldBillsProvider).value ?? const [];
    var label = 'Customer ${held.length + 1}';
    if (ask) {
      // The dialog owns its text controller, so it is disposed only after
      // the closing animation (disposing it here crashed mid-animation).
      final typed = await showDialog<String>(
        context: context,
        builder: (_) => _HoldDialog(suggestion: label),
      );
      if (typed == null) return false; // cancelled
      if (typed.trim().isNotEmpty) label = typed.trim();
    }
    await ref
        .read(heldBillsProvider.notifier)
        .hold(
          HeldBill(
            label: label,
            items: [for (final i in items) i],
            createdAt: DateTime.now(),
          ),
        );
    ref.read(cartProvider.notifier).clearCart();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$label" is on hold. Tap ⏸ list to resume.')),
      );
    }
    return true;
  }

  Future<void> _showHeld() async {
    final picked = await showModalBottomSheet<HeldBill>(
      context: context,
      builder: (_) => const _HeldBillsSheet(),
    );
    if (picked == null || !mounted) return;

    // Park whatever is in the cart now so nothing is lost.
    if (ref.read(cartProvider).isNotEmpty) {
      final ok = await _holdCurrent(ask: false);
      if (!ok) return;
    }
    final changed = await ref.read(cartProvider.notifier).restore(picked.items);
    await ref.read(heldBillsProvider.notifier).remove(picked.id!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          changed.isEmpty
              ? 'Resumed "${picked.label}"'
              : 'Resumed "${picked.label}". Not enough stock now for: '
                    '${changed.join(', ')}',
        ),
        backgroundColor: changed.isEmpty ? null : Color(0xFFB07A1E),
      ),
    );
  }

  Future<void> _checkout() async {
    final priced = ref.read(pricedCartProvider);
    if (priced.lines.isEmpty) return;
    // Lines as charged: promo prices are baked into each item's price.
    final items = [for (final l in priced.lines) l.toBillItem()];

    final subtotal = priced.total;
    final payment = await showModalBottomSheet<_PaymentResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _CheckoutSheet(subtotal: subtotal, promoSavings: priced.savings),
    );
    if (payment == null || !mounted) return;

    final draft = Bill(
      billNumber: '', // checkout assigns the next INV- number
      items: items,
      totalAmount: subtotal - payment.discount,
      createdAt: DateTime.now(),
      discount: payment.discount,
      paymentMethod: payment.method,
      customerId: payment.customer?.id,
      customerName: payment.customer?.name,
      customerPhone: payment.customer?.phone,
    );

    // Save bill and deduct stock atomically. Fails, with a message for the
    // cashier, if stock ran out meanwhile (e.g. an online order took it).
    final Bill bill;
    try {
      bill = await DatabaseHelper.instance.checkout(
        draft,
        paidNow: payment.paidNow,
      );
    } on StateError catch (e) {
      ref.invalidate(inventoryProvider); // show the real stock again
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bill not saved. ${e.message}'),
            backgroundColor: const Color(0xFFA8432F),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      return;
    }
    ref.invalidate(customerPaymentsProvider);

    // Refresh inventory, bill history and insights
    ref.invalidate(inventoryProvider);
    ref.invalidate(billsProvider);

    // Cloud backup in the background if the daily one is due.
    CloudBackupService.autoBackupIfDue();

    // Clear cart
    ref.read(cartProvider.notifier).clearCart();

    if (mounted) {
      // close scanner if open
      if (_isScanning) {
        _scannerController?.dispose();
        _scannerController = null;
        setState(() => _isScanning = false);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bill generated successfully!'),
          backgroundColor: Color(0xFF4E7448),
        ),
      );
    }

    // Preview the invoice before printing
    final settings = await ref.read(shopSettingsProvider.future);
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InvoicePreviewScreen(bill: bill, settings: settings),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final priced = ref.watch(pricedCartProvider);
    final total = priced.total;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing'),
        actions: [
          // Held (parked) carts waiting to be resumed.
          Builder(
            builder: (context) {
              final held = ref.watch(heldBillsProvider).value ?? const [];
              return IconButton(
                tooltip: 'Held bills',
                onPressed: _showHeld,
                icon: Badge(
                  isLabelVisible: held.isNotEmpty,
                  label: Text('${held.length}'),
                  child: const Icon(Icons.pending_actions),
                ),
              );
            },
          ),
          if (cartItems.isNotEmpty) ...[
            IconButton(
              tooltip: 'Hold this bill',
              onPressed: _holdCurrent,
              icon: const Icon(Icons.pause_circle_outline),
            ),
            IconButton(
              tooltip: 'Clear cart',
              onPressed: () => ref.read(cartProvider.notifier).clearCart(),
              icon: const Icon(Icons.clear_all),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // ── Scanner toggle ─────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: !_isScanning
                ? _EntryOptions(onScan: _toggleScanner, onManual: _pickProduct)
                : Container(
                    height: 220,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: _scannerController == null
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                )
                              : MobileScanner(
                                  controller: _scannerController!,
                                  onDetect: _onBarcodeDetected,
                                  errorBuilder: (context, error) {
                                    return Container(
                                      color: Colors.black,
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
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
                                                fontSize: 12,
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
                                                          DetectionSpeed
                                                              .noDuplicates,
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
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: _toggleScanner,
                            child: const CircleAvatar(
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close, color: Colors.white),
                            ),
                          ),
                        ),
                        if (_isProcessing)
                          const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ),
          ),

          // ── Cart items ─────────────────────────────────
          Expanded(
            child: cartItems.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Cart is empty',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Scan a barcode or use manual entry',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: cartItems.length,
                    // ← fixed: use two different names
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      return _CartItemCard(line: priced.lines[index]);
                    },
                  ),
          ),

          // ── Total & Checkout ───────────────────────────
          if (cartItems.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  if (priced.savings > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.local_offer,
                                size: 16,
                                color: Color(0xFF4E7448),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Promotion savings',
                                style: TextStyle(
                                  color: Color(0xFF4E7448),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '- Rs. ${priced.savings.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Color(0xFF4E7448),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Rs. ${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF16171B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4E7448),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _checkout,
                      icon: const Icon(Icons.receipt),
                      label: const Text(
                        'Checkout & Generate Bill',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Entry Options (Scan / Manual) ──────────────────────────
class _EntryOptions extends StatelessWidget {
  final VoidCallback onScan;
  final VoidCallback onManual;
  const _EntryOptions({required this.onScan, required this.onManual});

  Widget _option({
    required IconData icon,
    required String label,
    required bool primary,
    required VoidCallback onTap,
  }) {
    // Scanning is the main way in: solid ink. Manual entry is the fallback.
    final fg = primary ? Colors.white : AppTheme.ink;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: primary
          ? BorderSide.none
          : const BorderSide(color: AppTheme.border, width: 1.2),
    );
    return Expanded(
      child: Material(
        color: primary ? AppTheme.ink : AppTheme.surface,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: SizedBox(
            height: 72,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: fg, size: 28),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _option(
          icon: Icons.qr_code_scanner,
          label: 'Scan barcode',
          primary: true,
          onTap: onScan,
        ),
        const SizedBox(width: 12),
        _option(
          icon: Icons.touch_app_outlined,
          label: 'Manual entry',
          primary: false,
          onTap: onManual,
        ),
      ],
    );
  }
}

// ── Manual Entry Sheet: Type → Size → (Product) ────────────
class _ManualEntrySheet extends ConsumerStatefulWidget {
  const _ManualEntrySheet();

  @override
  ConsumerState<_ManualEntrySheet> createState() => _ManualEntrySheetState();
}

class _ManualEntrySheetState extends ConsumerState<_ManualEntrySheet> {
  // Stands in for "no size" in the size step.
  static const String _noSize = '__no_size__';

  String? _type;
  String? _size; // set only when several products share type + size

  List<Product> _ofType(List<Product> all) =>
      all.where((p) => p.type == _type).toList();

  List<Product> _ofSize(List<Product> ofType, String size) => ofType
      .where((p) => size == _noSize ? p.size == null : p.size == size)
      .toList();

  int _stock(List<Product> ps) => ps.fold(0, (sum, p) => sum + p.quantity);

  void _back() => setState(() {
    if (_size != null) {
      _size = null;
    } else {
      _type = null;
    }
  });

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(inventoryProvider);

    final title = _type == null
        ? 'Select Type'
        : _size == null
        ? '$_type — Select Size'
        : '$_type — ${_size == _noSize ? 'No size' : _size}';

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
              child: Row(
                children: [
                  if (_type != null)
                    IconButton(
                      onPressed: _back,
                      icon: const Icon(Icons.arrow_back),
                    )
                  else
                    const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: productsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (products) {
                  if (_type == null) return _buildTypes(products);
                  final ofType = _ofType(products);
                  if (_size == null) return _buildSizes(ofType);
                  return _buildProducts(_ofSize(ofType, _size!));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile({
    required String label,
    required String caption,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: enabled
          ? const Color(0xFF16171B).withValues(alpha: 0.08)
          : Colors.grey.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: enabled ? const Color(0xFF16171B) : Colors.grey,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                caption,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid(List<Widget> children) {
    return GridView.count(
      padding: const EdgeInsets.all(16),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.2,
      children: children,
    );
  }

  // Step 1: all types; disabled when nothing of that type is in stock.
  Widget _buildTypes(List<Product> products) {
    return _grid([
      for (final t in Product.types)
        Builder(
          builder: (_) {
            final stock = _stock(products.where((p) => p.type == t).toList());
            return _tile(
              label: t,
              caption: stock > 0 ? '$stock in stock' : 'Out of stock',
              enabled: stock > 0,
              onTap: () => setState(() => _type = t),
            );
          },
        ),
    ]);
  }

  // Step 2: sizes for the chosen type. Picking a size with exactly one
  // product adds it straight away; otherwise step 3 lists the choices.
  Widget _buildSizes(List<Product> ofType) {
    // Sizes this type actually comes in (standard and custom), smallest
    // first; "no size" last.
    final present = {for (final p in ofType) p.size}.toList()
      ..sort(compareSizes);
    final options = [for (final s in present) s ?? _noSize];

    return _grid([
      for (final s in options)
        Builder(
          builder: (_) {
            final matches = _ofSize(ofType, s);
            final stock = _stock(matches);
            return _tile(
              label: s == _noSize ? 'No size' : s,
              caption: stock > 0 ? '$stock in stock' : 'Out of stock',
              enabled: stock > 0,
              onTap: () {
                final inStock = matches.where((p) => p.quantity > 0).toList();
                if (inStock.length == 1) {
                  Navigator.pop(context, inStock.first);
                } else {
                  setState(() => _size = s);
                }
              },
            );
          },
        ),
    ]);
  }

  // Step 3: several products share this type + size — choose one.
  Widget _buildProducts(List<Product> matches) {
    return ListView.separated(
      itemCount: matches.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final p = matches[index];
        return ListTile(
          enabled: p.quantity > 0,
          title: Text(p.name),
          subtitle: Text('Stock: ${p.quantity}'),
          trailing: Text(
            'Rs. ${p.price.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF16171B),
            ),
          ),
          onTap: () => Navigator.pop(context, p),
        );
      },
    );
  }
}

// ── Cart Item Card ─────────────────────────────────────────
class _CartItemCard extends ConsumerWidget {
  final PricedLine line;
  const _CartItemCard({required this.line});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = line.item;
    final cart = ref.read(cartProvider.notifier);
    final stock = cart.availableStock(item.barcode);
    final inCart = cart.inCartQty(item.barcode);
    final atMax = inCart >= stock;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Rs. ${item.price.toStringAsFixed(2)} each',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  if (line.hasPromo)
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4E7448).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '🏷 ${line.promoName}  −Rs. ${line.discount.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF3F5F3A),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  // stock indicator
                  Text(
                    'Stock: $stock  |  In cart: $inCart',
                    style: TextStyle(
                      fontSize: 11,
                      color: atMax ? Color(0xFFB07A1E) : Colors.grey,
                      fontWeight: atMax ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            // Qty controls
            Row(
              children: [
                IconButton(
                  onPressed: () => ref
                      .read(cartProvider.notifier)
                      .decrementItem(item.barcode),
                  icon: const Icon(Icons.remove_circle_outline),
                  color: Color(0xFFA8432F),
                ),
                Text(
                  '${item.quantity}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                IconButton(
                  // grey out + disable when at stock limit
                  onPressed: atMax
                      ? null
                      : () {
                          final ok = ref
                              .read(cartProvider.notifier)
                              .incrementItem(item.barcode);
                          if (!ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${item.name} — only $stock in stock',
                                ),
                                backgroundColor: Color(0xFFB07A1E),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                  icon: Icon(
                    Icons.add_circle_outline,
                    color: atMax ? Colors.grey : Color(0xFF4E7448),
                  ),
                ),
              ],
            ),
            // Subtotal
            SizedBox(
              width: 75,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (line.hasPromo)
                    Text(
                      'Rs. ${line.listTotal.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  Text(
                    'Rs. ${line.total.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: line.hasPromo
                          ? const Color(0xFF4E7448)
                          : const Color(0xFF16171B),
                    ),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Checkout Sheet: discount + payment method ──────────────
class _PaymentResult {
  final double discount;
  final String method;
  final Customer? customer;

  /// Udhaar only: cash handed over now towards this bill.
  final double paidNow;
  const _PaymentResult(
    this.discount,
    this.method,
    this.customer, [
    this.paidNow = 0,
  ]);
}

class _CheckoutSheet extends StatefulWidget {
  final double subtotal; // after promotions
  final double promoSavings;
  const _CheckoutSheet({required this.subtotal, this.promoSavings = 0});

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  final _discountController = TextEditingController();
  final _paidNowController = TextEditingController();
  bool _percent = false;
  String _method = Bill.paymentMethods.first;
  Customer? _customer;

  @override
  void dispose() {
    _discountController.dispose();
    _paidNowController.dispose();
    super.dispose();
  }

  Future<void> _chooseCustomer() async {
    final c = await pickCustomer(context);
    if (c != null) setState(() => _customer = c);
  }

  /// Discount in rupees, clamped to 0..subtotal.
  double get _discount {
    final v = double.tryParse(_discountController.text.trim()) ?? 0;
    final rs = _percent ? widget.subtotal * v / 100 : v;
    return rs.clamp(0, widget.subtotal).toDouble();
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    final style = TextStyle(
      fontSize: bold ? 20 : 15,
      fontWeight: bold ? FontWeight.bold : FontWeight.w500,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final discount = _discount;
    final total = widget.subtotal - discount;
    final udhaar = _method == Bill.udhaar;
    final paidNow = udhaar
        ? (double.tryParse(_paidNowController.text.trim()) ?? 0)
              .clamp(0, total)
              .toDouble()
        : 0.0;
    final canConfirm = !udhaar || _customer != null;

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
              const Text(
                'Checkout',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // ── Customer ──
              Material(
                color: _customer == null
                    ? const Color(0xFFF4F4F1)
                    : const Color(0xFFF4F4F1),
                borderRadius: BorderRadius.circular(10),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  leading: Icon(
                    _customer == null ? Icons.person_add : Icons.person,
                    color: const Color(0xFF16171B),
                  ),
                  title: Text(_customer?.name ?? 'Add customer (optional)'),
                  subtitle: _customer == null
                      ? const Text('For udhaar, WhatsApp receipt & history')
                      : Text(_customer!.phone),
                  trailing: _customer == null
                      ? const Icon(Icons.chevron_right)
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _customer = null;
                            if (_method == Bill.udhaar) {
                              _method = Bill.cash;
                            }
                          }),
                        ),
                  onTap: _chooseCustomer,
                ),
              ),
              const SizedBox(height: 16),

              // ── Discount ──
              const Text(
                'Discount',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _discountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        hintText: '0',
                        prefixIcon: const Icon(Icons.local_offer),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('Rs')),
                      ButtonSegment(value: true, label: Text('%')),
                    ],
                    selected: {_percent},
                    onSelectionChanged: (s) =>
                        setState(() => _percent = s.first),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Payment method ──
              const Text(
                'Payment method',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in Bill.paymentMethods)
                    ChoiceChip(
                      label: Text(m == Bill.udhaar ? 'Udhaar (credit)' : m),
                      selected: _method == m,
                      selectedColor: m == Bill.udhaar
                          ? Color(0xFFF6EFE2)
                          : null,
                      onSelected: (_) async {
                        setState(() => _method = m);
                        if (m == Bill.udhaar && _customer == null) {
                          await _chooseCustomer();
                        }
                      },
                    ),
                ],
              ),
              if (udhaar) ...[
                const SizedBox(height: 12),
                if (_customer == null)
                  const Text(
                    'Choose a customer for an udhaar sale.',
                    style: TextStyle(color: Color(0xFFA8432F)),
                  )
                else
                  TextField(
                    controller: _paidNowController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Paid now in cash (optional)',
                      prefixText: 'Rs ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
              ],
              const Divider(height: 32),

              if (widget.promoSavings > 0)
                _row(
                  'Promotions',
                  '- Rs. ${widget.promoSavings.toStringAsFixed(2)}',
                  color: const Color(0xFF4E7448),
                ),
              _row('Subtotal', 'Rs. ${widget.subtotal.toStringAsFixed(2)}'),
              if (discount > 0)
                _row(
                  'Discount',
                  '- Rs. ${discount.toStringAsFixed(2)}',
                  color: Color(0xFFA8432F),
                ),
              _row(
                'Total',
                'Rs. ${total.toStringAsFixed(2)}',
                bold: true,
                color: const Color(0xFF16171B),
              ),
              if (udhaar && _customer != null) ...[
                if (paidNow > 0)
                  _row('Paid now', '- Rs. ${paidNow.toStringAsFixed(2)}'),
                _row(
                  'Added to ${_customer!.name}\'s udhaar',
                  'Rs. ${(total - paidNow).toStringAsFixed(2)}',
                  color: Color(0xFF8A5F17),
                ),
              ],
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4E7448),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: !canConfirm
                      ? null
                      : () => Navigator.pop(
                          context,
                          _PaymentResult(discount, _method, _customer, paidNow),
                        ),
                  icon: const Icon(Icons.check_circle),
                  label: Text(
                    'Confirm • $_method',
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

// ── Held bills list ────────────────────────────────────────
class _HeldBillsSheet extends ConsumerWidget {
  const _HeldBillsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final held = ref.watch(heldBillsProvider).value ?? const <HeldBill>[];
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Held bills',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          if (held.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Text(
                'No bills on hold. Use ⏸ in Billing to park a cart while a '
                'customer tries something on.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final h in held)
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFF6EFE2),
                      child: Icon(Icons.pause, color: Color(0xFFB07A1E)),
                    ),
                    title: Text(h.label),
                    subtitle: Text(
                      '${h.pieces} item${h.pieces == 1 ? '' : 's'} • '
                      'Rs ${h.listTotal.toStringAsFixed(0)} • held '
                      '${_ago(h.createdAt)}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Discard',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () =>
                          ref.read(heldBillsProvider.notifier).remove(h.id!),
                    ),
                    onTap: () => Navigator.pop(context, h),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

// ── "Hold this bill" dialog ────────────────────────────────
class _HoldDialog extends StatefulWidget {
  final String suggestion;
  const _HoldDialog({required this.suggestion});

  @override
  State<_HoldDialog> createState() => _HoldDialogState();
}

class _HoldDialogState extends State<_HoldDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Hold this bill'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: 'Name or note (optional)',
          hintText: 'e.g. ${widget.suggestion}, lady in blue',
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Hold'),
        ),
      ],
    );
  }
}
