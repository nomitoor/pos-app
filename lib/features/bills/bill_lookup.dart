import '../../core/database/database_helper.dart';
import '../../models/bill.dart';
import '../../models/sale_return.dart';

/// Result of looking up a scanned/typed code.
class BillLookup {
  final Bill? bill;

  /// Set when the code was a credit note (return) rather than an invoice.
  final SaleReturn? viaReturn;
  const BillLookup(this.bill, this.viaReturn);
}

/// Finds the bill for an invoice number (INV-…, or older BILL-…) or a credit note number
/// (RET-…, resolved to its original bill). Case and spaces are ignored.
BillLookup findBillByCode(
  String code,
  List<Bill> bills,
  List<SaleReturn> returns,
) {
  final c = code.trim().toUpperCase();
  final n = Bill.normalizeNumber(code);
  for (final b in bills) {
    if (Bill.normalizeNumber(b.billNumber) == n) return BillLookup(b, null);
  }
  for (final r in returns) {
    if (r.returnNumber.toUpperCase() == c) {
      final bill = r.billId == null
          ? null
          : bills.where((b) => b.id == r.billId).firstOrNull;
      return BillLookup(bill, r);
    }
  }
  return const BillLookup(null, null);
}

/// Same as [findBillByCode], but looks the bill up in the database rather
/// than in a loaded list (voided bills included, so they can be shown).
Future<BillLookup> lookupBillByCode(
  String code,
  List<SaleReturn> returns,
) async {
  final db = DatabaseHelper.instance;
  final bill = await db.getBillByNumber(code);
  if (bill != null) return BillLookup(bill, null);
  final c = code.trim().toUpperCase();
  for (final r in returns) {
    if (r.returnNumber.toUpperCase() == c) {
      final b = r.billId == null ? null : await db.getBillById(r.billId!);
      return BillLookup(b, r);
    }
  }
  return const BillLookup(null, null);
}

/// Whether [bill] matches a search box query: bill number, item name,
/// customer, payment method or amount.
bool billMatches(Bill bill, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return bill.billNumber.toLowerCase().contains(q) ||
      (bill.customerName?.toLowerCase().contains(q) ?? false) ||
      (bill.paymentMethod?.toLowerCase().contains(q) ?? false) ||
      bill.totalAmount.toStringAsFixed(0).contains(q) ||
      bill.items.any((i) => i.name.toLowerCase().contains(q));
}
