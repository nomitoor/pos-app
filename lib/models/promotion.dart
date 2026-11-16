import 'dart:convert';

enum PromoKind {
  /// Buy [Promotion.buyQty] for [Promotion.value] rupees.
  bundle('Bundle price'),

  /// Buy [Promotion.buyQty], get [Promotion.freeQty] free (cheapest free).
  buyGetFree('Buy X get Y free'),

  /// [Promotion.value]% off, when buying at least [Promotion.buyQty].
  percentOff('% off');

  final String label;
  const PromoKind(this.label);
}

enum PromoScope {
  products('Specific products'),
  type('A product type'),
  all('Everything');

  final String label;
  const PromoScope(this.label);
}

class Promotion {
  final int? id;
  final String name;
  final PromoKind kind;

  /// Bundle: pieces per bundle. Buy-get-free: pieces to buy.
  /// Percent off: minimum pieces (1 = no minimum).
  final int buyQty;

  /// Buy-get-free only: pieces given free per group.
  final int freeQty;

  /// Bundle: bundle price in rupees. Percent off: the percentage.
  final double value;

  final PromoScope scope;
  final String? scopeType; // PromoScope.type
  final List<String> barcodes; // PromoScope.products

  final DateTime? startsAt; // inclusive, from the start of that day
  final DateTime? endsAt; // inclusive, to the end of that day
  final bool active;

  const Promotion({
    this.id,
    required this.name,
    required this.kind,
    required this.buyQty,
    this.freeQty = 0,
    this.value = 0,
    required this.scope,
    this.scopeType,
    this.barcodes = const [],
    this.startsAt,
    this.endsAt,
    this.active = true,
  });

  bool isLiveAt(DateTime now) {
    if (!active) return false;
    if (startsAt != null &&
        now.isBefore(
          DateTime(startsAt!.year, startsAt!.month, startsAt!.day),
        )) {
      return false;
    }
    if (endsAt != null &&
        !now.isBefore(DateTime(endsAt!.year, endsAt!.month, endsAt!.day + 1))) {
      return false;
    }
    return true;
  }

  /// Whether a product (by barcode / type) is covered by this offer.
  bool covers(String barcode, String? type) => switch (scope) {
    PromoScope.all => true,
    PromoScope.type => type != null && type == scopeType,
    PromoScope.products => barcodes.contains(barcode),
  };

  /// Short customer-facing description, e.g. "Buy 2 for Rs 2000".
  String get summary {
    String n(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    return switch (kind) {
      PromoKind.bundle => 'Buy $buyQty for Rs ${n(value)}',
      PromoKind.buyGetFree => 'Buy $buyQty get $freeQty free',
      PromoKind.percentOff =>
        buyQty > 1
            ? '${n(value)}% off when you buy $buyQty+'
            : '${n(value)}% off',
    };
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'buy_qty': buyQty,
    'free_qty': freeQty,
    'value': value,
    'scope': scope.name,
    'scope_type': scopeType,
    'barcodes': jsonEncode(barcodes),
    'starts_at': startsAt?.toIso8601String(),
    'ends_at': endsAt?.toIso8601String(),
    'active': active ? 1 : 0,
  };

  factory Promotion.fromMap(Map<String, dynamic> m) => Promotion(
    id: m['id'] as int?,
    name: m['name'] as String,
    kind: PromoKind.values.byName(m['kind'] as String),
    buyQty: m['buy_qty'] as int,
    freeQty: m['free_qty'] as int? ?? 0,
    value: (m['value'] as num?)?.toDouble() ?? 0,
    scope: PromoScope.values.byName(m['scope'] as String),
    scopeType: m['scope_type'] as String?,
    barcodes: (jsonDecode(m['barcodes'] as String? ?? '[]') as List)
        .cast<String>(),
    startsAt: DateTime.tryParse(m['starts_at'] as String? ?? ''),
    endsAt: DateTime.tryParse(m['ends_at'] as String? ?? ''),
    active: (m['active'] as int? ?? 1) == 1,
  );
}
