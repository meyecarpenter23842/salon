import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../theme/salon_theme_template.dart';

class LocalSettingsStore {
  LocalSettingsStore._();

  static const _themeTemplateKey = 'theme_template';
  static const _salonNameKey = 'salon_name';
  static const _currencyKey = 'currency';
  static const _appointmentReminderKey = 'appointment_reminder';
  static const _offlineUpdatePathKey = 'offline_update_path';
  static const _autoCheckOfflineUpdateKey = 'auto_check_offline_update';
  static const _licenseKey = 'license_key';
  static const _deviceIdKey = 'device_id';
  static const _deviceNameKey = 'device_name';
  static const _bankNameKey = 'payment_bank_name';
  static const _accountNumberKey = 'payment_account_number';
  static const _accountHolderKey = 'payment_account_holder';
  static const _uploadedQrPayloadKey = 'payment_uploaded_qr_payload';
  static const _qrModeKey = 'payment_qr_mode';
  static const _transferContentTemplateKey =
      'payment_transfer_content_template';

  static const _legacyBusinessKeys = <String>[
    _salonNameKey,
    _currencyKey,
    _appointmentReminderKey,
    _bankNameKey,
    _accountNumberKey,
    _accountHolderKey,
    _uploadedQrPayloadKey,
    _qrModeKey,
    _transferContentTemplateKey,
  ];

  static final LocalSettingsStore instance = LocalSettingsStore._();

  SharedPreferences? _preferences;

  Future<void> initialize() async {
    _preferences ??= await SharedPreferences.getInstance();

    if ((_preferences?.getString(_deviceIdKey) ?? '').trim().isEmpty) {
      await _preferences!.setString(_deviceIdKey, const Uuid().v4());
    }
    if ((_preferences?.getString(_deviceNameKey) ?? '').trim().isEmpty) {
      await _preferences!.setString(_deviceNameKey, _resolveDeviceName());
    }
  }

  SalonThemeTemplate readThemeTemplate() {
    final storedValue = _preferences?.getString(_themeTemplateKey);

    // Compatibility with legacy template names that existed before the
    // four-reference visual contract was locked.
    if (storedValue == 'royalDark') {
      return SalonThemeTemplate.salonNoirGold;
    }
    if (storedValue == 'royalLight' || storedValue == 'salonSapphire') {
      return SalonThemeTemplate.salonIvory;
    }

    return SalonThemeTemplate.values.firstWhere(
      (template) => template.name == storedValue,
      orElse: () => SalonThemeTemplate.salonNoirGold,
    );
  }

  Future<void> saveThemeTemplate(SalonThemeTemplate template) async {
    await initialize();
    await _preferences!.setString(_themeTemplateKey, template.name);
  }

  Map<String, String> readDeviceSettings() {
    return {
      'offlineUpdatePath': _preferences?.getString(_offlineUpdatePathKey) ?? '',
      'autoCheckOfflineUpdate':
          _preferences?.getString(_autoCheckOfflineUpdateKey) ?? 'Tắt',
      'licenseKey': _preferences?.getString(_licenseKey) ?? '',
      'deviceId': _preferences?.getString(_deviceIdKey) ?? '',
      'deviceName':
          _preferences?.getString(_deviceNameKey) ?? _resolveDeviceName(),
    };
  }

  Future<void> saveDeviceSettings({
    required String offlineUpdatePath,
    required String autoCheckOfflineUpdate,
    required String licenseKey,
  }) async {
    await initialize();
    await _preferences!.setString(_offlineUpdatePathKey, offlineUpdatePath);
    await _preferences!.setString(
      _autoCheckOfflineUpdateKey,
      autoCheckOfflineUpdate,
    );
    await _preferences!.setString(_licenseKey, licenseKey);
  }

  Map<String, String> readStoredLegacyBusinessSettings() {
    final values = <String, String>{};

    void addIfStored(String storageKey, String viewKey) {
      final preferences = _preferences;
      if (preferences == null || !preferences.containsKey(storageKey)) {
        return;
      }
      values[viewKey] = preferences.getString(storageKey) ?? '';
    }

    addIfStored(_salonNameKey, 'salonName');
    addIfStored(_currencyKey, 'currency');
    addIfStored(_appointmentReminderKey, 'appointmentReminder');
    addIfStored(_bankNameKey, 'bankName');
    addIfStored(_accountNumberKey, 'accountNumber');
    addIfStored(_accountHolderKey, 'accountHolder');
    addIfStored(_uploadedQrPayloadKey, 'uploadedQrPayload');
    addIfStored(_qrModeKey, 'qrMode');
    addIfStored(_transferContentTemplateKey, 'transferContentTemplate');

    return values;
  }

  Future<void> clearLegacyBusinessSettings() async {
    await initialize();
    for (final key in _legacyBusinessKeys) {
      await _preferences!.remove(key);
    }
  }

  // Compatibility API for the fake/dev repository. Production SQLite settings
  // use readDeviceSettings/saveDeviceSettings and migrate business values away
  // from SharedPreferences.
  Map<String, String> readLocalSettings() {
    return {
      'salonName':
          _preferences?.getString(_salonNameKey) ?? 'Quản Lý Salon Tóc',
      'currency': _preferences?.getString(_currencyKey) ?? 'VND',
      'appointmentReminder':
          _preferences?.getString(_appointmentReminderKey) ?? 'Bật',
      ...readDeviceSettings(),
      'bankName': _preferences?.getString(_bankNameKey) ?? '',
      'accountNumber': _preferences?.getString(_accountNumberKey) ?? '',
      'accountHolder': _preferences?.getString(_accountHolderKey) ?? '',
      'uploadedQrPayload': _preferences?.getString(_uploadedQrPayloadKey) ?? '',
      'qrMode': _preferences?.getString(_qrModeKey) ?? 'both',
      'transferContentTemplate':
          _preferences?.getString(_transferContentTemplateKey) ??
          'Mã hóa đơn + SĐT khách',
    };
  }

  Future<void> saveLocalSettings({
    required String salonName,
    required String currency,
    required String appointmentReminder,
    required String offlineUpdatePath,
    required String autoCheckOfflineUpdate,
    required String licenseKey,
    required String bankName,
    required String accountNumber,
    required String accountHolder,
    required String uploadedQrPayload,
    required String qrMode,
    required String transferContentTemplate,
  }) async {
    await initialize();
    await _preferences!.setString(_salonNameKey, salonName);
    await _preferences!.setString(_currencyKey, currency);
    await _preferences!.setString(_appointmentReminderKey, appointmentReminder);
    await saveDeviceSettings(
      offlineUpdatePath: offlineUpdatePath,
      autoCheckOfflineUpdate: autoCheckOfflineUpdate,
      licenseKey: licenseKey,
    );
    await _preferences!.setString(_bankNameKey, bankName);
    await _preferences!.setString(_accountNumberKey, accountNumber);
    await _preferences!.setString(_accountHolderKey, accountHolder);
    await _preferences!.setString(_uploadedQrPayloadKey, uploadedQrPayload);
    await _preferences!.setString(_qrModeKey, qrMode);
    await _preferences!.setString(
      _transferContentTemplateKey,
      transferContentTemplate,
    );
  }

  String _resolveDeviceName() {
    try {
      final host = Platform.localHostname.trim();
      if (host.isNotEmpty) {
        return host;
      }
    } catch (_) {
      // Fall through to default label.
    }
    return 'Salon Windows';
  }
}
