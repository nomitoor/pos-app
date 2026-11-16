import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_helper.dart';
import '../../../models/promotion.dart';

final promotionsProvider =
    AsyncNotifierProvider<PromotionsNotifier, List<Promotion>>(
      PromotionsNotifier.new,
    );

class PromotionsNotifier extends AsyncNotifier<List<Promotion>> {
  @override
  Future<List<Promotion>> build() => DatabaseHelper.instance.getPromotions();

  Future<void> save(Promotion p) async {
    await DatabaseHelper.instance.savePromotion(p);
    ref.invalidateSelf();
  }

  Future<void> delete(int id) async {
    await DatabaseHelper.instance.deletePromotion(id);
    ref.invalidateSelf();
  }

  Future<void> setActive(Promotion p, bool active) => save(
    Promotion(
      id: p.id,
      name: p.name,
      kind: p.kind,
      buyQty: p.buyQty,
      freeQty: p.freeQty,
      value: p.value,
      scope: p.scope,
      scopeType: p.scopeType,
      barcodes: p.barcodes,
      startsAt: p.startsAt,
      endsAt: p.endsAt,
      active: active,
    ),
  );
}

/// Promotions running right now.
final livePromotionsProvider = Provider<List<Promotion>>((ref) {
  final all = ref.watch(promotionsProvider).value ?? const [];
  final now = DateTime.now();
  return all.where((p) => p.isLiveAt(now)).toList();
});
