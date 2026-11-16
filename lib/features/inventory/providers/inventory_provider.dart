import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_helper.dart';
import '../../../models/design.dart';
import '../../../models/product.dart';

final inventoryProvider =
    AsyncNotifierProvider<InventoryNotifier, List<Product>>(
      InventoryNotifier.new,
    );

/// Products (one per size). Changing them can create or remove designs,
/// so designs are refreshed too.
class InventoryNotifier extends AsyncNotifier<List<Product>> {
  @override
  Future<List<Product>> build() async {
    return await DatabaseHelper.instance.getAllProducts();
  }

  void _refresh() {
    ref.invalidateSelf();
    ref.invalidate(designsProvider);
  }

  Future<void> addProduct(Product product) async {
    await DatabaseHelper.instance.insertProduct(product);
    _refresh();
  }

  Future<void> updateProduct(Product product) async {
    await DatabaseHelper.instance.updateProduct(product);
    _refresh();
  }

  Future<void> deleteProduct(int id) async {
    await DatabaseHelper.instance.deleteProduct(id);
    _refresh();
  }

  Future<void> adjustStock(int productId, int delta) async {
    await DatabaseHelper.instance.adjustStock(productId, delta);
    ref.invalidateSelf();
  }

  Future<Product?> getByBarcode(String barcode) async {
    return await DatabaseHelper.instance.getProductByBarcode(barcode);
  }
}

final designsProvider = AsyncNotifierProvider<DesignsNotifier, List<Design>>(
  DesignsNotifier.new,
);

class DesignsNotifier extends AsyncNotifier<List<Design>> {
  @override
  Future<List<Design>> build() => DatabaseHelper.instance.getDesigns();

  Future<int> save(
    Design d,
    List<Product> sizes, {
    List<int> removeIds = const [],
  }) async {
    final id = await DatabaseHelper.instance.saveDesign(
      d,
      sizes,
      removeIds: removeIds,
    );
    ref.invalidateSelf();
    ref.invalidate(inventoryProvider);
    return id;
  }

  /// Photos / online switch only; sizes untouched.
  Future<void> updateDetails(Design d) async {
    await DatabaseHelper.instance.updateDesign(d);
    ref.invalidateSelf();
  }

  Future<void> delete(int id) async {
    await DatabaseHelper.instance.deleteDesign(id);
    ref.invalidateSelf();
    ref.invalidate(inventoryProvider);
  }
}

/// Designs with their sizes, for the inventory screen.
final designGroupsProvider = FutureProvider<List<DesignGroup>>((ref) async {
  final designs = await ref.watch(designsProvider.future);
  final products = await ref.watch(inventoryProvider.future);
  final byDesign = <int, List<Product>>{};
  for (final p in products) {
    if (p.designId != null) byDesign.putIfAbsent(p.designId!, () => []).add(p);
  }
  return [
    for (final d in designs)
      if (byDesign[d.id] != null)
        DesignGroup(
          d,
          byDesign[d.id]!..sort((a, b) => compareSizes(a.size, b.size)),
        ),
  ];
});
