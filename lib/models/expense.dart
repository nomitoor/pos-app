class Expense {
  static const List<String> categories = [
    'Rent',
    'Salaries',
    'Electricity',
    'Gas / Water',
    'Internet / Phone',
    'Transport',
    'Repairs / Maintenance',
    'Marketing',
    'Packaging / Supplies',
    'Tea / Food',
    'Other',
  ];

  /// Where the money came from. "Cash drawer" lowers the expected cash at
  /// day close; anything else doesn't.
  static const String cashDrawer = 'Cash drawer';
  static const List<String> sources = [
    cashDrawer,
    'Bank / Card',
    'JazzCash / Easypaisa',
    'Owner pocket',
  ];

  final int? id;
  final String category;
  final double amount;
  final String paidFrom;
  final String? note;
  final DateTime date;

  const Expense({
    this.id,
    required this.category,
    required this.amount,
    required this.paidFrom,
    this.note,
    required this.date,
  });

  bool get fromDrawer => paidFrom == cashDrawer;

  Map<String, dynamic> toMap() => {
    'id': id,
    'category': category,
    'amount': amount,
    'paid_from': paidFrom,
    'note': note,
    'date': date.toIso8601String(),
  };

  factory Expense.fromMap(Map<String, dynamic> m) => Expense(
    id: m['id'] as int?,
    category: m['category'] as String,
    amount: (m['amount'] as num).toDouble(),
    paidFrom: m['paid_from'] as String,
    note: m['note'] as String?,
    date: DateTime.parse(m['date'] as String),
  );
}
