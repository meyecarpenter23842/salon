class PaymentConfig {
  const PaymentConfig({
    required this.bankName,
    required this.accountNumber,
    required this.accountHolder,
    required this.uploadedQrPayload,
    required this.qrMode,
    required this.transferContentTemplate,
  });

  final String bankName;
  final String accountNumber;
  final String accountHolder;
  final String uploadedQrPayload;
  final String qrMode;
  final String transferContentTemplate;

  bool get hasRequiredBankFields =>
      bankName.trim().isNotEmpty &&
      accountNumber.trim().isNotEmpty &&
      accountHolder.trim().isNotEmpty;

  bool get hasUploadedQr => uploadedQrPayload.trim().isNotEmpty;

  static const String qrModeBoth = 'both';
  static const String qrModeUploaded = 'uploaded';
  static const String qrModeGenerated = 'generated';

  static const String defaultTransferTemplate = 'Mã hóa đơn + SĐT khách';
}
