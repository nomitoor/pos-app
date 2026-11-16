import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import '../../models/bill.dart';
import '../../models/shop_settings.dart';
import 'printer_settings.dart';

final _money = NumberFormat('#,##0', 'en_US');
String _rs(double v) => 'Rs ${_money.format(v)}';

/// Builds ESC/POS bytes for receipts on a thermal roll printer.
class ThermalReceipt {
  static Future<Generator> _generator(PaperWidth paper) async {
    final profile = await CapabilityProfile.load();
    return Generator(
      paper == PaperWidth.mm80 ? PaperSize.mm80 : PaperSize.mm58,
      profile,
    );
  }

  /// Receipt printers only know basic Latin characters; anything else
  /// (e.g. Urdu product names) would garble the line, so swap it for '?'.
  static String _safe(String s) =>
      s.replaceAll(RegExp(r'[^\x20-\x7E]'), '?').trim();

  /// Left text and right-aligned amount on one line, e.g. "Total   Rs 2,500".
  static List<int> _pair(
    Generator g,
    PaperWidth p,
    String left,
    String right, {
    PosStyles style = const PosStyles(),
  }) {
    final r = _safe(right);
    final l = _safe(left);
    final room = p.chars - r.length - 1;
    final lText = l.length > room ? l.substring(0, room) : l;
    return g.text('${lText.padRight(room)} $r', styles: style);
  }

  static Future<List<int>> bill(
    Bill bill,
    ShopSettings shop,
    PaperWidth paper, {
    double? unpaid,
  }) async {
    final g = await _generator(paper);
    final b = <int>[];
    const center = PosStyles(align: PosAlign.center);

    b.addAll(g.reset());

    // ── Shop header ──
    b.addAll(
      g.text(
        _safe(shop.shopName),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
    );
    for (final line in [shop.address, shop.phone, shop.taxNumber]) {
      if (line.trim().isNotEmpty) b.addAll(g.text(_safe(line), styles: center));
    }
    b.addAll(g.hr());

    // ── Bill details ──
    b.addAll(_pair(g, paper, 'Invoice', bill.billNumber));
    b.addAll(
      _pair(
        g,
        paper,
        'Date',
        DateFormat('dd MMM yyyy, hh:mm a').format(bill.createdAt),
      ),
    );
    if (bill.customerName != null) {
      b.addAll(_pair(g, paper, 'Customer', bill.customerName!));
    }
    b.addAll(g.hr());

    // ── Items: name on one line, "qty x price ... subtotal" under it ──
    for (final i in bill.items) {
      final name = i.size == null ? i.name : '${i.name} (${i.size})';
      b.addAll(g.text(_safe(name), styles: const PosStyles(bold: true)));
      b.addAll(
        _pair(
          g,
          paper,
          '  ${i.quantity} x ${_money.format(i.price)}',
          _money.format(i.subtotal),
        ),
      );
      if (i.promoSavings > 0.5) {
        b.addAll(g.text(_safe('  Offer saved ${_rs(i.promoSavings)}')));
      }
    }
    b.addAll(g.hr());

    // ── Totals ──
    final pieces = bill.items.fold<int>(0, (s, i) => s + i.quantity);
    b.addAll(_pair(g, paper, 'Items', '$pieces'));
    if (bill.discount > 0.5) {
      b.addAll(_pair(g, paper, 'Subtotal', _rs(bill.subtotal)));
      b.addAll(_pair(g, paper, 'Discount', '-${_rs(bill.discount)}'));
    }
    b.addAll(
      _pair(
        g,
        paper,
        'TOTAL',
        _rs(bill.totalAmount),
        style: const PosStyles(bold: true, height: PosTextSize.size2),
      ),
    );
    final saved = bill.promoSavings + bill.discount;
    if (saved > 0.5) b.addAll(_pair(g, paper, 'You saved', _rs(saved)));
    if (bill.paymentMethod != null) {
      b.addAll(_pair(g, paper, 'Payment', bill.paymentMethod!));
    }
    if (bill.isUdhaar && unpaid != null && unpaid > 0.5) {
      b.addAll(
        _pair(
          g,
          paper,
          'Balance due',
          _rs(unpaid),
          style: const PosStyles(bold: true),
        ),
      );
    }
    b.addAll(g.hr());

    // ── Footer ──
    if (shop.terms.trim().isNotEmpty) {
      b.addAll(g.text(_safe(shop.terms), styles: center));
    }
    if (shop.footerMessage.trim().isNotEmpty) {
      b.addAll(
        g.text(
          _safe(shop.footerMessage),
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ),
      );
    }
    b.addAll(g.feed(3));
    b.addAll(g.cut());
    return b;
  }

  /// Short slip to check the printer and paper width are right.
  static Future<List<int>> test(PaperWidth paper, String shopName) async {
    final g = await _generator(paper);
    return [
      ...g.reset(),
      ...g.text(
        _safe(shopName),
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
      ...g.text(
        'Printer test (${paper.label})',
        styles: const PosStyles(align: PosAlign.center),
      ),
      ...g.hr(),
      // 48 digits fit on one line only on 80 mm paper; on 58 mm they wrap.
      ...g.text(List.generate(48, (i) => '${(i + 1) % 10}').join()),
      ...g.hr(),
      ...g.text('Digits on ONE line: choose 80 mm.'),
      ...g.text('Digits wrap to 2 lines: choose 58 mm.'),
      ...g.feed(3),
      ...g.cut(),
    ];
  }
}
