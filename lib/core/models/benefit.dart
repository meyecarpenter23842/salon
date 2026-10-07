class BenefitVoucherInput {
  const BenefitVoucherInput({
    required this.code,
    required this.discountType,
    required this.discountValue,
    required this.validFrom,
    required this.validTo,
    this.maxDiscountAmount,
    this.minSpendAmount = 0,
    this.customerId,
  });

  final String code;
  final String discountType;
  final int discountValue;
  final int? maxDiscountAmount;
  final int minSpendAmount;
  final String? customerId;
  final DateTime validFrom;
  final DateTime validTo;
}

class BenefitVoucher {
  const BenefitVoucher({
    required this.id,
    required this.code,
    required this.discountType,
    required this.discountValue,
    required this.minSpendAmount,
    required this.validFrom,
    required this.validTo,
    required this.status,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.maxDiscountAmount,
    this.customerId,
  });

  final String id;
  final String code;
  final String discountType;
  final int discountValue;
  final int? maxDiscountAmount;
  final int minSpendAmount;
  final String? customerId;
  final DateTime validFrom;
  final DateTime validTo;
  final String status;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class VoucherRedemption {
  const VoucherRedemption({
    required this.id,
    required this.kind,
    required this.voucherId,
    required this.invoiceId,
    required this.customerId,
    required this.discountAmount,
    required this.createdAt,
    this.originalRedemptionId,
  });

  final String id;
  final String kind;
  final String? originalRedemptionId;
  final String voucherId;
  final String invoiceId;
  final String customerId;
  final int discountAmount;
  final DateTime createdAt;
}

class MembershipPlanInput {
  const MembershipPlanInput({
    required this.name,
    required this.salePrice,
    required this.durationDays,
    required this.serviceDiscountBps,
    required this.productDiscountBps,
  });

  final String name;
  final int salePrice;
  final int durationDays;
  final int serviceDiscountBps;
  final int productDiscountBps;
}

class MembershipPlan {
  const MembershipPlan({
    required this.id,
    required this.name,
    required this.salePrice,
    required this.durationDays,
    required this.serviceDiscountBps,
    required this.productDiscountBps,
    required this.isActive,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final int salePrice;
  final int durationDays;
  final int serviceDiscountBps;
  final int productDiscountBps;
  final bool isActive;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class CustomerMembership {
  const CustomerMembership({
    required this.id,
    required this.customerId,
    required this.planId,
    required this.planName,
    required this.salePrice,
    required this.durationDays,
    required this.serviceDiscountBps,
    required this.productDiscountBps,
    required this.startsAt,
    required this.expiresAt,
    required this.sourceType,
    required this.actor,
    required this.createdAt,
    required this.cancelled,
    this.previousMembershipId,
    this.sourceId,
  });

  final String id;
  final String customerId;
  final String planId;
  final String? previousMembershipId;
  final String planName;
  final int salePrice;
  final int durationDays;
  final int serviceDiscountBps;
  final int productDiscountBps;
  final DateTime startsAt;
  final DateTime expiresAt;
  final String sourceType;
  final String? sourceId;
  final String actor;
  final DateTime createdAt;
  final bool cancelled;
}

class MembershipUsage {
  const MembershipUsage({
    required this.id,
    required this.kind,
    required this.membershipId,
    required this.invoiceId,
    required this.customerId,
    required this.serviceDiscountAmount,
    required this.productDiscountAmount,
    required this.createdAt,
    this.originalUsageId,
  });

  final String id;
  final String kind;
  final String? originalUsageId;
  final String membershipId;
  final String invoiceId;
  final String customerId;
  final int serviceDiscountAmount;
  final int productDiscountAmount;
  final DateTime createdAt;
}

class ServicePackageComponentInput {
  const ServicePackageComponentInput({
    required this.serviceId,
    required this.quantity,
  });

  final String serviceId;
  final int quantity;
}

class ServicePackagePlanInput {
  const ServicePackagePlanInput({
    required this.name,
    required this.salePrice,
    required this.durationDays,
    required this.components,
  });

  final String name;
  final int salePrice;
  final int durationDays;
  final List<ServicePackageComponentInput> components;
}

class ServicePackagePlanComponent {
  const ServicePackagePlanComponent({
    required this.id,
    required this.serviceId,
    required this.serviceName,
    required this.listPrice,
    required this.quantity,
  });

  final String id;
  final String serviceId;
  final String serviceName;
  final int listPrice;
  final int quantity;
}

class ServicePackagePlan {
  const ServicePackagePlan({
    required this.id,
    required this.name,
    required this.salePrice,
    required this.durationDays,
    required this.isActive,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    required this.components,
  });

  final String id;
  final String name;
  final int salePrice;
  final int durationDays;
  final bool isActive;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ServicePackagePlanComponent> components;
}

class CustomerServicePackageUnit {
  const CustomerServicePackageUnit({
    required this.id,
    required this.serviceId,
    required this.serviceName,
    required this.listPrice,
    required this.quantityTotal,
    required this.balance,
    required this.allocatedValueTotal,
    required this.unitValueBase,
    required this.remainderUnits,
  });

  final String id;
  final String serviceId;
  final String serviceName;
  final int listPrice;
  final int quantityTotal;
  final int balance;
  final int allocatedValueTotal;
  final int unitValueBase;
  final int remainderUnits;
}

class CustomerServicePackage {
  const CustomerServicePackage({
    required this.id,
    required this.customerId,
    required this.planId,
    required this.planName,
    required this.salePrice,
    required this.durationDays,
    required this.startsAt,
    required this.expiresAt,
    required this.sourceType,
    required this.actor,
    required this.createdAt,
    required this.cancelled,
    required this.units,
    this.sourceId,
  });

  final String id;
  final String customerId;
  final String planId;
  final String planName;
  final int salePrice;
  final int durationDays;
  final DateTime startsAt;
  final DateTime expiresAt;
  final String sourceType;
  final String? sourceId;
  final String actor;
  final DateTime createdAt;
  final bool cancelled;
  final List<CustomerServicePackageUnit> units;
}

class ServicePackageMovement {
  const ServicePackageMovement({
    required this.id,
    required this.packageId,
    required this.packageUnitId,
    required this.kind,
    required this.quantityDelta,
    required this.recognizedValue,
    required this.createdAt,
    this.originalMovementId,
    this.invoiceId,
  });

  final String id;
  final String packageId;
  final String packageUnitId;
  final String kind;
  final String? originalMovementId;
  final int quantityDelta;
  final int recognizedValue;
  final String? invoiceId;
  final DateTime createdAt;
}
