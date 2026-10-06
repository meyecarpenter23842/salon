enum SensitiveAction {
  billDiscount,
  billPriceEdit,
  invoiceAdjustment,
  settingsEdit,
  stockDocument;

  String get databaseValue => switch (this) {
    SensitiveAction.billDiscount => 'bill_discount',
    SensitiveAction.billPriceEdit => 'bill_price_edit',
    SensitiveAction.invoiceAdjustment => 'invoice_adjustment',
    SensitiveAction.settingsEdit => 'settings_edit',
    SensitiveAction.stockDocument => 'stock_document',
  };

  String get label => switch (this) {
    SensitiveAction.billDiscount => 'giảm giá',
    SensitiveAction.billPriceEdit => 'sửa giá bill',
    SensitiveAction.invoiceAdjustment => 'hoàn tiền / hủy giao dịch',
    SensitiveAction.settingsEdit => 'sửa cài đặt',
    SensitiveAction.stockDocument => 'quản lý chứng từ kho',
  };
}

class AuditEvent {
  const AuditEvent({
    required this.id,
    required this.actorName,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.result,
    required this.detail,
    required this.createdAt,
  });

  final String id;
  final String actorName;
  final String action;
  final String targetType;
  final String targetId;
  final String result;
  final String detail;
  final DateTime createdAt;
}
