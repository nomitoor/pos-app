import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/bill.dart';
import '../providers/bills_provider.dart';

class EditBillScreen extends ConsumerStatefulWidget {
  final Bill bill;
  const EditBillScreen({super.key, required this.bill});

  @override
  ConsumerState<EditBillScreen> createState() => _EditBillScreenState();
}

class _EditBillScreenState extends ConsumerState<EditBillScreen> {
  late List<BillItem> _items;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _items = widget.bill.items
        .map(
          (i) => BillItem(
            barcode: i.barcode,
            name: i.name,
            price: i.price,
            quantity: i.quantity,
            size: i.size,
            type: i.type,
            costPrice: i.costPrice,
            listPrice: i.listPrice,
            promo: i.promo,
          ),
        )
        .toList();
  }

  // Matches DatabaseHelper.updateBill: the bill's discount is kept but
  // capped at the new subtotal.
  double get _total {
    final subtotal = _items.fold<double>(0, (sum, i) => sum + i.subtotal);
    final discount = math.min(widget.bill.discount, subtotal);
    return subtotal - discount;
  }

  void _incrementItem(int index) {
    setState(() => _items[index].quantity += 1);
  }

  void _decrementItem(int index) {
    setState(() {
      if (_items[index].quantity <= 1) {
        _items.removeAt(index);
      } else {
        _items[index].quantity -= 1;
      }
    });
  }

  Future<void> _save() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A bill needs at least one item. Delete it instead.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(billsProvider.notifier).editBill(widget.bill, _items);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError
                  ? e.message
                  : 'Not enough stock to increase quantity.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Edit ${widget.bill.billNumber}')),
      body: Column(
        children: [
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text('No items left'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Rs. ${item.price.toStringAsFixed(2)} each',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => _decrementItem(index),
                            ),
                            Text(
                              '${item.quantity}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => _incrementItem(index),
                            ),
                            SizedBox(
                              width: 72,
                              child: Text(
                                'Rs. ${item.subtotal.toStringAsFixed(2)}',
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: const Border(top: BorderSide(color: Colors.black12)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'TOTAL: Rs. ${_total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16171B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
