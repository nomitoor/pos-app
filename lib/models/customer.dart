class Customer {
  final int? id;
  final String name;
  final String phone;
  final String? note;
  final DateTime createdAt;

  const Customer({
    this.id,
    required this.name,
    required this.phone,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'note': note,
    'created_at': createdAt.toIso8601String(),
  };

  factory Customer.fromMap(Map<String, dynamic> m) => Customer(
    id: m['id'] as int?,
    name: m['name'] as String,
    phone: m['phone'] as String? ?? '',
    note: m['note'] as String?,
    createdAt: DateTime.parse(m['created_at'] as String),
  );

  /// Phone in international form for WhatsApp links, e.g. 0300-1234567 →
  /// 923001234567. Assumes Pakistan (+92) for local 03xx numbers.
  static String whatsappNumber(String phone) {
    var d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('00')) d = d.substring(2);
    if (d.startsWith('0') && d.length == 11) d = '92${d.substring(1)}';
    if (d.length == 10 && d.startsWith('3')) d = '92$d';
    return d;
  }
}

/// Money received from a customer against their udhaar (credit) balance.
class CustomerPayment {
  final int? id;
  final int customerId;

  /// The credit bill this was paid with at checkout, if any.
  final int? billId;
  final double amount;
  final String method; // one of Bill.paymentMethods (not Udhaar)
  final String? note;
  final DateTime createdAt;

  const CustomerPayment({
    this.id,
    required this.customerId,
    this.billId,
    required this.amount,
    required this.method,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'customer_id': customerId,
    'bill_id': billId,
    'amount': amount,
    'method': method,
    'note': note,
    'created_at': createdAt.toIso8601String(),
  };

  factory CustomerPayment.fromMap(Map<String, dynamic> m) => CustomerPayment(
    id: m['id'] as int?,
    customerId: m['customer_id'] as int,
    billId: m['bill_id'] as int?,
    amount: (m['amount'] as num).toDouble(),
    method: m['method'] as String,
    note: m['note'] as String?,
    createdAt: DateTime.parse(m['created_at'] as String),
  );
}
