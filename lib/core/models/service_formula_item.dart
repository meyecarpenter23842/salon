class ServiceFormulaItem {
  const ServiceFormulaItem({
    required this.id,
    required this.serviceId,
    required this.serviceName,
    required this.formulaText,
    required this.isHiddenFromStaff,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String serviceId;
  final String serviceName;
  final String formulaText;
  final bool isHiddenFromStaff;
  final DateTime createdAt;
  final DateTime updatedAt;

  ServiceFormulaItem copyWith({
    String? id,
    String? serviceId,
    String? serviceName,
    String? formulaText,
    bool? isHiddenFromStaff,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ServiceFormulaItem(
      id: id ?? this.id,
      serviceId: serviceId ?? this.serviceId,
      serviceName: serviceName ?? this.serviceName,
      formulaText: formulaText ?? this.formulaText,
      isHiddenFromStaff: isHiddenFromStaff ?? this.isHiddenFromStaff,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
