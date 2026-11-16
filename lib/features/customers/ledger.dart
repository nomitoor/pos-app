import '../../models/bill.dart';
import '../../models/customer.dart';
import '../../models/sale_return.dart';

/// One line in a customer's account history.
class LedgerEntry {
  final DateTime at;
  final String description;

  /// Positive = customer owes more (udhaar sale); negative = less
  /// (payment, or a return credited to the account).
  final double amount;
  final Bill? bill;
  final CustomerPayment? payment;

  const LedgerEntry(
    this.at,
    this.description,
    this.amount, {
    this.bill,
    this.payment,
  });
}

/// A customer's purchases and udhaar position.
class CustomerAccount {
  final Customer customer;
  final List<Bill> bills; // every bill with this customer, newest first
  final List<LedgerEntry> ledger; // udhaar movements, newest first

  const CustomerAccount(this.customer, this.bills, this.ledger);

  /// What the customer owes the shop (negative = shop owes them credit).
  double get balance => ledger.fold(0, (s, e) => s + e.amount);

  double get totalSpent => bills.fold(0, (s, b) => s + b.totalAmount);
  DateTime? get lastVisit => bills.isEmpty ? null : bills.first.createdAt;
}

/// Builds every customer's account from bills, returns and payments.
Map<int, CustomerAccount> buildAccounts({
  required List<Customer> customers,
  required List<Bill> bills,
  required List<SaleReturn> returns,
  required List<CustomerPayment> payments,
}) {
  final billsById = {
    for (final b in bills)
      if (b.id != null) b.id!: b,
  };
  final out = <int, CustomerAccount>{};

  for (final c in customers) {
    final id = c.id!;
    final theirBills = bills.where((b) => b.customerId == id).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final ledger = <LedgerEntry>[
      for (final b in theirBills)
        if (b.isUdhaar)
          LedgerEntry(
            b.createdAt,
            'Udhaar sale ${b.billNumber}',
            b.totalAmount,
            bill: b,
          ),
      for (final p in payments)
        if (p.customerId == id)
          LedgerEntry(
            p.createdAt,
            'Payment (${p.method})',
            -p.amount,
            payment: p,
          ),
      // A return refunded "to udhaar" reduces what they owe.
      for (final r in returns)
        if (r.refundMethod == Bill.udhaar &&
            billsById[r.billId]?.customerId == id)
          LedgerEntry(
            r.createdAt,
            'Return ${r.returnNumber}',
            -r.refundAmount,
            bill: billsById[r.billId],
          ),
    ]..sort((a, b) => b.at.compareTo(a.at));
    out[id] = CustomerAccount(c, theirBills, ledger);
  }
  return out;
}

/// Amount still unpaid on one udhaar bill (total − payments made against
/// it at checkout). Later general payments aren't tied to a bill.
double unpaidOnBill(Bill bill, List<CustomerPayment> payments) {
  if (!bill.isUdhaar) return 0;
  final paid = payments
      .where((p) => p.billId == bill.id)
      .fold<double>(0, (s, p) => s + p.amount);
  return (bill.totalAmount - paid).clamp(0, double.infinity).toDouble();
}
