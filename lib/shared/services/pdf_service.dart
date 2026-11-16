import 'dart:convert';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;
import 'package:printing/printing.dart';
import '../../core/theme/brand.dart';
import '../../models/bill.dart';
import '../../models/sale_return.dart';
import '../../models/shop_settings.dart';
import '../../features/day_close/z_report.dart';

// ── Palette ─────────────────────────────────────────────────
const _brand = PdfColor.fromInt(0xFF1E3A8A); // deep blue
const _brandLight = PdfColor.fromInt(0xFFEFF4FF);
const _ink = PdfColor.fromInt(0xFF111827);
const _muted = PdfColor.fromInt(0xFF6B7280);
const _line = PdfColor.fromInt(0xFFE5E7EB);
const _zebra = PdfColor.fromInt(0xFFF9FAFB);
const _green = PdfColor.fromInt(0xFF15803D);
const _red = PdfColor.fromInt(0xFFB91C1C);

final _money = NumberFormat('#,##0.00', 'en_US');
String _rs(double v) => 'Rs ${_money.format(v)}';

class PdfService {
  /// Urban Thread mark, used when the shop hasn't uploaded its own logo.
  static Uint8List? _brandMark;
  static bool _brandMarkTried = false;

  static Future<void> _loadBrandMark() async {
    if (_brandMarkTried) return;
    _brandMarkTried = true;
    try {
      final data = await rootBundle.load(Brand.markOnLight);
      _brandMark = data.buffer.asUint8List();
    } catch (_) {
      _brandMark = null; // asset missing (e.g. some tests): no logo
    }
  }

  static Future<void> generateAndOpenBill(
    Bill bill, [
    ShopSettings settings = const ShopSettings(),
  ]) async {
    final bytes = await buildBillPdf(bill, settings);
    await Printing.layoutPdf(
      onLayout: (format) async => bytes,
      name: '${bill.billNumber}.pdf',
    );
  }

  // ═══════════════════════════════════════════════════════════
  // INVOICE
  // ═══════════════════════════════════════════════════════════

