import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/design.dart';
import '../../promotions/providers/promotions_provider.dart';
import '../providers/inventory_provider.dart';
import 'add_product_screen.dart';
import 'design_form_screen.dart';
import '../../online/design_online_panel.dart';

final _money = NumberFormat('#,##0', 'en_US');

class DesignDetailScreen extends ConsumerWidget {
  final int designId;
  const DesignDetailScreen({super.key, required this.designId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(designGroupsProvider);
    return groups.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (list) {
        final g = list.where((g) => g.design.id == designId).firstOrNull;
        if (g == null) {
          return const Scaffold(body: Center(child: Text('Product deleted')));
        }
        return _Body(group: g);
      },
    );
  }
}

class _Body extends ConsumerWidget {
  final DesignGroup group;
  const _Body({required this.group});

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${group.design.name}?'),
        content: Text(
          'All ${group.variants.length} size(s) and their stock '
          'will be deleted. Past bills are not affected.',
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
    await ref.read(designsProvider.notifier).delete(group.design.id!);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = group.design;
    final offer = ref
        .watch(livePromotionsProvider)
        .where((p) => group.variants.any((v) => p.covers(v.barcode, v.type)))
        .firstOrNull;
    final priceText = group.minPrice == group.maxPrice
        ? 'Rs ${_money.format(group.minPrice)}'
        : 'Rs ${_money.format(group.minPrice)} – ${_money.format(group.maxPrice)}';

    return Scaffold(
      appBar: AppBar(
        title: Text(d.name),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DesignFormScreen(existing: group),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (d.type != null) _Pill(d.type!, AppTheme.brand),
                      if (offer != null) ...[
                        const SizedBox(width: 6),
                        _Pill('🏷 ${offer.summary}', const Color(0xFF7C6833)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    priceText,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (d.costPrice != null)
                    Text(
                      'Cost Rs ${_money.format(d.costPrice)} • profit '
                      'Rs ${_money.format(group.minPrice - d.costPrice!)} per piece',
                      style: const TextStyle(color: AppTheme.muted),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    '${group.totalStock} in stock across '
                    '${group.variants.length} size${group.variants.length == 1 ? '' : 's'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (d.description != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      d.description!,
                      style: const TextStyle(color: AppTheme.muted),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          DesignOnlinePanel(group: group),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                'Sizes & stock',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DesignFormScreen(existing: group),
                  ),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add size'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final v in group.variants)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddProductScreen(existingProduct: v),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(
                    children: [
                      Container(
                        constraints: const BoxConstraints(minWidth: 52),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _stockColor(
                            v.quantity,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          shortSize(v.size),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _stockColor(v.quantity),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rs ${_money.format(v.price)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              v.hasRealBarcode ? v.barcode : 'No barcode',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'One less',
                        onPressed: v.quantity <= 0
                            ? null
                            : () => ref
                                  .read(inventoryProvider.notifier)
                                  .adjustStock(v.id!, -1),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      SizedBox(
                        width: 32,
                        child: Text(
                          '${v.quantity}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: _stockColor(v.quantity),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'One more',
                        onPressed: () => ref
                            .read(inventoryProvider.notifier)
                            .adjustStock(v.id!, 1),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Tap a size to change its barcode or details.',
              style: TextStyle(fontSize: 12, color: AppTheme.muted),
            ),
          ),
        ],
      ),
    );
  }

  static Color _stockColor(int q) => q <= 0
      ? const Color(0xFFA8432F)
      : q <= 5
      ? const Color(0xFFB07A1E)
      : const Color(0xFF4E7448);
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}
