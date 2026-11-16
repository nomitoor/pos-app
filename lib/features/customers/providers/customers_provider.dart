import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_helper.dart';
import '../../../models/customer.dart';
import '../../bills/providers/bills_provider.dart';
import '../../returns/providers/returns_provider.dart';
import '../ledger.dart';

final customersProvider =
    AsyncNotifierProvider<CustomersNotifier, List<Customer>>(
      CustomersNotifier.new,
    );

class CustomersNotifier extends AsyncNotifier<List<Customer>> {
  @override
  Future<List<Customer>> build() => DatabaseHelper.instance.getCustomers();

  /// Returns the saved customer (with id).
  Future<Customer> save(Customer c) async {
    final id = await DatabaseHelper.instance.saveCustomer(c);
    ref.invalidateSelf();
    return Customer(
      id: id,
      name: c.name,
      phone: c.phone,
      note: c.note,
      createdAt: c.createdAt,
    );
  }

  Future<void> delete(int id) async {
    await DatabaseHelper.instance.deleteCustomer(id);
    ref.invalidateSelf();
  }
}

final customerPaymentsProvider =
    AsyncNotifierProvider<CustomerPaymentsNotifier, List<CustomerPayment>>(
      CustomerPaymentsNotifier.new,
    );

class CustomerPaymentsNotifier extends AsyncNotifier<List<CustomerPayment>> {
  @override
  Future<List<CustomerPayment>> build() =>
      DatabaseHelper.instance.getCustomerPayments();

  Future<void> add(CustomerPayment p) async {
    await DatabaseHelper.instance.addCustomerPayment(p);
    ref.invalidateSelf();
  }

  Future<void> delete(int id) async {
    await DatabaseHelper.instance.deleteCustomerPayment(id);
    ref.invalidateSelf();
  }
}

/// Every customer's account (bills, udhaar ledger, balance), by id.
final customerAccountsProvider = FutureProvider<Map<int, CustomerAccount>>((
  ref,
) async {
  return buildAccounts(
    customers: await ref.watch(customersProvider.future),
    // Only bills with a customer matter here (voided ones never count).
    bills: await () async {
      await ref.watch(billsProvider.future);
      return DatabaseHelper.instance.getBills(withCustomer: true);
    }(),
    returns: await ref.watch(returnsProvider.future),
    payments: await ref.watch(customerPaymentsProvider.future),
  );
});
