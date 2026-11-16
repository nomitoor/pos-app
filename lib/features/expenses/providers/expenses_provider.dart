import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_helper.dart';
import '../../../models/expense.dart';

final expensesProvider = AsyncNotifierProvider<ExpensesNotifier, List<Expense>>(
  ExpensesNotifier.new,
);

class ExpensesNotifier extends AsyncNotifier<List<Expense>> {
  @override
  Future<List<Expense>> build() => DatabaseHelper.instance.getExpenses();

  Future<void> save(Expense e) async {
    await DatabaseHelper.instance.saveExpense(e);
    ref.invalidateSelf();
  }

  Future<void> delete(int id) async {
    await DatabaseHelper.instance.deleteExpense(id);
    ref.invalidateSelf();
  }
}
