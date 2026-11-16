import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../../core/database/database_helper.dart';
import '../../models/bill.dart';
import '../../models/customer.dart';
import '../../models/online_order.dart';
import '../../models/sale_return.dart';
import '../bills/providers/bills_provider.dart';
import '../customers/ledger.dart';
import '../customers/providers/customers_provider.dart';
import '../inventory/providers/inventory_provider.dart';
import '../returns/providers/returns_provider.dart';
import 'online_store_service.dart';

/// Online orders, newest first. Refreshes every minute while the owner is
/// signed in, so the dashboard badge stays current.
final onlineOrdersProvider =
    AsyncNotifierProvider<OnlineOrdersNotifier, List<OnlineOrder>>(
      OnlineOrdersNotifier.new,
    );

class OnlineOrdersNotifier extends AsyncNotifier<List<OnlineOrder>> {
  Timer? _timer;

  @override
  Future<List<OnlineOrder>> build() async {
    ref.onDispose(() => _timer?.cancel());
    final owner = await ref.watch(shopOwnerProvider.future);
    _timer?.cancel();
    if (owner != true) return const [];
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => refresh());

    // Instant updates: Supabase Realtime tells us the moment an order is
    // placed (needs `orders` in the supabase_realtime publication, see
    // supabase/store.sql). The one-minute timer above is the fallback.
    final client = Supabase.instance.client;
    final channel = client
        .channel('pos-online-orders')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'orders',
          callback: (_) => refresh(),
        )
        .subscribe();
    ref.onDispose(() => client.removeChannel(channel));

    return _fetch();
  }

  static Future<List<OnlineOrder>> _fetch() async {
    final rows = await Supabase.instance.client
        .from('orders')
        .select('*, order_items(*)')
        .order('created_at', ascending: false)
        .limit(300);
    return [for (final r in rows) OnlineOrder.fromMap(r)];
  }

  Future<void> refresh() async {
    try {
      state = AsyncData(await _fetch());
    } catch (e, s) {
      // Keep showing what we had; surface the error only if we had nothing.
      if (!state.hasValue) state = AsyncError(e, s);
    }
  }

  void _replace(OnlineOrder o) {
    final list = state.value ?? const <OnlineOrder>[];
    state = AsyncData([for (final x in list) x.id == o.id ? o : x]);
  }

  Future<OnlineOrder> _setStatus(
    OnlineOrder o,
    String status, {
    String? note,
    String? billNumber,
  }) async {
    final row = await Supabase.instance.client
        .from('orders')
        .update({
          'status': status,
          'status_note': ?note,
          'pos_bill_number': ?billNumber,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', o.id)
        .select('*, order_items(*)')
        .single();
    final updated = OnlineOrder.fromMap(row);
    _replace(updated);
    return updated;
  }

  // ─── Actions ──────────────────────────────────────────────

  /// Lines whose size doesn't have enough stock in the POS.
  Future<List<String>> stockProblems(OnlineOrder o) async {
    final db = DatabaseHelper.instance;
    final products = {for (final p in await db.getAllProducts()) p.id: p};
    return [
      for (final i in o.items)
        if ((products[i.variantId]?.quantity ?? 0) < i.quantity)
          '${i.name} (${i.size ?? 'one size'}): ordered ${i.quantity}, '
              'in stock ${products[i.variantId]?.quantity ?? 0}'
              '${products[i.variantId] == null ? ' (product deleted)' : ''}',
    ];
  }

  /// Accept: creates the POS bill (stock out, customer owes the total as
  /// COD), then marks the order confirmed. Safe to call again if it fails
  /// halfway: an existing bill with this order number is reused.
  Future<OnlineOrder> accept(OnlineOrder o) async {
    final db = DatabaseHelper.instance;
    final existing = await db.getBillByNumber(o.orderNo);
    if (existing == null || existing.isVoided) {
      final problems = await stockProblems(o);
      if (problems.isNotEmpty) {
        throw StateError('Not enough stock:\n${problems.join('\n')}');
      }
      final customer = await _customerFor(o);
      final products = {for (final p in await db.getAllProducts()) p.id: p};
      final items = [
        for (final i in o.items)
          BillItem(
            barcode: products[i.variantId]!.barcode,
            name: i.name,
            price: i.price,
            quantity: i.quantity,
            size: i.size,
            type: products[i.variantId]!.type,
            costPrice: products[i.variantId]!.costPrice,
          ),
      ];
      await db.checkout(
        Bill(
          billNumber: o.orderNo,
          items: items,
          totalAmount: o.subtotal,
          createdAt: DateTime.now(),
          paymentMethod: Bill.udhaar, // paid in cash on delivery
          customerId: customer.id,
          customerName: customer.name,
          customerPhone: customer.phone,
        ),
      );
      _refreshPos();
    }
    return _setStatus(o, OnlineOrder.confirmed, billNumber: o.orderNo);
  }

  Future<OnlineOrder> markPacked(OnlineOrder o) =>
      _setStatus(o, OnlineOrder.packed);

  Future<OnlineOrder> markOutForDelivery(OnlineOrder o) =>
      _setStatus(o, OnlineOrder.outForDelivery);

  /// Delivered: the COD cash is recorded against the bill, so it shows in
  /// today's cash drawer (day close).
  Future<OnlineOrder> markDelivered(OnlineOrder o) async {
    final bill = await _billFor(o);
    if (bill != null) {
      final payments = await DatabaseHelper.instance.getCustomerPayments();
      final unpaid = unpaidOnBill(bill, payments);
      if (unpaid > 0.005 && bill.customerId != null) {
        await DatabaseHelper.instance.addCustomerPayment(
          CustomerPayment(
            customerId: bill.customerId!,
            billId: bill.id,
            amount: unpaid,
            method: Bill.cash,
            note: 'Cash on delivery (${o.orderNo})',
            createdAt: DateTime.now(),
          ),
        );
        ref.invalidate(customerPaymentsProvider);
      }
    }
    return _setStatus(o, OnlineOrder.delivered);
  }

  /// Reject a new order, or cancel an accepted one (its stock goes back and
  /// the amount owed is cleared). [reason] is shown to the customer.
  Future<OnlineOrder> cancel(OnlineOrder o, String reason) async {
    if (o.isNew) {
      return _setStatus(o, OnlineOrder.rejected, note: reason);
    }
    final bill = await _billFor(o);
    if (bill != null) {
      final already = await DatabaseHelper.instance.returnedQtyForBill(
        bill.id!,
      );
      final items = <ReturnItem>[];
      for (final i in bill.items) {
        final left = i.quantity - (already[i.barcode] ?? 0);
        if (left <= 0) continue;
        items.add(
          ReturnItem(
            barcode: i.barcode,
            name: i.name,
            price: i.price,
            quantity: left,
            refund: refundFor(bill, i, left),
            restocked: true,
            size: i.size,
            type: i.type,
            costPrice: i.costPrice,
          ),
        );
      }
      if (items.isNotEmpty) {
        await ref
            .read(returnsProvider.notifier)
            .addReturn(
              bill,
              SaleReturn(
                returnNumber: 'RET-${o.orderNo}',
                billId: bill.id,
                billNumber: bill.billNumber,
                items: items,
                reason: 'Online order cancelled',
                note: reason,
                // Clears what the customer owed; no cash changes hands.
                refundMethod: Bill.udhaar,
                createdAt: DateTime.now(),
              ),
            );
      }
      _refreshPos();
    }
    return _setStatus(o, OnlineOrder.cancelled, note: reason);
  }

  // ─── Helpers ──────────────────────────────────────────────

  Future<Bill?> _billFor(OnlineOrder o) async {
    final b = await DatabaseHelper.instance.getBillByNumber(
      o.posBillNumber ?? o.orderNo,
    );
    return (b == null || b.isVoided) ? null : b;
  }

  /// Finds the customer by phone, or adds them.
  Future<Customer> _customerFor(OnlineOrder o) async {
    String digits(String s) => s.replaceAll(RegExp(r'\D'), '');
    final want = Customer.whatsappNumber(o.phone);
    final all = await DatabaseHelper.instance.getCustomers();
    final found = all
        .where(
          (c) =>
              Customer.whatsappNumber(c.phone) == want ||
              digits(c.phone) == digits(o.phone),
        )
        .firstOrNull;
    if (found != null) return found;
    return ref
        .read(customersProvider.notifier)
        .save(
          Customer(
            name: o.customerName,
            phone: o.phone,
            note: [o.area, o.address].whereType<String>().join(', '),
            createdAt: DateTime.now(),
          ),
        );
  }

  void _refreshPos() {
    ref.invalidate(billsProvider);
    ref.invalidate(inventoryProvider); // also re-syncs website stock
    ref.invalidate(customersProvider);
    ref.invalidate(customerPaymentsProvider);
  }
}

/// Number of new (not yet accepted) online orders, for badges.
final newOnlineOrdersCountProvider = Provider<int>((ref) {
  if (!SupabaseConfig.isConfigured) return 0;
  final orders = ref.watch(onlineOrdersProvider).value ?? const [];
  return orders.where((o) => o.isNew).length;
});
