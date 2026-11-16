import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_helper.dart';
import '../../../models/bill.dart';
import '../../../models/sale_return.dart';
import '../../bills/providers/bills_provider.dart';
import '../../inventory/providers/inventory_provider.dart';

final returnsProvider =
    AsyncNotifierProvider<ReturnsNotifier, List<SaleReturn>>(
      ReturnsNotifier.new,
    );

class ReturnsNotifier extends AsyncNotifier<List<SaleReturn>> {
  @override
  Future<List<SaleReturn>> build() => DatabaseHelper.instance.getAllReturns();

  Future<void> addReturn(Bill bill, SaleReturn ret) async {
    await DatabaseHelper.instance.insertReturn(bill, ret);
    ref.invalidateSelf();
    ref.invalidate(inventoryProvider); // restocked quantities
    ref.invalidate(billsProvider);
  }
}

/// Quantity already returned per barcode, keyed by bill id.
final returnedQtyByBillProvider = Provider<Map<int, Map<String, int>>>((ref) {
  final returns = ref.watch(returnsProvider).value ?? const [];
  final out = <int, Map<String, int>>{};
  for (final r in returns) {
    if (r.billId == null) continue;
    final m = out.putIfAbsent(r.billId!, () => {});
    for (final i in r.items) {
      m[i.barcode] = (m[i.barcode] ?? 0) + i.quantity;
    }
  }
  return out;
});

/// Refund for returning [qty] of [item] from [bill]: the item's price less
/// its proportional share of the bill's discount.
double refundFor(Bill bill, BillItem item, int qty) {
  final subtotal = bill.subtotal;
  final keep = subtotal > 0 ? (subtotal - bill.discount) / subtotal : 1.0;
  return item.price * qty * keep;
}
