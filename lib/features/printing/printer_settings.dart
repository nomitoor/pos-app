import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/database_helper.dart';

/// Thermal receipt roll width.
enum PaperWidth {
  mm58('58 mm'),
  mm80('80 mm');

  final String label;
  const PaperWidth(this.label);

  /// Characters per line in the printer's normal font.
  int get chars => this == mm58 ? 32 : 48;
}

/// The Bluetooth receipt printer this phone prints to.
class PrinterSettings {
  /// Bluetooth MAC address; null until a printer is chosen.
  final String? address;
  final String? name;
  final PaperWidth paper;

  const PrinterSettings({
    this.address,
    this.name,
    this.paper = PaperWidth.mm58,
  });

  bool get isSet => address != null && address!.isNotEmpty;

  PrinterSettings copyWith({
    String? address,
    String? name,
    PaperWidth? paper,
  }) => PrinterSettings(
    address: address ?? this.address,
    name: name ?? this.name,
    paper: paper ?? this.paper,
  );
}

final printerSettingsProvider =
    AsyncNotifierProvider<PrinterSettingsNotifier, PrinterSettings>(
      PrinterSettingsNotifier.new,
    );

/// Stored as rows in the key/value `settings` table, next to shop details.
class PrinterSettingsNotifier extends AsyncNotifier<PrinterSettings> {
  static const _kAddress = 'printerAddress';
  static const _kName = 'printerName';
  static const _kPaper = 'printerPaper';

  @override
  Future<PrinterSettings> build() async {
    final m = await DatabaseHelper.instance.getSettings();
    final address = m[_kAddress];
    return PrinterSettings(
      address: (address == null || address.isEmpty) ? null : address,
      name: m[_kName],
      // 58 mm by default: it also prints correctly (just narrower) on 80 mm.
      paper: m[_kPaper] == '80' ? PaperWidth.mm80 : PaperWidth.mm58,
    );
  }

  Future<void> save(PrinterSettings s) async {
    await DatabaseHelper.instance.saveSettings({
      _kAddress: s.address ?? '',
      _kName: s.name ?? '',
      _kPaper: s.paper == PaperWidth.mm80 ? '80' : '58',
    });
    state = AsyncData(s);
  }
}
