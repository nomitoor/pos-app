import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/bill.dart';
import '../../models/customer.dart';
import '../../models/shop_settings.dart';

final _money = NumberFormat('#,##0', 'en_US');
String _rs(double v) => 'Rs ${_money.format(v)}';

enum PdfShareResult { sent, notInstalled, failed }

class WhatsAppService {
  static const _channel = MethodChannel('urbanthread/whatsapp');

  /// WhatsApp file sharing goes through the Android app (MainActivity).
  static bool get canSendPdf =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Opens WhatsApp with the bill PDF attached. With a [phone] it goes
  /// straight to that chat; without one WhatsApp asks which chat.
  static Future<PdfShareResult> sendPdf({
    required Uint8List bytes,
    required String fileName,
    String? phone,
    String caption = '',
  }) async {
    try {
      final r = await _channel.invokeMethod<String>('sharePdf', {
        'bytes': bytes,
        'fileName': fileName,
        'phone': (phone == null || phone.isEmpty)
            ? null
            : Customer.whatsappNumber(phone),
        'caption': caption,
      });
      return r == 'not_installed'
          ? PdfShareResult.notInstalled
          : PdfShareResult.sent;
    } on PlatformException {
      return PdfShareResult.failed;
    }
  }

  /// One-line message sent with the PDF.
  static String pdfCaption(Bill bill, ShopSettings s) =>
      '${s.shopName}: invoice ${bill.billNumber}, total ${_rs(bill.totalAmount)}. '
              '${s.footerMessage}'
          .trim();

  /// Opens WhatsApp chat with [phone] and [message] typed in, ready to send.
  /// Returns false if WhatsApp (or a browser) couldn't be opened.
  static Future<bool> open(String phone, String message) {
    final uri = Uri.parse(
      'https://wa.me/${Customer.whatsappNumber(phone)}'
      '?text=${Uri.encodeComponent(message)}',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Short text receipt for a bill.
  static String receiptText(Bill bill, ShopSettings s, {double? unpaid}) {
    final b = StringBuffer()
      ..writeln('*${s.shopName}*')
      ..writeln('Invoice ${bill.billNumber}')
      ..writeln(DateFormat('dd MMM yyyy, hh:mm a').format(bill.createdAt))
      ..writeln();
    for (final i in bill.items) {
      final details = [?i.size].join();
      b.writeln(
        '${i.quantity} x ${i.name}${details.isEmpty ? '' : ' ($details)'}'
        '  ${_rs(i.subtotal)}',
      );
    }
    b.writeln();
    final saved = bill.promoSavings + bill.discount;
    if (saved > 0.5) b.writeln('You saved: ${_rs(saved)}');
    b.writeln('*Total: ${_rs(bill.totalAmount)}*');
    if (bill.isUdhaar) {
      b.writeln('Payment: Udhaar (credit)');
      if (unpaid != null) b.writeln('Balance due on this bill: ${_rs(unpaid)}');
    } else if (bill.paymentMethod != null) {
      b.writeln('Paid by: ${bill.paymentMethod}');
    }
    b
      ..writeln()
      ..writeln(s.footerMessage);
    if (s.phone.isNotEmpty) b.writeln(s.phone);
    return b.toString().trim();
  }

  /// Polite udhaar reminder.
  static String reminderText(String name, double balance, ShopSettings s) =>
      'Assalam-o-Alaikum $name,\n\n'
      'This is a reminder from *${s.shopName}* that your outstanding '
      'balance is *${_rs(balance)}*.\n\n'
      'Please visit us or send the payment at your convenience. '
      'Thank you!${s.phone.isEmpty ? '' : '\n${s.phone}'}';
}
