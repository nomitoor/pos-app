import 'dart:convert';
import 'product.dart';

/// A product design (e.g. "Classic Hoodie") that comes in several sizes.
/// Each size is a [Product] row (its own barcode, stock and price) linked
/// by [Product.designId]; billing, returns and reports work on those rows.
class Design {
  final int? id;
  final String name;
  final String? type;

  /// Default price for new sizes; a size can have its own price.
  final double price;
  final double? costPrice;
  final String? description;

  /// Photo file paths/URLs (filled in by the online-store phase).
  final List<String> photos;

  /// Whether this design is listed on the online store.
  final bool online;
  final DateTime createdAt;

  const Design({
    this.id,
    required this.name,
    this.type,
    required this.price,
    this.costPrice,
    this.description,
    this.photos = const [],
    this.online = false,
    required this.createdAt,
  });

  Design copyWith({
    int? id,
    String? name,
    String? type,
    double? price,
    double? costPrice,
    String? description,
    List<String>? photos,
    bool? online,
  }) => Design(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    price: price ?? this.price,
    costPrice: costPrice ?? this.costPrice,
    description: description ?? this.description,
    photos: photos ?? this.photos,
    online: online ?? this.online,
    createdAt: createdAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'type': type,
    'price': price,
    'cost_price': costPrice,
    'description': description,
    'photos': jsonEncode(photos),
    'online': online ? 1 : 0,
    'created_at': createdAt.toIso8601String(),
  };

  factory Design.fromMap(Map<String, dynamic> m) => Design(
    id: m['id'] as int?,
    name: m['name'] as String,
    type: m['type'] as String?,
    price: (m['price'] as num).toDouble(),
    costPrice: (m['cost_price'] as num?)?.toDouble(),
    description: m['description'] as String?,
    photos: (jsonDecode(m['photos'] as String? ?? '[]') as List).cast<String>(),
    online: (m['online'] as int? ?? 0) == 1,
    createdAt: DateTime.parse(m['created_at'] as String),
  );
}

/// A design with its sizes, for display.
class DesignGroup {
  final Design design;
  final List<Product> variants; // sorted by size

  const DesignGroup(this.design, this.variants);

  int get totalStock => variants.fold(0, (s, v) => s + v.quantity);
  bool get anyOut => variants.any((v) => v.quantity <= 0);
  bool get anyLow => variants.any((v) => v.quantity > 0 && v.quantity <= 5);

  double get minPrice => variants.isEmpty
      ? design.price
      : variants.map((v) => v.price).reduce((a, b) => a < b ? a : b);
  double get maxPrice => variants.isEmpty
      ? design.price
      : variants.map((v) => v.price).reduce((a, b) => a > b ? a : b);
}

/// Sort key so sizes appear XS, S, M, L, XL, XXL, then numbers (28, 30…),
/// then anything else alphabetically, then "no size".
int compareSizes(String? a, String? b) {
  (int, num, String) key(String? s) {
    if (s == null || s.isEmpty) return (3, 0, '');
    final i = Product.sizes.indexOf(s);
    if (i >= 0) return (0, i, '');
    final n = num.tryParse(s);
    if (n != null) return (1, n, '');
    return (2, 0, s.toLowerCase());
  }

  final ka = key(a), kb = key(b);
  if (ka.$1 != kb.$1) return ka.$1 - kb.$1;
  final c = ka.$2.compareTo(kb.$2);
  return c != 0 ? c : ka.$3.compareTo(kb.$3);
}

/// Short label for size chips: "Medium" → "M", "Extra Large" → "XL".
String shortSize(String? s) => switch (s) {
  null || '' => 'One size',
  'Extra Small' => 'XS',
  'Small' => 'S',
  'Medium' => 'M',
  'Large' => 'L',
  'Extra Large' => 'XL',
  'XXL' => 'XXL',
  _ => s,
};
