import 'dart:convert';

/// A saved end-of-day (Z) report.
class DayClose {
  final int? id;
  final DateTime periodStart;
  final DateTime closedAt;

  /// Cash in the drawer at the start of the period.
  final double openingFloat;
  final double expectedCash;
  final double countedCash;

  /// Cash left in the drawer for the next day (next opening float).
  final double floatKept;
  final String? note;

  /// Snapshot of the report figures (see ZReport.toMap) for reprinting.
  final Map<String, dynamic> summary;

  const DayClose({
    this.id,
    required this.periodStart,
    required this.closedAt,
    required this.openingFloat,
    required this.expectedCash,
    required this.countedCash,
    required this.floatKept,
    this.note,
    required this.summary,
  });

  /// Positive = extra cash, negative = shortage.
  double get difference => countedCash - expectedCash;

  /// Cash taken out of the drawer (to bank / owner) at close.
  double get cashRemoved => countedCash - floatKept;

  Map<String, dynamic> toMap() => {
    'id': id,
    'period_start': periodStart.toIso8601String(),
    'closed_at': closedAt.toIso8601String(),
    'opening_float': openingFloat,
    'expected_cash': expectedCash,
    'counted_cash': countedCash,
    'float_kept': floatKept,
    'note': note,
    'summary': jsonEncode(summary),
  };

  factory DayClose.fromMap(Map<String, dynamic> m) => DayClose(
    id: m['id'] as int?,
    periodStart: DateTime.parse(m['period_start'] as String),
    closedAt: DateTime.parse(m['closed_at'] as String),
    openingFloat: (m['opening_float'] as num).toDouble(),
    expectedCash: (m['expected_cash'] as num).toDouble(),
    countedCash: (m['counted_cash'] as num).toDouble(),
    floatKept: (m['float_kept'] as num).toDouble(),
    note: m['note'] as String?,
    summary: (jsonDecode(m['summary'] as String) as Map)
        .cast<String, dynamic>(),
  );
}
