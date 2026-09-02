class SettingsUpsertInput {
  const SettingsUpsertInput({
    required this.salonName,
    required this.currency,
    required this.appointmentReminder,
    required this.offlineUpdatePath,
    required this.autoCheckOfflineUpdate,
    required this.licenseKey,
    required this.bankName,
    required this.accountNumber,
    required this.accountHolder,
    required this.uploadedQrPayload,
    required this.qrMode,
    required this.transferContentTemplate,
  });

  final String salonName;
  final String currency;
  final String appointmentReminder;
  final String offlineUpdatePath;
  final String autoCheckOfflineUpdate;
  final String licenseKey;
  final String bankName;
  final String accountNumber;
  final String accountHolder;
  final String uploadedQrPayload;
  final String qrMode;
  final String transferContentTemplate;
}
