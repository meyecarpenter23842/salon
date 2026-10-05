import '../models/payment_config.dart';
import '../models/settings_upsert_input.dart';
import '../models/audit_event.dart';
import '../services/sensitive_action_service.dart';
import 'repository_contracts.dart';

class GuardedSettingsRepository implements SettingsRepository {
  GuardedSettingsRepository(this._delegate, this._security);

  final SettingsRepository _delegate;
  final SensitiveActionService _security;

  @override
  Future<Map<String, Object?>> fetchLocalSettings() =>
      _delegate.fetchLocalSettings();

  @override
  Future<PaymentConfig> fetchPaymentConfig() =>
      _delegate.fetchPaymentConfig();

  @override
  Future<Map<String, Object?>> saveLocalSettings(SettingsUpsertInput input) {
    return _security.runSensitive(
      action: SensitiveAction.settingsEdit,
      targetType: 'settings',
      targetId: 'all',
      operation: () => _delegate.saveLocalSettings(input),
    );
  }

  @override
  Future<Map<String, Object?>> saveSalonProfileSettings({
    required String salonName,
    required String appointmentReminder,
  }) {
    return _security.runSensitive(
      action: SensitiveAction.settingsEdit,
      targetType: 'settings',
      targetId: 'salon_profile',
      operation: () => _delegate.saveSalonProfileSettings(
        salonName: salonName,
        appointmentReminder: appointmentReminder,
      ),
    );
  }

  @override
  Future<Map<String, Object?>> saveDeviceUpdateSettings({
    required String offlineUpdatePath,
    required String autoCheckOfflineUpdate,
    required String licenseKey,
  }) {
    return _security.runSensitive(
      action: SensitiveAction.settingsEdit,
      targetType: 'settings',
      targetId: 'device_update',
      operation: () => _delegate.saveDeviceUpdateSettings(
        offlineUpdatePath: offlineUpdatePath,
        autoCheckOfflineUpdate: autoCheckOfflineUpdate,
        licenseKey: licenseKey,
      ),
    );
  }

  @override
  Future<Map<String, Object?>> savePaymentSettings({
    required String bankName,
    required String accountNumber,
    required String accountHolder,
    required String transferContentTemplate,
  }) {
    return _security.runSensitive(
      action: SensitiveAction.settingsEdit,
      targetType: 'settings',
      targetId: 'payment',
      operation: () => _delegate.savePaymentSettings(
        bankName: bankName,
        accountNumber: accountNumber,
        accountHolder: accountHolder,
        transferContentTemplate: transferContentTemplate,
      ),
    );
  }
}
