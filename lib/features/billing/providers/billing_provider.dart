import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/bill.dart';
import '../../../models/product.dart';
import '../../../core/database/database_helper.dart';
import '../../promotions/promo_engine.dart';
import '../../promotions/providers/promotions_provider.dart';

class CartNotifier extends Notifier<List<BillItem>> {
  // tracks available stock per barcode
  final Map<String, int> _stockMap = {};

  @override
  List<BillItem> build() => [];

  Future<bool> addItem(Product product) async {
    // fetch fresh stock from DB
    final fresh = await DatabaseHelper.instance.getProductByBarcode(
      product.barcode,
    );
    final availableStock = fresh?.quantity ?? product.quantity;

    // how many already in cart
    final existing = state.indexWhere((i) => i.barcode == product.barcode);
    final inCart = existing != -1 ? state[existing].quantity : 0;

    if (inCart >= availableStock) {
      // already at stock limit
      return false;
    }

    // store available stock for this product
    _stockMap[product.barcode] = availableStock;

    if (existing != -1) {
      final updated = List<BillItem>.from(state);
      updated[existing].quantity += 1;
      state = updated;
    } else {
      state = [
        ...state,
        BillItem(
          barcode: product.barcode,
          name: product.name,
          price: product.price,
          quantity: 1,
          size: product.size,
          type: product.type,
          costPrice: product.costPrice,
        ),
      ];
    }
    return true;
  }

  // returns false if already at stock limit
  bool incrementItem(String barcode) {
    final index = state.indexWhere((i) => i.barcode == barcode);
    if (index == -1) return false;

    final currentQty = state[index].quantity;
    final availableStock = _stockMap[barcode] ?? 0;

    if (currentQty >= availableStock) return false;

    final updated = List<BillItem>.from(state);
    updated[index].quantity += 1;
    state = updated;
    return true;
  }

  void decrementItem(String barcode) {
    final updated = List<BillItem>.from(state);
    final index = updated.indexWhere((i) => i.barcode == barcode);
    if (index == -1) return;

    if (updated[index].quantity <= 1) {
      updated.removeAt(index);
      _stockMap.remove(barcode);
    } else {
      updated[index].quantity -= 1;
    }
    state = updated;
  }

  void removeItem(String barcode) {
    _stockMap.remove(barcode);
    state = state.where((i) => i.barcode != barcode).toList();
  }

  /// Replaces the cart with [items] (e.g. a resumed held bill), using
  /// current product data and stock. Lines are capped at what's in stock;
  /// returns the names of items that were reduced or are now unavailable.
  Future<List<String>> restore(List<BillItem> items) async {
    _stockMap.clear();
    final out = <BillItem>[];
    final changed = <String>[];
    for (final i in items) {
      final p = await DatabaseHelper.instance.getProductByBarcode(i.barcode);
      final stock = p?.quantity ?? 0;
      final qty = i.quantity > stock ? stock : i.quantity;
      if (qty < i.quantity) changed.add(i.name);
      if (p == null || qty <= 0) continue;
      _stockMap[p.barcode] = stock;
      out.add(
        BillItem(
          barcode: p.barcode,
          name: p.name,
          price: p.price, // today's price
          quantity: qty,
          size: p.size,
          type: p.type,
          costPrice: p.costPrice,
        ),
      );
    }
    state = out;
    return changed;
  }

  void clearCart() {
    _stockMap.clear();
    state = [];
  }

  int availableStock(String barcode) => _stockMap[barcode] ?? 0;

  int inCartQty(String barcode) {
    final item = state.where((i) => i.barcode == barcode).firstOrNull;
    return item?.quantity ?? 0;
  }
}

final cartProvider = NotifierProvider<CartNotifier, List<BillItem>>(
  CartNotifier.new,
);

/// The cart with live promotions applied.
final pricedCartProvider = Provider<PricedCart>((ref) {
  return applyPromotions(
    ref.watch(cartProvider),
    ref.watch(livePromotionsProvider),
  );
});

/// Amount payable after promotions (before any bill discount).
final cartTotalProvider = Provider<double>((ref) {
  return ref.watch(pricedCartProvider).total;
});
