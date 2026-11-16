import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';
import '../../../models/sale_return.dart';
import '../../../models/shop_settings.dart';
import '../../../shared/services/pdf_service.dart';

class RefundSlipScreen extends StatelessWidget {
  final SaleReturn ret;
  final ShopSettings settings;

  const RefundSlipScreen({
    super.key,
    required this.ret,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Refund slip: ${ret.returnNumber}')),
      body: PdfPreview(
        build: (format) => PdfService.buildReturnPdf(ret, settings),
        pdfFileName: '${ret.returnNumber}.pdf',
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
      ),
    );
  }
}
