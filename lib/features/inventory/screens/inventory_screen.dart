import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/design.dart';
import '../../promotions/providers/promotions_provider.dart';
import '../../promotions/screens/promotions_screen.dart';
import '../providers/inventory_provider.dart';
import 'design_detail_screen.dart';
import 'design_form_screen.dart';
import '../../../shared/widgets/scan_code_screen.dart';

final _money = NumberFormat('#,##0', 'en_US');

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

enum _Filter { all, low, out }

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  String _q = '';
  _Filter _filter = _Filter.all;

  void _add() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const DesignFormScreen()),
  );

  /// Scan a tag: open its product, or start a new product with it.
  Future<void> _scan() async {
    final code = (await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanCodeScreen(
          title: 'Scan product barcode',
          hint: 'Find a product, or add a new one',
        ),
      ),
    ))?.trim();
    if (code == null || code.isEmpty || !mounted) return;

    final product = await ref
        .read(inventoryProvider.notifier)
        .getByBarcode(code);
    if (!mounted) return;
    if (product?.designId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DesignDetailScreen(designId: product!.designId!),
        ),
      );
      return;
    }
    final add = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New barcode'),
        content: Text('No product has barcode $code yet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add new product'),
          ),
        ],
      ),
    );
    if (add == true && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DesignFormScreen(initialBarcode: code),
        ),
      );
    }
  }

  bool _matches(DesignGroup g) {
    final q = _q.toLowerCase();
    final text =
        q.isEmpty ||
        g.design.name.toLowerCase().contains(q) ||
        (g.design.type?.toLowerCase().contains(q) ?? false) ||
        g.variants.any((v) => v.barcode.toLowerCase().contains(q));
    return text &&
        switch (_filter) {
          _Filter.all => true,
          _Filter.low => g.anyLow,
          _Filter.out => g.anyOut,
        };
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(designGroupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [
          IconButton(
            tooltip: 'Scan barcode',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _scan,
          ),
          IconButton(
            tooltip: 'Promotions',
            icon: const Icon(Icons.local_offer_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PromotionsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Add product',
            icon: const Icon(Icons.add),
            onPressed: _add,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
      ),
      body: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (groups) {
          if (groups.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No products yet',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Tap Add Product to add one with its sizes',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          final shown = groups.where(_matches).toList();
          final pieces = groups.fold<int>(0, (s, g) => s + g.totalStock);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search name, type or barcode',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _q = v.trim()),
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final (f, label) in [
                      (_Filter.all, 'All ${groups.length} · $pieces pcs'),
                      (
                        _Filter.low,
                        'Low stock ${groups.where((g) => g.anyLow).length}',
                      ),
                      (
                        _Filter.out,
                        'Sold out sizes ${groups.where((g) => g.anyOut).length}',
                      ),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? const Center(
                        child: Text(
                          'Nothing matches',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) =>
                            _DesignCard(group: shown[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DesignCard extends ConsumerWidget {
  final DesignGroup group;
  const _DesignCard({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = group.design;
    final offer = ref
        .watch(livePromotionsProvider)
        .where((p) => group.variants.any((v) => p.covers(v.barcode, v.type)))
        .firstOrNull;
    final price = group.minPrice == group.maxPrice
        ? 'Rs ${_money.format(group.minPrice)}'
        : 'Rs ${_money.format(group.minPrice)}–${_money.format(group.maxPrice)}';

    return Card(
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DesignDetailScreen(designId: d.id!),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [?d.type, '${group.totalStock} in stock'].join(' · '),
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    price,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppTheme.brand,
                    ),
                  ),
                ],
              ),
              if (offer != null) ...[
                const SizedBox(height: 6),
                Text(
                  '🏷 ${offer.summary}',
                  style: const TextStyle(
                    color: Color(0xFF7C6833),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final v in group.variants) _SizeChip(v.size, v.quantity),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SizeChip extends StatelessWidget {
  final String? size;
  final int qty;
  const _SizeChip(this.size, this.qty);

  @override
  Widget build(BuildContext context) {
    final color = qty <= 0
        ? const Color(0xFFA8432F)
        : qty <= 5
        ? const Color(0xFFB07A1E)
        : const Color(0xFF4E7448);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: shortSize(size),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
            TextSpan(
              text: '  $qty',
              style: TextStyle(fontWeight: FontWeight.w800, color: color),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}
