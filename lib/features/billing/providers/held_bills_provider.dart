import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_helper.dart';
import '../../../models/held_bill.dart';

final heldBillsProvider =
    AsyncNotifierProvider<HeldBillsNotifier, List<HeldBill>>(
      HeldBillsNotifier.new,
    );

class HeldBillsNotifier extends AsyncNotifier<List<HeldBill>> {
  @override
  Future<List<HeldBill>> build() => DatabaseHelper.instance.getHeldBills();

  Future<void> hold(HeldBill h) async {
    await DatabaseHelper.instance.holdBill(h);
    ref.invalidateSelf();
  }

  Future<void> remove(int id) async {
    await DatabaseHelper.instance.deleteHeldBill(id);
    ref.invalidateSelf();
  }
}
