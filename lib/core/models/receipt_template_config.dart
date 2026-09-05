class ReceiptTemplateConfig {
  const ReceiptTemplateConfig({
    required this.paperSize,
    required this.printerName,
    required this.copies,
    required this.salonName,
    required this.address,
    required this.phone,
    required this.tagline,
    required this.logoPath,
    required this.showLogo,
    required this.showInvoiceId,
    required this.showDateTime,
    required this.showCustomerName,
    required this.showCustomerPhone,
    required this.showPaymentMethod,
    required this.showQuantity,
    required this.showUnitPrice,
    required this.showDiscount,
    required this.fontSize,
    required this.layoutStyle,
    required this.footerMessage,
    required this.footerNote,
    required this.showQr,
  });

  static const paper58 = '58mm';
  static const paper80 = '80mm';
  static const paperA4 = 'A4';
  static const paperSizes = [paper58, paper80, paperA4];

  static const fontSmall = 'small';
  static const fontMedium = 'medium';
  static const fontLarge = 'large';
  static const fontSizes = [fontSmall, fontMedium, fontLarge];

  static const layoutCompact = 'compact';
  static const layoutStandard = 'standard';
  static const layoutStyles = [layoutCompact, layoutStandard];

  final String paperSize;
  final String printerName;
  final int copies;
  final String salonName;
  final String address;
  final String phone;
  final String tagline;
  final String logoPath;
  final bool showLogo;
  final bool showInvoiceId;
  final bool showDateTime;
  final bool showCustomerName;
  final bool showCustomerPhone;
  final bool showPaymentMethod;
  final bool showQuantity;
  final bool showUnitPrice;
  final bool showDiscount;
  final String fontSize;
  final String layoutStyle;
  final String footerMessage;
  final String footerNote;
  final bool showQr;

  factory ReceiptTemplateConfig.defaults({String salonName = 'Hair Spa Manager'}) {
    return ReceiptTemplateConfig(
      paperSize: paper80,
      printerName: '',
      copies: 1,
      salonName: salonName.trim().isEmpty ? 'Hair Spa Manager' : salonName.trim(),
      address: '',
      phone: '',
      tagline: 'Hair • Spa • Beauty',
      logoPath: '',
      showLogo: false,
      showInvoiceId: true,
      showDateTime: true,
      showCustomerName: true,
      showCustomerPhone: true,
      showPaymentMethod: true,
      showQuantity: true,
      showUnitPrice: true,
      showDiscount: true,
      fontSize: fontMedium,
      layoutStyle: layoutStandard,
      footerMessage: 'Cảm ơn quý khách. Hẹn gặp lại!',
      footerNote: '',
      showQr: false,
    );
  }

  factory ReceiptTemplateConfig.fromJson(
    Map<String, Object?> json, {
    String fallbackSalonName = 'Hair Spa Manager',
  }) {
    final defaults = ReceiptTemplateConfig.defaults(salonName: fallbackSalonName);
    final paper = json['paperSize']?.toString() ?? defaults.paperSize;
    final font = json['fontSize']?.toString() ?? defaults.fontSize;
    final layout = json['layoutStyle']?.toString() ?? defaults.layoutStyle;
    final copiesValue = int.tryParse(json['copies']?.toString() ?? '') ?? defaults.copies;

    bool readBool(String key, bool fallback) {
      final value = json[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      final normalized = value?.toString().trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
      return fallback;
    }

    return ReceiptTemplateConfig(
      paperSize: paperSizes.contains(paper) ? paper : defaults.paperSize,
      printerName: json['printerName']?.toString() ?? defaults.printerName,
      copies: copiesValue.clamp(1, 3).toInt(),
      salonName: (json['salonName']?.toString().trim().isNotEmpty ?? false)
          ? json['salonName']!.toString().trim()
          : defaults.salonName,
      address: json['address']?.toString() ?? defaults.address,
      phone: json['phone']?.toString() ?? defaults.phone,
      tagline: json['tagline']?.toString() ?? defaults.tagline,
      logoPath: json['logoPath']?.toString() ?? defaults.logoPath,
      showLogo: readBool('showLogo', defaults.showLogo),
      showInvoiceId: readBool('showInvoiceId', defaults.showInvoiceId),
      showDateTime: readBool('showDateTime', defaults.showDateTime),
      showCustomerName: readBool('showCustomerName', defaults.showCustomerName),
      showCustomerPhone: readBool('showCustomerPhone', defaults.showCustomerPhone),
      showPaymentMethod: readBool('showPaymentMethod', defaults.showPaymentMethod),
      showQuantity: readBool('showQuantity', defaults.showQuantity),
      showUnitPrice: readBool('showUnitPrice', defaults.showUnitPrice),
      showDiscount: readBool('showDiscount', defaults.showDiscount),
      fontSize: fontSizes.contains(font) ? font : defaults.fontSize,
      layoutStyle: layoutStyles.contains(layout) ? layout : defaults.layoutStyle,
      footerMessage: json['footerMessage']?.toString() ?? defaults.footerMessage,
      footerNote: json['footerNote']?.toString() ?? defaults.footerNote,
      showQr: readBool('showQr', defaults.showQr),
    );
  }

  Map<String, Object?> toJson() => {
    'paperSize': paperSize,
    'printerName': printerName,
    'copies': copies,
    'salonName': salonName,
    'address': address,
    'phone': phone,
    'tagline': tagline,
    'logoPath': logoPath,
    'showLogo': showLogo,
    'showInvoiceId': showInvoiceId,
    'showDateTime': showDateTime,
    'showCustomerName': showCustomerName,
    'showCustomerPhone': showCustomerPhone,
    'showPaymentMethod': showPaymentMethod,
    'showQuantity': showQuantity,
    'showUnitPrice': showUnitPrice,
    'showDiscount': showDiscount,
    'fontSize': fontSize,
    'layoutStyle': layoutStyle,
    'footerMessage': footerMessage,
    'footerNote': footerNote,
    'showQr': showQr,
  };

  ReceiptTemplateConfig copyWith({
    String? paperSize,
    String? printerName,
    int? copies,
    String? salonName,
    String? address,
    String? phone,
    String? tagline,
    String? logoPath,
    bool? showLogo,
    bool? showInvoiceId,
    bool? showDateTime,
    bool? showCustomerName,
    bool? showCustomerPhone,
    bool? showPaymentMethod,
    bool? showQuantity,
    bool? showUnitPrice,
    bool? showDiscount,
    String? fontSize,
    String? layoutStyle,
    String? footerMessage,
    String? footerNote,
    bool? showQr,
  }) {
    return ReceiptTemplateConfig(
      paperSize: paperSize ?? this.paperSize,
      printerName: printerName ?? this.printerName,
      copies: (copies ?? this.copies).clamp(1, 3).toInt(),
      salonName: salonName ?? this.salonName,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      tagline: tagline ?? this.tagline,
      logoPath: logoPath ?? this.logoPath,
      showLogo: showLogo ?? this.showLogo,
      showInvoiceId: showInvoiceId ?? this.showInvoiceId,
      showDateTime: showDateTime ?? this.showDateTime,
      showCustomerName: showCustomerName ?? this.showCustomerName,
      showCustomerPhone: showCustomerPhone ?? this.showCustomerPhone,
      showPaymentMethod: showPaymentMethod ?? this.showPaymentMethod,
      showQuantity: showQuantity ?? this.showQuantity,
      showUnitPrice: showUnitPrice ?? this.showUnitPrice,
      showDiscount: showDiscount ?? this.showDiscount,
      fontSize: fontSize ?? this.fontSize,
      layoutStyle: layoutStyle ?? this.layoutStyle,
      footerMessage: footerMessage ?? this.footerMessage,
      footerNote: footerNote ?? this.footerNote,
      showQr: showQr ?? this.showQr,
    );
  }

  String get paperLabel => paperSize;

  String get fontSizeLabel {
    switch (fontSize) {
      case fontSmall:
        return 'Nhỏ';
      case fontLarge:
        return 'Lớn';
      default:
        return 'Vừa';
    }
  }

  String get layoutStyleLabel =>
      layoutStyle == layoutCompact ? 'Gọn' : 'Tiêu chuẩn';
}
