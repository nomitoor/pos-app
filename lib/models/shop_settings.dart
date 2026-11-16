class ShopSettings {
  final String shopName;
  final String address;
  final String phone;
  final String email;

  /// Tax registration shown on invoices (e.g. "NTN 1234567-8"); optional.
  final String taxNumber;

  /// Terms printed at the bottom of invoices (e.g. exchange policy).
  final String terms;
  final String footerMessage;
  // Logo image bytes, base64-encoded for storage; null means no logo.
  final String? logoBase64;

  const ShopSettings({
    this.shopName = 'Urban Thread',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.taxNumber = '',
    this.terms = '',
    this.footerMessage = 'Thank you for your purchase!',
    this.logoBase64,
  });

  ShopSettings copyWith({
    String? shopName,
    String? address,
    String? phone,
    String? email,
    String? taxNumber,
    String? terms,
    String? footerMessage,
    String? logoBase64,
  }) {
    return ShopSettings(
      shopName: shopName ?? this.shopName,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      taxNumber: taxNumber ?? this.taxNumber,
      terms: terms ?? this.terms,
      footerMessage: footerMessage ?? this.footerMessage,
      logoBase64: logoBase64 ?? this.logoBase64,
    );
  }
}
