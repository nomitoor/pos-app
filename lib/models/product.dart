class Product {
  /// Sizes offered in the product form's dropdown.
  /// Standard sizes, smallest first. Custom sizes (e.g. waist "32") are
  /// also allowed on a product.
  static const List<String> sizes = [
    'Extra Small',
    'Small',
    'Medium',
    'Large',
    'Extra Large',
    'XXL',
  ];

  /// Product types offered in the product form's dropdown.
  static const List<String> types = [
    'Hoodie',
    'Sweatshirt',
    'Trouser',
    'T-Shirt',
    'Shirt',
    'Jacket',
    'Jeans',
    'Shorts',
    'Other',
  ];

  /// Prefix for internal codes given to products saved without a barcode.
  static const String autoCodePrefix = 'NB-';

  /// A unique internal code for a product that has no barcode. The cart,
  /// stock deduction and bills identify products by this value.
  static String generateAutoCode() =>
      '$autoCodePrefix${DateTime.now().microsecondsSinceEpoch}';

  final int? id;
  final String barcode;

  /// False when [barcode] is an auto-generated internal code.
  bool get hasRealBarcode => !barcode.startsWith(autoCodePrefix);
  final String name;
  final double price;
  int quantity;

  /// Optional size (one of [sizes]); null for products without a size.
  final String? size;

  /// Optional product type (one of [types]); null when not set.
  final String? type;

  /// What the shop paid per unit; null when unknown. Used for profit.
  final double? costPrice;

  /// The design (see Design) this size belongs to.
  final int? designId;

  Product({
    this.id,
    required this.barcode,
    required this.name,
    required this.price,
    required this.quantity,
    this.size,
    this.type,
    this.costPrice,
    this.designId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'barcode': barcode,
      'name': name,
      'price': price,
      'quantity': quantity,
      'size': size,
      'type': type,
      'cost_price': costPrice,
      'design_id': designId,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      barcode: map['barcode'],
      name: map['name'],
      price: map['price'].toDouble(),
      quantity: map['quantity'],
      size: map['size'] as String?,
      type: map['type'] as String?,
      costPrice: (map['cost_price'] as num?)?.toDouble(),
      designId: map['design_id'] as int?,
    );
  }

  Product copyWith({
    int? id,
    String? barcode,
    String? name,
    double? price,
    int? quantity,
    String? size,
    String? type,
    double? costPrice,
    int? designId,
  }) {
    return Product(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      name: name ?? this.name,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      size: size ?? this.size,
      type: type ?? this.type,
      costPrice: costPrice ?? this.costPrice,
      designId: designId ?? this.designId,
    );
  }
}
