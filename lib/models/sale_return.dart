/// One returned line from a bill.
class ReturnItem {
  final String barcode;
  final String name;

  /// Original unit price on the bill (before the bill's discount).
  final double price;
  final int quantity;

  /// Money given back for this line: price × qty less its share of the
  /// original bill's discount.
  final double refund;

  /// Whether the pieces went back into stock (false for damaged goods).
  final bool restocked;

  final String? size;
  final String? type;
  final double? costPrice;

  const ReturnItem({
    required this.barcode,
    required this.name,
    required this.price,
    required this.quantity,
    required this.refund,
    required this.restocked,
    this.size,
    this.type,
    this.costPrice,
  });

  Map<String, dynamic> toMap() => {
    'barcode': barcode,
    'name': name,
    'price': price,
    'quantity': quantity,
    'refund': refund,
    'restocked': restocked,
    if (size != null) 'size': size,
    if (type != null) 'type': type,
    if (costPrice != null) 'cost_price': costPrice,
  };

  factory ReturnItem.fromMap(Map<String, dynamic> m) => ReturnItem(
    barcode: m['barcode'] as String,
    name: m['name'] as String,
    price: (m['price'] as num).toDouble(),
    quantity: m['quantity'] as int,
    refund: (m['refund'] as num).toDouble(),
    restocked: m['restocked'] as bool? ?? true,
    size: m['size'] as String?,
    type: m['type'] as String?,
    costPrice: (m['cost_price'] as num?)?.toDouble(),
  );
}

/// A return/refund against an earlier bill.
class SaleReturn {
  static const List<String> reasons = [
    'Wrong size',
    'Defective / damaged',
    'Not as expected',
    'Changed mind',
    'Wrong item given',
    'Other',
  ];

  final int? id;
  final String returnNumber;

  /// The original bill. [billId] is null if that bill was later deleted.
  final int? billId;
  final String billNumber;

  final List<ReturnItem> items;
  final String reason;
  final String? note;

  /// How the money was given back (one of Bill.paymentMethods).
  final String refundMethod;

  /// True when the customer took other goods instead (a new bill follows).
  final bool isExchange;
  final DateTime createdAt;

  const SaleReturn({
    this.id,
    required this.returnNumber,
    required this.billId,
    required this.billNumber,
    required this.items,
    required this.reason,
    required this.refundMethod,
    required this.createdAt,
    this.note,
    this.isExchange = false,
  });

  double get refundAmount => items.fold(0, (s, i) => s + i.refund);
  int get itemCount => items.fold(0, (s, i) => s + i.quantity);
}
