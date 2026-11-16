import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/online_order.dart';
import '../online_orders.dart';
import '../online_store_service.dart';
import 'online_order_detail_screen.dart';

final _money = NumberFormat('#,##0', 'en_US');

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return DateFormat('d MMM').format(t);
}

Color statusColor(String s) => switch (s) {
  OnlineOrder.pending => const Color(0xFFB07A1E),
  OnlineOrder.confirmed => AppTheme.brand,
  OnlineOrder.packed => const Color(0xFF7C6833),
  OnlineOrder.outForDelivery => const Color(0xFF3D5A80),
  OnlineOrder.delivered => const Color(0xFF4E7448),
  _ => const Color(0xFFA8432F),
};

class OnlineOrdersScreen extends ConsumerWidget {
  const OnlineOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(shopOwnerProvider);
    final orders = ref.watch(onlineOrdersProvider);

    if (owner.value != true) {
      return Scaffold(
        appBar: AppBar(title: const Text('Online orders')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              owner.isLoading
                  ? 'Checking…'
                  : 'Sign in with the store owner account under Settings → '
                        'Cloud backup to see online orders.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.muted),
            ),
          ),
        ),
      );
    }

    final list = orders.value ?? const <OnlineOrder>[];
    final groups = [
      list.where((o) => o.isNew).toList(),
      list.where((o) => o.isActive).toList(),
      list.where((o) => o.isDone).toList(),
    ];

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Online orders'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: () =>
                  ref.read(onlineOrdersProvider.notifier).refresh(),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'New (${groups[0].length})'),
              Tab(text: 'Active (${groups[1].length})'),
              const Tab(text: 'Done'),
            ],
          ),
        ),
        body: orders.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load orders:\n$e',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (_) => TabBarView(
            children: [
              for (final (i, g) in groups.indexed)
                RefreshIndicator(
                  onRefresh: () =>
                      ref.read(onlineOrdersProvider.notifier).refresh(),
                  child: g.isEmpty
                      ? ListView(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(48),
                              child: Text(
                                const [
                                  'No new orders. New website orders appear here.',
                                  'No orders in progress.',
                                  'No finished orders yet.',
                                ][i],
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppTheme.muted),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: g.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, j) => _OrderCard(g[j]),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OnlineOrder o;
  const _OrderCard(this.o);

  @override
  Widget build(BuildContext context) {
    final color = statusColor(o.status);
    return Card(
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OnlineOrderDetailScreen(orderId: o.id),
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
                    child: Text(
                      o.orderNo,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      o.statusLabel,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${o.customerName} · ${o.area ?? o.city}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                o.items
                    .map(
                      (i) =>
                          '${i.quantity}× ${i.name}'
                          '${i.size == null ? '' : ' (${i.size})'}',
                    )
                    .join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.muted, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    timeAgo(o.createdAt),
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    'Rs ${_money.format(o.total)} COD',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.brand,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
