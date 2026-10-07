class InvoicePackageRedemptionIntent {
  const InvoicePackageRedemptionIntent({
    required this.lineId,
    required this.packageId,
    required this.quantity,
  });

  final String lineId;
  final String packageId;
  final int quantity;

  Map<String, Object> toJson() => {
    'lineId': lineId,
    'packageId': packageId,
    'quantity': quantity,
  };

  factory InvoicePackageRedemptionIntent.fromJson(Map<String, dynamic> json) {
    return InvoicePackageRedemptionIntent(
      lineId: json['lineId']?.toString() ?? '',
      packageId: json['packageId']?.toString() ?? '',
      quantity: _asInt(json['quantity']),
    );
  }
}

class InvoiceBenefitPurchaseIntent {
  const InvoiceBenefitPurchaseIntent({
    required this.lineId,
    required this.kind,
    required this.planId,
  });

  static const membership = 'membership';
  static const servicePackage = 'service_package';

  final String lineId;
  final String kind;
  final String planId;

  Map<String, Object> toJson() => {
    'lineId': lineId,
    'kind': kind,
    'planId': planId,
  };

  factory InvoiceBenefitPurchaseIntent.fromJson(Map<String, dynamic> json) {
    return InvoiceBenefitPurchaseIntent(
      lineId: json['lineId']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      planId: json['planId']?.toString() ?? '',
    );
  }
}

class InvoiceBenefitIntent {
  const InvoiceBenefitIntent({
    this.voucherId,
    this.membershipId,
    this.packageRedemptions = const [],
    this.purchases = const [],
  });

  final String? voucherId;
  final String? membershipId;
  final List<InvoicePackageRedemptionIntent> packageRedemptions;
  final List<InvoiceBenefitPurchaseIntent> purchases;

  bool get isEmpty =>
      voucherId == null &&
      membershipId == null &&
      packageRedemptions.isEmpty &&
      purchases.isEmpty;

  InvoiceBenefitIntent copyWith({
    String? voucherId,
    String? membershipId,
    bool clearVoucher = false,
    bool clearMembership = false,
    List<InvoicePackageRedemptionIntent>? packageRedemptions,
    List<InvoiceBenefitPurchaseIntent>? purchases,
  }) {
    return InvoiceBenefitIntent(
      voucherId: clearVoucher ? null : voucherId ?? this.voucherId,
      membershipId: clearMembership
          ? null
          : membershipId ?? this.membershipId,
      packageRedemptions:
          packageRedemptions ?? this.packageRedemptions,
      purchases: purchases ?? this.purchases,
    );
  }

  Map<String, Object?> toJson() => {
    'voucherId': voucherId,
    'membershipId': membershipId,
    'packageRedemptions': [
      for (final item in packageRedemptions) item.toJson(),
    ],
    'purchases': [for (final item in purchases) item.toJson()],
  };

  factory InvoiceBenefitIntent.fromJson(Map<String, dynamic> json) {
    final packageRows = json['packageRedemptions'];
    final purchaseRows = json['purchases'];
    return InvoiceBenefitIntent(
      voucherId: _nullableText(json['voucherId']),
      membershipId: _nullableText(json['membershipId']),
      packageRedemptions: packageRows is List
          ? packageRows
                .whereType<Map>()
                .map(
                  (row) => InvoicePackageRedemptionIntent.fromJson(
                    Map<String, dynamic>.from(row),
                  ),
                )
                .toList(growable: false)
          : const [],
      purchases: purchaseRows is List
          ? purchaseRows
                .whereType<Map>()
                .map(
                  (row) => InvoiceBenefitPurchaseIntent.fromJson(
                    Map<String, dynamic>.from(row),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

class InvoiceBenefitLinePreview {
  const InvoiceBenefitLinePreview({
    required this.lineId,
    required this.itemType,
    required this.cashBasis,
    required this.automatedDiscountAmount,
    required this.prepaidCoveredAmount,
    required this.manualLineDiscountAmount,
    required this.manualBillDiscountAmount,
    required this.recognizedValue,
  });

  final String lineId;
  final String itemType;
  final int cashBasis;
  final int automatedDiscountAmount;
  final int prepaidCoveredAmount;
  final int manualLineDiscountAmount;
  final int manualBillDiscountAmount;
  final int recognizedValue;
}

class InvoicePackageApplicationPreview {
  const InvoicePackageApplicationPreview({
    required this.lineId,
    required this.packageId,
    required this.serviceId,
    required this.quantity,
    required this.coveredSaleValue,
    required this.recognizedValue,
  });

  final String lineId;
  final String packageId;
  final String serviceId;
  final int quantity;
  final int coveredSaleValue;
  final int recognizedValue;
}

class InvoiceBenefitPreview {
  const InvoiceBenefitPreview({
    required this.intent,
    required this.serviceEligibleAmount,
    required this.productEligibleAmount,
    required this.prepaidCoveredAmount,
    required this.automatedDiscountAmount,
    required this.manualLineDiscountAmount,
    required this.manualBillDiscountAmount,
    required this.cashDue,
    required this.lines,
    required this.packageApplications,
    this.promoKind,
    this.promoSourceId,
  });

  final InvoiceBenefitIntent intent;
  final int serviceEligibleAmount;
  final int productEligibleAmount;
  final int prepaidCoveredAmount;
  final int automatedDiscountAmount;
  final int manualLineDiscountAmount;
  final int manualBillDiscountAmount;
  final int cashDue;
  final List<InvoiceBenefitLinePreview> lines;
  final List<InvoicePackageApplicationPreview> packageApplications;
  final String? promoKind;
  final String? promoSourceId;
}

String? _nullableText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
