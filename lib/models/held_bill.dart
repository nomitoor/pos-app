import 'dart:convert';
import 'bill.dart';

/// A cart parked for later (e.g. customer is trying something on).
class HeldBill {
  final int? id;
  final String label;
  final List<BillItem> items; // at list price, as in the cart
  final DateTime createdAt;

  const HeldBill({
    this.id,
    required this.label,
    required this.items,
    required this.createdAt,
  });

  int get pieces => items.fold(0, (s, i) => s + i.quantity);
  double get listTotal => items.fold(0, (s, i) => s + i.subtotal);

  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'items': jsonEncode(items.map((e) => e.toMap()).toList()),
    'created_at': createdAt.toIso8601String(),
  };

  factory HeldBill.fromMap(Map<String, dynamic> m) => HeldBill(
    id: m['id'] as int?,
    label: m['label'] as String,
    items: (jsonDecode(m['items'] as String) as List)
        .map((e) => BillItem.fromMap(e as Map<String, dynamic>))
        .toList(),
    createdAt: DateTime.parse(m['created_at'] as String),
  );
}
