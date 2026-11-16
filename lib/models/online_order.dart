/// An order placed on the online store (Supabase `orders` + `order_items`).
class OnlineOrder {
  static const pending = 'pending';
  static const confirmed = 'confirmed';
  static const packed = 'packed';
  static const outForDelivery = 'out_for_delivery';
  static const delivered = 'delivered';
  static const cancelled = 'cancelled';
  static const rejected = 'rejected';

  final int id;
  final String orderNo;
  final String customerName;
  final String phone;
  final String address;
  final String? area;
  final String city;
  final String? notes;
  final String status;
  final String? statusNote;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final String? posBillNumber;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<OnlineOrderItem> items;

  const OnlineOrder({
    required this.id,
    required this.orderNo,
    required this.customerName,
    required this.phone,
    required this.address,
    this.area,
    required this.city,
    this.notes,
    required this.status,
    this.statusNote,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    this.posBillNumber,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
  });

  bool get isNew => status == pending;
  bool get isActive =>
      status == confirmed || status == packed || status == outForDelivery;
  bool get isDone =>
      status == delivered || status == cancelled || status == rejected;

  int get pieces => items.fold(0, (s, i) => s + i.quantity);

  String get statusLabel => labelFor(status);

  static String labelFor(String s) => switch (s) {
    pending => 'New',
    confirmed => 'Confirmed',
    packed => 'Packed',
    outForDelivery => 'Out for delivery',
    delivered => 'Delivered',
    cancelled => 'Cancelled',
    rejected => 'Rejected',
    _ => s,
  };

  factory OnlineOrder.fromMap(Map<String, dynamic> m) => OnlineOrder(
    id: (m['id'] as num).toInt(),
    orderNo: m['order_no'] as String,
    customerName: m['customer_name'] as String,
    phone: m['phone'] as String,
    address: m['address'] as String,
    area: m['area'] as String?,
    city: m['city'] as String? ?? 'Lahore',
    notes: m['notes'] as String?,
    status: m['status'] as String,
    statusNote: m['status_note'] as String?,
    subtotal: (m['subtotal'] as num).toDouble(),
    deliveryFee: (m['delivery_fee'] as num).toDouble(),
    total: (m['total'] as num).toDouble(),
    posBillNumber: m['pos_bill_number'] as String?,
    createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
    updatedAt: DateTime.parse(m['updated_at'] as String).toLocal(),
    items: [
      for (final i in (m['order_items'] as List? ?? const []))
        OnlineOrderItem.fromMap(i as Map<String, dynamic>),
    ],
  );
}

class OnlineOrderItem {
  /// The POS product id of this size (catalog ids are POS ids).
  final int variantId;
  final int designId;
  final String name;
  final String? size;
  final double price;
  final int quantity;

  const OnlineOrderItem({
    required this.variantId,
    required this.designId,
    required this.name,
    this.size,
    required this.price,
    required this.quantity,
  });

  double get subtotal => price * quantity;

  factory OnlineOrderItem.fromMap(Map<String, dynamic> m) => OnlineOrderItem(
    variantId: (m['variant_id'] as num).toInt(),
    designId: (m['design_id'] as num).toInt(),
    name: m['name'] as String,
    size: m['size'] as String?,
    price: (m['price'] as num).toDouble(),
    quantity: (m['quantity'] as num).toInt(),
  );
}
