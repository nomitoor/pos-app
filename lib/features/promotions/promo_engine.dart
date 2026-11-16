import '../../models/bill.dart';
import '../../models/promotion.dart';

/// A cart line after promotions.
class PricedLine {
  final BillItem item; // at its normal (list) price
  final double discount; // total promo discount on this line
  final String? promoName;

  const PricedLine(this.item, this.discount, this.promoName);

  double get listTotal => item.price * item.quantity;
  double get total => listTotal - discount;

  /// Average price actually paid per piece.
  double get unitPrice =>
      item.quantity == 0 ? item.price : total / item.quantity;

  bool get hasPromo => discount > 0.0001;

  /// The line as it should be saved on the bill.
  BillItem toBillItem() => BillItem(
    barcode: item.barcode,
    name: item.name,
    price: unitPrice,
    quantity: item.quantity,
    size: item.size,
    type: item.type,
    costPrice: item.costPrice,
    listPrice: hasPromo ? item.price : null,
    promo: hasPromo ? promoName : null,
  );
}

class PricedCart {
  final List<PricedLine> lines;
  const PricedCart(this.lines);

  double get listTotal => lines.fold(0, (s, l) => s + l.listTotal);
  double get savings => lines.fold(0, (s, l) => s + l.discount);
  double get total => listTotal - savings;
}

/// One physical piece in the cart.
class _Unit {
  final int line;
  final double price;
  _Unit(this.line, this.price);
}

/// The discount one promotion would give on [units], and which units it uses.
class _Offer {
  final Promotion promo;
  final Map<_Unit, double> discounts;
  _Offer(this.promo, this.discounts);
  double get total => discounts.values.fold(0, (s, d) => s + d);
}

/// Applies the live [promos] to [cart] (items at list price).
///
/// Each piece gets at most one promotion. Promotions are chosen greedily:
/// the one saving the most on the still-unused pieces is applied first,
/// then the next, until none saves anything. Within an offer, the most
/// expensive pieces are grouped first; for "get Y free" the cheapest
/// piece(s) of each group are free.
PricedCart applyPromotions(
  List<BillItem> cart,
  List<Promotion> promos, {
  DateTime? now,
}) {
  now ??= DateTime.now();
  final live = promos.where((p) => p.isLiveAt(now!)).toList();

  var free = <_Unit>[
    for (var i = 0; i < cart.length; i++)
      for (var q = 0; q < cart[i].quantity; q++) _Unit(i, cart[i].price),
  ];
  final lineDiscount = List<double>.filled(cart.length, 0);
  final lineNames = List.generate(cart.length, (_) => <String>{});

  while (true) {
    _Offer? best;
    for (final p in live) {
      final eligible =
          free
              .where((u) => p.covers(cart[u.line].barcode, cart[u.line].type))
              .toList()
            ..sort((a, b) => b.price.compareTo(a.price));
      final offer = _evaluate(p, eligible);
      if (offer != null && (best == null || offer.total > best.total)) {
        best = offer;
      }
    }
    if (best == null || best.total <= 0.0001) break;

    for (final e in best.discounts.entries) {
      lineDiscount[e.key.line] += e.value;
      lineNames[e.key.line].add(best.promo.name);
    }
    free = free.where((u) => !best!.discounts.containsKey(u)).toList();
  }

  return PricedCart([
    for (var i = 0; i < cart.length; i++)
      PricedLine(
        cart[i],
        lineDiscount[i],
        lineNames[i].isEmpty ? null : lineNames[i].join(' + '),
      ),
  ]);
}

/// [units] are sorted most expensive first.
_Offer? _evaluate(Promotion p, List<_Unit> units) {
  final out = <_Unit, double>{};
  switch (p.kind) {
    case PromoKind.bundle:
      final n = p.buyQty;
      if (n < 1) return null;
      for (var g = 0; g + n <= units.length; g += n) {
        final group = units.sublist(g, g + n);
        final full = group.fold<double>(0, (s, u) => s + u.price);
        final saving = full - p.value;
        if (saving <= 0) continue; // bundle isn't cheaper for these pieces
        // Spread the saving across the group in proportion to price.
        for (final u in group) {
          out[u] = saving * u.price / full;
        }
      }
    case PromoKind.buyGetFree:
      final size = p.buyQty + p.freeQty;
      if (p.buyQty < 1 || p.freeQty < 1) return null;
      for (var g = 0; g + size <= units.length; g += size) {
        final group = units.sublist(g, g + size);
        // Group members share the saving so each line's paid price stays
        // sensible; the saving equals the cheapest freeQty pieces.
        final saving = group
            .sublist(group.length - p.freeQty)
            .fold<double>(0, (s, u) => s + u.price);
        final full = group.fold<double>(0, (s, u) => s + u.price);
        if (full <= 0) continue;
        for (final u in group) {
          out[u] = saving * u.price / full;
        }
      }
    case PromoKind.percentOff:
      if (units.length < (p.buyQty < 1 ? 1 : p.buyQty)) return null;
      final pct = p.value.clamp(0, 100) / 100;
      for (final u in units) {
        out[u] = u.price * pct;
      }
  }
  return out.isEmpty ? null : _Offer(p, out);
}
