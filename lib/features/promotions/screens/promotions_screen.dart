import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../models/promotion.dart';
import '../providers/promotions_provider.dart';
import 'promotion_form_screen.dart';

enum _Status { live, scheduled, expired, off }

_Status _statusOf(Promotion p, DateTime now) {
  if (!p.active) return _Status.off;
  if (p.isLiveAt(now)) return _Status.live;
  if (p.startsAt != null && now.isBefore(p.startsAt!)) return _Status.scheduled;
  return _Status.expired;
}

String scopeText(Promotion p) => switch (p.scope) {
  PromoScope.all => 'All products',
  PromoScope.type => 'All ${p.scopeType ?? '?'}s (mix & match)',
  PromoScope.products =>
    p.barcodes.length == 1
        ? '1 product'
        : '${p.barcodes.length} products (mix & match)',
};

class PromotionsScreen extends ConsumerWidget {
  const PromotionsScreen({super.key});

  void _open(BuildContext context, [Promotion? p]) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => PromotionFormScreen(existing: p)),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promos = ref.watch(promotionsProvider);
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Promotions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context),
        icon: const Icon(Icons.add),
        label: const Text('New offer'),
      ),
      body: promos.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.local_offer_outlined,
                      size: 64,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No offers yet',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Create offers like "Buy 2 for Rs 2000" or '
                      '"Buy 2 get 1 free". They apply automatically at billing.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: list.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final p = list[i];
              final status = _statusOf(p, now);
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _open(context, p),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      p.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _StatusChip(status),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                p.summary,
                                style: const TextStyle(
                                  color: Color(0xFF4E7448),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                [scopeText(p), ?_dates(p)].join(' • '),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: p.active,
                          onChanged: (v) => ref
                              .read(promotionsProvider.notifier)
                              .setActive(p, v),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static String? _dates(Promotion p) {
    final f = DateFormat('d MMM');
    if (p.startsAt == null && p.endsAt == null) return null;
    if (p.startsAt == null) return 'until ${f.format(p.endsAt!)}';
    if (p.endsAt == null) return 'from ${f.format(p.startsAt!)}';
    return '${f.format(p.startsAt!)} – ${f.format(p.endsAt!)}';
  }
}

class _StatusChip extends StatelessWidget {
  final _Status status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      _Status.live => ('LIVE', const Color(0xFF4E7448)),
      _Status.scheduled => ('SCHEDULED', const Color(0xFF16171B)),
      _Status.expired => ('ENDED', Colors.grey),
      _Status.off => ('OFF', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
