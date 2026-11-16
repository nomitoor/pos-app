import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_helper.dart';
import '../../../models/shop_settings.dart';

final shopSettingsProvider =
    AsyncNotifierProvider<ShopSettingsNotifier, ShopSettings>(
      ShopSettingsNotifier.new,
    );

class ShopSettingsNotifier extends AsyncNotifier<ShopSettings> {
  @override
  Future<ShopSettings> build() async {
    final map = await DatabaseHelper.instance.getSettings();
    const defaults = ShopSettings();
    return ShopSettings(
      shopName: map['shopName'] ?? defaults.shopName,
      address: map['address'] ?? defaults.address,
      phone: map['phone'] ?? defaults.phone,
      email: map['email'] ?? defaults.email,
      taxNumber: map['taxNumber'] ?? defaults.taxNumber,
      terms: map['terms'] ?? defaults.terms,
      footerMessage: map['footerMessage'] ?? defaults.footerMessage,
      logoBase64: (map['logoBase64'] == null || map['logoBase64']!.isEmpty)
          ? null
          : map['logoBase64'],
    );
  }

  Future<void> save(ShopSettings settings) async {
    await DatabaseHelper.instance.saveSettings({
      'shopName': settings.shopName,
      'address': settings.address,
      'phone': settings.phone,
      'email': settings.email,
      'taxNumber': settings.taxNumber,
      'terms': settings.terms,
      'footerMessage': settings.footerMessage,
      'logoBase64': settings.logoBase64 ?? '',
    });
    state = AsyncData(settings);
  }
}