  /// [paidOnBill]: for an udhaar bill, cash taken against it at checkout
  /// (the rest is shown as balance due).
  static Future<Uint8List> buildBillPdf(
    Bill bill, [
    ShopSettings settings = const ShopSettings(),
    double paidOnBill = 0,
  ]) async {
    await _loadBrandMark();
    final paid = bill.isUdhaar ? paidOnBill : bill.totalAmount;
    final due = bill.totalAmount - paid;
    final pdf = pw.Document(
      title: 'Invoice ${bill.billNumber}',
      author: settings.shopName,
    );

    final listSubtotal = bill.items.fold<double>(
      0,
      (s, i) => s + (i.listPrice ?? i.price) * i.quantity,
    );
    final pieces = bill.items.fold<int>(0, (s, i) => s + i.quantity);
    final saved = bill.promoSavings + bill.discount;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 28, 36, 28),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : _continuationHeader(settings, 'Invoice ${bill.billNumber}'),
        footer: (ctx) => _footer(ctx, settings, 'Invoice ${bill.billNumber}'),
        build: (ctx) => [
          _letterhead(
            settings,
            title: 'INVOICE',
            meta: [
              ('Invoice No.', bill.billNumber),
              ('Date', DateFormat('dd MMM yyyy').format(bill.createdAt)),
              ('Time', DateFormat('hh:mm a').format(bill.createdAt)),
              if (bill.paymentMethod != null) ('Payment', bill.paymentMethod!),
            ],
            stamp: due > 0.005
                ? ('UDHAAR', const PdfColor.fromInt(0xFFB45309))
                : ('PAID', _green),
          ),
          pw.SizedBox(height: 18),

          // ── Billed to / summary ──
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _infoBlock(
                  'BILLED TO',
                  bill.customerName == null
                      ? ['Walk-in customer']
                      : [bill.customerName!, ?bill.customerPhone],
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                child: _infoBlock('ORDER SUMMARY', [
                  '$pieces item${pieces == 1 ? '' : 's'} '
                      '(${bill.items.length} line${bill.items.length == 1 ? '' : 's'})',
                  due > 0.005 ? 'On credit: ${_rs(due)} due' : 'Paid in full',
                ]),
              ),
            ],
          ),
          pw.SizedBox(height: 18),

          // ── Items ──
          _itemsTable(bill),
          pw.SizedBox(height: 14),

          // ── Totals ──
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _label('AMOUNT IN WORDS'),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      _amountInWords(bill.totalAmount),
                      style: const pw.TextStyle(fontSize: 9.5, color: _ink),
                    ),
                    if (saved > 0.005) ...[
                      pw.SizedBox(height: 12),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: pw.BoxDecoration(
                          color: const PdfColor.fromInt(0xFFECFDF5),
                          border: pw.Border.all(
                            color: const PdfColor.fromInt(0xFFA7F3D0),
                          ),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Text(
                          'You saved ${_rs(saved)} on this purchase',
                          style: pw.TextStyle(
                            fontSize: 10,
                            color: _green,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(width: 24),
              pw.SizedBox(
                width: 230,
                child: pw.Column(
                  children: [
                    _totalRow('Subtotal', _rs(listSubtotal)),
                    if (bill.promoSavings > 0.005)
                      _totalRow(
                        'Offers',
                        '- ${_rs(bill.promoSavings)}',
                        color: _green,
                      ),
                    if (bill.discount > 0.005)
                      _totalRow(
                        'Discount',
                        '- ${_rs(bill.discount)}',
                        color: _green,
                      ),
                    pw.SizedBox(height: 4),
                    _grandTotal('TOTAL', _rs(bill.totalAmount), _brand),
                    pw.SizedBox(height: 4),
                    _totalRow(
                      bill.isUdhaar
                          ? 'Paid now (Cash)'
                          : 'Paid${bill.paymentMethod == null ? '' : ' (${bill.paymentMethod})'}',
                      _rs(paid),
                    ),
                    if (due > 0.005)
                      _totalRow('Balance due (udhaar)', _rs(due), color: _red)
                    else
                      _totalRow('Balance', _rs(0)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 24),

          // ── Terms + thanks + barcode ──
          _closing(settings, bill.billNumber),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _itemsTable(Bill bill) {
    final headStyle = pw.TextStyle(
      fontSize: 8.5,
      color: PdfColors.white,
      fontWeight: pw.FontWeight.bold,
      letterSpacing: 0.5,
    );

    pw.Widget cell(pw.Widget child, {pw.Alignment? align}) => pw.Container(
      alignment: align ?? pw.Alignment.centerLeft,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: child,
    );

    return pw.Table(
      columnWidths: const {
        0: pw.FixedColumnWidth(36),
        1: pw.FlexColumnWidth(5),
        2: pw.FixedColumnWidth(40),
        3: pw.FixedColumnWidth(90),
        4: pw.FixedColumnWidth(90),
      },
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _line, width: 0.6),
        bottom: pw.BorderSide(color: _line, width: 0.6),
      ),
      children: [
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: _brand),
          children: [
            cell(pw.Text('#', style: headStyle)),
            cell(pw.Text('DESCRIPTION', style: headStyle)),
            cell(pw.Text('QTY', style: headStyle), align: pw.Alignment.center),
            cell(
              pw.Text('UNIT PRICE', style: headStyle),
              align: pw.Alignment.centerRight,
            ),
            cell(
              pw.Text('AMOUNT', style: headStyle),
              align: pw.Alignment.centerRight,
            ),
          ],
        ),
        for (var n = 0; n < bill.items.length; n++)
          () {
            final i = bill.items[n];
            final details = [?i.type, ?i.size].join(' / ');
            return pw.TableRow(
              decoration: pw.BoxDecoration(
                color: n.isOdd ? _zebra : PdfColors.white,
              ),
              verticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: [
                cell(
                  pw.Text(
                    '${n + 1}',
                    style: const pw.TextStyle(fontSize: 9, color: _muted),
                  ),
                ),
                cell(
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        i.name,
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: _ink,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      if (details.isNotEmpty)
                        pw.Text(
                          details,
                          style: const pw.TextStyle(
                            fontSize: 8.5,
                            color: _muted,
                          ),
                        ),
                      if (i.promo != null)
                        pw.Text(
                          'Offer: ${i.promo}',
                          style: const pw.TextStyle(
                            fontSize: 8.5,
                            color: _green,
                          ),
                        ),
                    ],
                  ),
                ),
                cell(
                  pw.Text(
                    '${i.quantity}',
                    style: const pw.TextStyle(fontSize: 10, color: _ink),
                  ),
                  align: pw.Alignment.center,
                ),
                cell(
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      if (i.listPrice != null)
                        pw.Text(
                          _rs(i.listPrice!),
                          style: const pw.TextStyle(
                            fontSize: 8,
                            color: _muted,
                            decoration: pw.TextDecoration.lineThrough,
                          ),
                        ),
                      pw.Text(
                        _rs(i.price),
                        style: const pw.TextStyle(fontSize: 10, color: _ink),
                      ),
                    ],
                  ),
                  align: pw.Alignment.centerRight,
                ),
                cell(
                  pw.Text(
                    _rs(i.subtotal),
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: _ink,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  align: pw.Alignment.centerRight,
                ),
              ],
            );
          }(),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // CREDIT NOTE (refund / exchange)
  // ═══════════════════════════════════════════════════════════

  static Future<Uint8List> buildReturnPdf(
    SaleReturn ret, [
    ShopSettings settings = const ShopSettings(),
  ]) async {
    await _loadBrandMark();
    final pdf = pw.Document(
      title: 'Credit note ${ret.returnNumber}',
      author: settings.shopName,
    );
    final docName = 'Credit note ${ret.returnNumber}';
    final headStyle = pw.TextStyle(
      fontSize: 8.5,
      color: PdfColors.white,
      fontWeight: pw.FontWeight.bold,
      letterSpacing: 0.5,
    );
    pw.Widget cell(pw.Widget child, {pw.Alignment? align}) => pw.Container(
      alignment: align ?? pw.Alignment.centerLeft,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: child,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 28, 36, 28),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : _continuationHeader(settings, docName),
        footer: (ctx) => _footer(ctx, settings, docName),
        build: (ctx) => [
          _letterhead(
            settings,
            title: 'CREDIT NOTE',
            titleColor: _red,
            meta: [
              ('Credit Note No.', ret.returnNumber),
              ('Date', DateFormat('dd MMM yyyy').format(ret.createdAt)),
              ('Time', DateFormat('hh:mm a').format(ret.createdAt)),
              ('Against invoice', ret.billNumber),
            ],
            stamp: ret.isExchange
                ? ('EXCHANGE', const PdfColor.fromInt(0xFFB45309))
                : ('REFUNDED', _red),
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _infoBlock('REASON', [ret.reason, ?ret.note])),
              pw.SizedBox(width: 16),
              pw.Expanded(
                child:
                    _infoBlock(ret.isExchange ? 'SETTLEMENT' : 'REFUNDED VIA', [
                      ret.isExchange
                          ? 'Credit applied to a new purchase'
                          : ret.refundMethod,
                    ]),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Table(
            columnWidths: const {
              0: pw.FixedColumnWidth(36),
              1: pw.FlexColumnWidth(5),
              2: pw.FixedColumnWidth(40),
              3: pw.FixedColumnWidth(70),
              4: pw.FixedColumnWidth(90),
            },
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: _line, width: 0.6),
              bottom: pw.BorderSide(color: _line, width: 0.6),
            ),
            children: [
              pw.TableRow(
                repeat: true,
                decoration: const pw.BoxDecoration(color: _red),
                children: [
                  cell(pw.Text('#', style: headStyle)),
                  cell(pw.Text('RETURNED ITEM', style: headStyle)),
                  cell(
                    pw.Text('QTY', style: headStyle),
                    align: pw.Alignment.center,
                  ),
                  cell(
                    pw.Text('STOCK', style: headStyle),
                    align: pw.Alignment.center,
                  ),
                  cell(
                    pw.Text('REFUND', style: headStyle),
                    align: pw.Alignment.centerRight,
                  ),
                ],
              ),
              for (var n = 0; n < ret.items.length; n++)
                () {
                  final i = ret.items[n];
                  final details = [?i.type, ?i.size].join(' / ');
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: n.isOdd ? _zebra : PdfColors.white,
                    ),
                    verticalAlignment: pw.TableCellVerticalAlignment.middle,
                    children: [
                      cell(
                        pw.Text(
                          '${n + 1}',
                          style: const pw.TextStyle(fontSize: 9, color: _muted),
                        ),
                      ),
                      cell(
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              i.name,
                              style: pw.TextStyle(
                                fontSize: 10,
                                color: _ink,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            if (details.isNotEmpty)
                              pw.Text(
                                details,
                                style: const pw.TextStyle(
                                  fontSize: 8.5,
                                  color: _muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      cell(
                        pw.Text(
                          '${i.quantity}',
                          style: const pw.TextStyle(fontSize: 10, color: _ink),
                        ),
                        align: pw.Alignment.center,
                      ),
                      cell(
                        pw.Text(
                          i.restocked ? 'Restocked' : 'Written off',
                          style: const pw.TextStyle(
                            fontSize: 8.5,
                            color: _muted,
                          ),
                        ),
                        align: pw.Alignment.center,
                      ),
                      cell(
                        pw.Text(
                          _rs(i.refund),
                          style: pw.TextStyle(
                            fontSize: 10,
                            color: _ink,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        align: pw.Alignment.centerRight,
                      ),
                    ],
                  );
                }(),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _label('AMOUNT IN WORDS'),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      _amountInWords(ret.refundAmount),
                      style: const pw.TextStyle(fontSize: 9.5, color: _ink),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 24),
              pw.SizedBox(
                width: 230,
                child: _grandTotal(
                  ret.isExchange ? 'CREDIT' : 'TOTAL REFUND',
                  _rs(ret.refundAmount),
                  _red,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 48),
          pw.Row(
            children: [
              pw.Expanded(child: _signature('Customer signature')),
              pw.SizedBox(width: 40),
              pw.Expanded(child: _signature('Authorised by')),
            ],
          ),
          pw.SizedBox(height: 24),
          _closing(settings, ret.returnNumber, showThanks: false),
        ],
      ),
    );
    return pdf.save();
  }

  // ═══════════════════════════════════════════════════════════
  // DAY CLOSE (Z REPORT)
  // ═══════════════════════════════════════════════════════════

  static Future<Uint8List> buildZReportPdf(
    ZReport z,
    ShopSettings settings, {
    required double countedCash,
    required double floatKept,
    String? note,
    required DateTime closedAt,
  }) async {
    await _loadBrandMark();
    final pdf = pw.Document(title: 'Day close', author: settings.shopName);
    final f = DateFormat('dd MMM yyyy, hh:mm a');
    final diff = countedCash - z.expectedCash;
    final doc = 'Day close ${DateFormat('dd MMM yyyy').format(closedAt)}';

    pw.Widget section(String title, List<pw.Widget> rows) => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            color: _brandLight,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: _label(title),
          ),
          pw.SizedBox(height: 3),
          ...rows,
          pw.SizedBox(height: 3),
        ],
      ),
    );

    final methods = {
      ...z.salesByMethod.keys,
      ...z.refundsByMethod.keys,
    }.toList()..sort();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 28, 36, 28),
        footer: (ctx) => _footer(ctx, settings, doc),
        build: (ctx) => [
          _letterhead(
            settings,
            title: 'DAY CLOSE',
            meta: [
              ('From', f.format(z.from)),
              ('To', f.format(closedAt)),
              ('Bills', '${z.billCount}'),
              ('Items sold', '${z.itemsSold}'),
            ],
            stamp: diff.abs() < 0.5
                ? ('BALANCED', _green)
                : diff > 0
                ? ('EXCESS', const PdfColor.fromInt(0xFFB45309))
                : ('SHORT', _red),
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  children: [
                    section('SALES', [
                      _totalRow(
                        'Gross sales',
                        _rs(z.sales + z.offers + z.discounts),
                      ),
                      _totalRow('Offers', '- ${_rs(z.offers)}', color: _green),
                      _totalRow(
                        'Discounts',
                        '- ${_rs(z.discounts)}',
                        color: _green,
                      ),
                      _totalRow('Sales', _rs(z.sales)),
                      _totalRow(
                        'Refunds (${z.returnCount})',
                        '- ${_rs(z.refunds)}',
                        color: _red,
                      ),
                      _totalRow('Net sales', _rs(z.netSales)),
                    ]),
                    section('BY PAYMENT METHOD', [
                      for (final m in methods)
                        _totalRow(
                          m,
                          (z.refundsByMethod[m] ?? 0) > 0
                              ? '${_rs(z.salesByMethod[m] ?? 0)}  '
                                    '(-${_money.format(z.refundsByMethod[m])})'
                              : _rs(z.salesByMethod[m] ?? 0),
                        ),
                      if (methods.isEmpty) _totalRow('No sales', '-'),
                    ]),
                    section('UDHAAR', [
                      _totalRow('Given on credit', _rs(z.udhaarGiven)),
                      _totalRow('Collected', _rs(z.udhaarCollected)),
                      _totalRow('  of which cash', _rs(z.udhaarCollectedCash)),
                    ]),
                  ],
                ),
              ),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: pw.Column(
                  children: [
                    section('CASH DRAWER', [
                      _totalRow('Opening float', _rs(z.openingFloat)),
                      _totalRow('+ Cash sales', _rs(z.cashSales)),
                      _totalRow('- Cash refunds', _rs(z.cashRefunds)),
                      _totalRow(
                        '+ Udhaar collected (cash)',
                        _rs(z.udhaarCollectedCash),
                      ),
                      _totalRow(
                        '- Expenses from drawer',
                        _rs(z.drawerExpenses),
                      ),
                      _totalRow('Expected', _rs(z.expectedCash)),
                      _totalRow('Counted', _rs(countedCash)),
                      _totalRow(
                        diff.abs() < 0.5
                            ? 'Difference'
                            : diff > 0
                            ? 'Excess'
                            : 'Shortage',
                        _rs(diff.abs()),
                        color: diff.abs() < 0.5
                            ? _green
                            : diff > 0
                            ? const PdfColor.fromInt(0xFFB45309)
                            : _red,
                      ),
                      _totalRow('Kept as float', _rs(floatKept)),
                      _totalRow('Taken out', _rs(countedCash - floatKept)),
                    ]),
                    section('EXPENSES', [
                      for (final e in z.expensesByCategory.entries)
                        _totalRow(e.key, _rs(e.value)),
                      if (z.expensesByCategory.isEmpty) _totalRow('None', '-'),
                      _totalRow('Total', _rs(z.expenses)),
                    ]),
                    if (z.topItems.isNotEmpty)
                      section('TOP ITEMS', [
                        for (final (name, qty, amount) in z.topItems)
                          _totalRow('$qty x $name', _rs(amount)),
                      ]),
                  ],
                ),
              ),
            ],
          ),
          if (note != null && note.isNotEmpty) ...[
            _label('NOTE'),
            pw.SizedBox(height: 3),
            pw.Text(note, style: const pw.TextStyle(fontSize: 10, color: _ink)),
          ],
          pw.SizedBox(height: 40),
          pw.Row(
            children: [
              pw.Expanded(child: _signature('Closed by')),
              pw.SizedBox(width: 40),
              pw.Expanded(child: _signature('Checked by')),
            ],
          ),
        ],
      ),
    );
    return pdf.save();
  }

  // ═══════════════════════════════════════════════════════════
  // Shared pieces
  // ═══════════════════════════════════════════════════════════

  /// Shop details on the left, document title + meta table on the right.
  static pw.Widget _letterhead(
    ShopSettings s, {
    required String title,
    required List<(String, String)> meta,
    required (String, PdfColor) stamp,
    PdfColor titleColor = _brand,
  }) {
    final logo = s.logoBase64 != null
        ? pw.MemoryImage(base64Decode(s.logoBase64!))
        : _brandMark == null
        ? null
        : pw.MemoryImage(_brandMark!);
    final contact = [
      if (s.address.isNotEmpty) s.address,
      if (s.phone.isNotEmpty) 'Tel: ${s.phone}',
      if (s.email.isNotEmpty) s.email,
      if (s.taxNumber.isNotEmpty) s.taxNumber,
    ];

    return pw.Column(
      children: [
        pw.Container(height: 5, color: titleColor),
        pw.SizedBox(height: 16),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logo != null) ...[
              pw.Container(
                width: 64,
                height: 64,
                child: pw.Image(logo, fit: pw.BoxFit.contain),
              ),
              pw.SizedBox(width: 12),
            ],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    s.shopName,
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: _ink,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  for (final line in contact)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 1.5),
                      child: pw.Text(
                        line,
                        style: const pw.TextStyle(fontSize: 9, color: _muted),
                      ),
                    ),
                ],
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    color: titleColor,
                    letterSpacing: 2,
                  ),
                ),
                pw.SizedBox(height: 8),
                for (final (k, v) in meta)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 2),
                    child: pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.SizedBox(
                          width: 90,
                          child: pw.Text(
                            k,
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(
                              fontSize: 9,
                              color: _muted,
                            ),
                          ),
                        ),
                        pw.SizedBox(width: 10),
                        pw.SizedBox(
                          width: 105,
                          child: pw.Text(
                            v,
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                              fontSize: 9,
                              color: _ink,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                pw.SizedBox(height: 6),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: stamp.$2, width: 1.5),
                    borderRadius: pw.BorderRadius.circular(3),
                  ),
                  child: pw.Text(
                    stamp.$1,
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: stamp.$2,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _continuationHeader(ShopSettings s, String doc) =>
      pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        padding: const pw.EdgeInsets.only(bottom: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _line)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              s.shopName,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: _ink,
              ),
            ),
            pw.Text(
              '$doc (continued)',
              style: const pw.TextStyle(fontSize: 9, color: _muted),
            ),
          ],
        ),
      );

  static pw.Widget _footer(pw.Context ctx, ShopSettings s, String doc) =>
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 12),
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _line)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'This is a computer-generated document.',
              style: const pw.TextStyle(fontSize: 7.5, color: _muted),
            ),
            pw.Text(
              '$doc  |  Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 7.5, color: _muted),
            ),
          ],
        ),
      );

  static pw.Widget _label(String text) => pw.Text(
    text,
    style: pw.TextStyle(
      fontSize: 8,
      color: _muted,
      fontWeight: pw.FontWeight.bold,
      letterSpacing: 0.8,
    ),
  );

  static pw.Widget _infoBlock(String title, List<String> lines) => pw.Container(
    // Same height side by side even when one has fewer lines.
    constraints: const pw.BoxConstraints(minHeight: 62),
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: _brandLight,
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _label(title),
        pw.SizedBox(height: 4),
        for (final l in lines)
          pw.Text(l, style: const pw.TextStyle(fontSize: 10, color: _ink)),
      ],
    ),
  );

  static pw.Widget _totalRow(String label, String value, {PdfColor? color}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 8),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(fontSize: 10, color: color ?? _muted),
            ),
            pw.Text(
              value,
              style: pw.TextStyle(fontSize: 10, color: color ?? _ink),
            ),
          ],
        ),
      );

  static pw.Widget _grandTotal(String label, String value, PdfColor color) =>
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        color: color,
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 11,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 13,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      );

  static pw.Widget _signature(String label) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(height: 0.8, color: _muted),
      pw.SizedBox(height: 4),
      pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: _muted)),
    ],
  );

  /// Terms, thank-you note and a scannable barcode of the document number.
  static pw.Widget _closing(
    ShopSettings s,
    String number, {
    bool showThanks = true,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (s.terms.isNotEmpty) ...[
                _label('TERMS & CONDITIONS'),
                pw.SizedBox(height: 3),
                pw.Text(
                  s.terms,
                  style: const pw.TextStyle(fontSize: 8.5, color: _muted),
                ),
                pw.SizedBox(height: 12),
              ],
              if (showThanks)
                pw.Text(
                  s.footerMessage,
                  style: pw.TextStyle(
                    fontSize: 12,
                    color: _brand,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
        pw.SizedBox(width: 24),
        pw.BarcodeWidget(
          barcode: pw.Barcode.code128(),
          data: number,
          width: 150,
          height: 42,
          textStyle: const pw.TextStyle(fontSize: 8, color: _ink),
        ),
      ],
    );
  }

  // ── Amount in words (e.g. "Rupees Two Thousand Two Hundred Only") ──

  static const _ones = [
    '',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
    'Twelve',
    'Thirteen',
    'Fourteen',
    'Fifteen',
    'Sixteen',
    'Seventeen',
    'Eighteen',
    'Nineteen',
  ];
  static const _tens = [
    '',
    '',
    'Twenty',
    'Thirty',
    'Forty',
    'Fifty',
    'Sixty',
    'Seventy',
    'Eighty',
    'Ninety',
  ];

  static String _below1000(int n) {
    final parts = <String>[];
    if (n >= 100) {
      parts.add('${_ones[n ~/ 100]} Hundred');
      n %= 100;
    }
    if (n >= 20) {
      parts.add(_tens[n ~/ 10] + (n % 10 > 0 ? '-${_ones[n % 10]}' : ''));
    } else if (n > 0) {
      parts.add(_ones[n]);
    }
    return parts.join(' ');
  }

  static String _words(int n) {
    if (n == 0) return 'Zero';
    const scales = [
      (1000000000, 'Billion'),
      (1000000, 'Million'),
      (1000, 'Thousand'),
    ];
    final parts = <String>[];
    for (final (size, name) in scales) {
      if (n >= size) {
        parts.add('${_below1000(n ~/ size)} $name');
        n %= size;
      }
    }
    if (n > 0) parts.add(_below1000(n));
    return parts.join(' ');
  }

  /// Visible for tests.
  static String amountInWords(double amount) => _amountInWords(amount);

  static String _amountInWords(double amount) {
    final paisa = (amount * 100).round();
    final rupees = paisa ~/ 100;
    final rest = paisa % 100;
    return 'Rupees ${_words(rupees)}'
        '${rest > 0 ? ' and ${_words(rest)} Paisa' : ''} Only';
  }
}
