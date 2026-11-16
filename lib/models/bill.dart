import 'dart:math';

class BillItem {
  final String barcode;
  final String name;
  final double price;
  int quantity;

  /// Product size/type at the time of sale (null on bills saved before
  /// these fields existed, or for products without them).
  final String? size;
  final String? type;

  /// Unit cost at the time of sale; null when unknown.
  final double? costPrice;

  /// Normal price per piece when a promotion lowered [price]; null if no
  /// promotion applied. [price] is always what was actually charged.
  final double? listPrice;

  /// Name of the promotion(s) applied, if any.
  final String? promo;

  BillItem({
    required this.barcode,
    required this.name,
    required this.price,
    required this.quantity,
    this.size,
    this.type,
    this.costPrice,
    this.listPrice,
    this.promo,
  });

  double get subtotal => price * quantity;

  /// Money saved on this line by promotions.
  double get promoSavings =>
      listPrice == null ? 0 : (listPrice! - price) * quantity;

  Map<String, dynamic> toMap() {
    return {
      'barcode': barcode,
      'name': name,
      'price': price,
      'quantity': quantity,
      if (size != null) 'size': size,
      if (type != null) 'type': type,
      if (costPrice != null) 'cost_price': costPrice,
      if (listPrice != null) 'list_price': listPrice,
      if (promo != null) 'promo': promo,
    };
  }

  factory BillItem.fromMap(Map<String, dynamic> map) {
    return BillItem(
      barcode: map['barcode'],
      name: map['name'],
      price: map['price'].toDouble(),
      quantity: map['quantity'],
      size: map['size'] as String?,
      type: map['type'] as String?,
      costPrice: (map['cost_price'] as num?)?.toDouble(),
      listPrice: (map['list_price'] as num?)?.toDouble(),
      promo: map['promo'] as String?,
    );
  }
}

class Bill {
  static const String cash = 'Cash';

  /// Sold on credit to a customer; they pay later.
  static const String udhaar = 'Udhaar';

  /// Ways money actually changes hands.
  static const List<String> moneyMethods = [
    cash,
    'Card',
    'JazzCash',
    'Easypaisa',
    'Bank Transfer',
  ];

  /// Everything selectable at checkout (udhaar needs a customer).
  static const List<String> paymentMethods = [...moneyMethods, udhaar];

  final int? id;
  final String billNumber;
  final List<BillItem> items;

  /// Amount payable: items subtotal minus [discount].
  final double totalAmount;
  final DateTime createdAt;

  /// Bill-level discount in rupees (0 when none).
  final double discount;

  /// How the customer paid; null on bills saved before this existed.
  final String? paymentMethod;

  /// Customer on the bill (optional; required for udhaar). Name and phone
  /// are copied so the invoice stays correct if the customer is edited.
  final int? customerId;
  final String? customerName;
  final String? customerPhone;

  /// When the bill was voided (cancelled), or null. A voided bill stays in
  /// history for the record but no longer counts in sales, stock or udhaar.
  final DateTime? voidedAt;
  final String? voidReason;

  /// Internal running number (1, 2, 3, …) in the order bills were made.
  /// Shown only inside the app, never printed, so the shop can see every
  /// sale in order while customers can't infer sales volume.
  final int? serial;

  /// Prefix for POS invoice numbers, e.g. INV-K7Q3-9XPM.
  /// (Online-store bills keep their order number, e.g. UT-251113-4821.)
  static const numberPrefix = 'INV-';

  /// Letters and digits that can't be misread: no 0/O, 1/I/L, or U.
  static const _codeChars = '23456789ABCDEFGHJKMNPQRSTVWXYZ';
  static final _random = Random.secure();

  /// A new unpredictable invoice number, e.g. INV-K7Q3-9XPM
  /// (8 characters from 30: about 650 billion possibilities).
  static String randomNumber([Random? random]) {
    final r = random ?? _random;
    String part() => List.generate(
      4,
      (_) => _codeChars[r.nextInt(_codeChars.length)],
    ).join();
    return '$numberPrefix${part()}-${part()}';
  }

  /// A typed or scanned bill number in the form stored for lookups:
  /// upper case, without spaces or dashes (so "inv k7q3 9xpm" matches).
  static String normalizeNumber(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');

  Bill({
    this.id,
    required this.billNumber,
    required this.items,
    required this.totalAmount,
    required this.createdAt,
    this.discount = 0,
    this.paymentMethod,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.voidedAt,
    this.voidReason,
    this.serial,
  });

  bool get isUdhaar => paymentMethod == udhaar;
  bool get isVoided => voidedAt != null;

  Bill copyWith({int? id, String? billNumber, int? serial}) => Bill(
    id: id ?? this.id,
    billNumber: billNumber ?? this.billNumber,
    serial: serial ?? this.serial,
    items: items,
    totalAmount: totalAmount,
    createdAt: createdAt,
    discount: discount,
    paymentMethod: paymentMethod,
    customerId: customerId,
    customerName: customerName,
    customerPhone: customerPhone,
    voidedAt: voidedAt,
    voidReason: voidReason,
  );

  /// Sum of item subtotals (after promotions), before the bill discount.
  double get subtotal => items.fold(0, (s, i) => s + i.subtotal);

  /// Total saved by promotions on this bill.
  double get promoSavings => items.fold(0, (s, i) => s + i.promoSavings);
}
