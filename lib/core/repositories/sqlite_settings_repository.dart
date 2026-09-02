import 'package:sqflite/sqflite.dart';

import '../database/salon_database.dart';
import '../models/payment_config.dart';
import '../models/settings_upsert_input.dart';
import '../settings/local_settings_store.dart';
import 'repository_contracts.dart';

class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository(this._database, this._localSettingsStore);

  final SalonDatabase _database;
  final LocalSettingsStore _localSettingsStore;

  static const _migrationMarkerKey = 'settings_ownership_v1';

  static const _databaseKeys = <String, String>{
    'salonName': 'business.salon_name',
    'currency': 'business.currency',
    'appointmentReminder': 'business.appointment_reminder',
    'bankName': 'business.payment.bank_name',
    'accountNumber': 'business.payment.account_number',
    'accountHolder': 'business.payment.account_holder',
    'uploadedQrPayload': 'business.payment.uploaded_qr_payload',
    'qrMode': 'business.payment.qr_mode',
    'transferContentTemplate': 'business.payment.transfer_content_template',
  };

  static const _businessDefaults = <String, String>{
    'salonName': 'Quản Lý Salon Tóc',
    'currency': 'VND',
    'appointmentReminder': 'Bật',
    'bankName': '',
    'accountNumber': '',
    'accountHolder': '',
    'uploadedQrPayload': '',
    'qrMode': PaymentConfig.qrModeBoth,
    'transferContentTemplate': PaymentConfig.defaultTransferTemplate,
  };

  @override
  Future<Map<String, Object?>> fetchLocalSettings() async {
    final database = await _database.database;
    await _migrateLegacyBusinessSettings(database);

    final business = await _readBusinessSettings(database);
    final device = _localSettingsStore.readDeviceSettings();

    return <String, Object?>{
      ..._businessDefaults,
      ...business,
      ...device,
      'themeDefault': 'Salon Emerald',
      'themeGoal':
          'Compact desktop dashboard, thong tin day du, de van hanh thuc te',
      'sampleData': 'Không tự tạo dữ liệu mẫu trong SQLite',
    };
  }

  @override
  Future<Map<String, Object?>> saveLocalSettings(
    SettingsUpsertInput input,
  ) async {
    final database = await _database.database;
    await _migrateLegacyBusinessSettings(database);

    final now = DateTime.now().toIso8601String();
    final businessValues = <String, String>{
      'salonName': input.salonName,
      'currency': input.currency,
      'appointmentReminder': input.appointmentReminder,
      'bankName': input.bankName,
      'accountNumber': input.accountNumber,
      'accountHolder': input.accountHolder,
      'uploadedQrPayload': input.uploadedQrPayload,
      'qrMode': input.qrMode,
      'transferContentTemplate': input.transferContentTemplate,
    };

    await database.transaction((transaction) async {
      for (final entry in businessValues.entries) {
        await _upsertSetting(
          transaction,
          key: _databaseKeys[entry.key]!,
          value: entry.value,
          updatedAt: now,
        );
      }
    });

    await _localSettingsStore.saveDeviceSettings(
      offlineUpdatePath: input.offlineUpdatePath,
      autoCheckOfflineUpdate: input.autoCheckOfflineUpdate,
      licenseKey: input.licenseKey,
    );

    return fetchLocalSettings();
  }

  @override
  Future<PaymentConfig> fetchPaymentConfig() async {
    final settings = await fetchLocalSettings();
    return PaymentConfig(
      bankName: settings['bankName']?.toString() ?? '',
      accountNumber: settings['accountNumber']?.toString() ?? '',
      accountHolder: settings['accountHolder']?.toString() ?? '',
      uploadedQrPayload: settings['uploadedQrPayload']?.toString() ?? '',
      qrMode: settings['qrMode']?.toString() ?? PaymentConfig.qrModeBoth,
      transferContentTemplate:
          settings['transferContentTemplate']?.toString() ??
          PaymentConfig.defaultTransferTemplate,
    );
  }

  Future<Map<String, String>> _readBusinessSettings(Database database) async {
    final keys = _databaseKeys.values.toList(growable: false);
    final placeholders = List.filled(keys.length, '?').join(', ');
    final rows = await database.query(
      'app_settings',
      columns: const ['key', 'value'],
      where: 'key IN ($placeholders)',
      whereArgs: keys,
    );

    final viewKeyByDatabaseKey = <String, String>{
      for (final entry in _databaseKeys.entries) entry.value: entry.key,
    };
    final values = <String, String>{};
    for (final row in rows) {
      final databaseKey = row['key']?.toString();
      final viewKey = databaseKey == null
          ? null
          : viewKeyByDatabaseKey[databaseKey];
      if (viewKey == null) {
        continue;
      }
      values[viewKey] = row['value']?.toString() ?? '';
    }
    return values;
  }

  Future<void> _migrateLegacyBusinessSettings(Database database) async {
    final markerRows = await database.query(
      'app_settings',
      columns: const ['key'],
      where: 'key = ?',
      whereArgs: const [_migrationMarkerKey],
      limit: 1,
    );

    if (markerRows.isNotEmpty) {
      await _localSettingsStore.clearLegacyBusinessSettings();
      return;
    }

    final legacyValues = _localSettingsStore.readStoredLegacyBusinessSettings();
    final now = DateTime.now().toIso8601String();

    await database.transaction((transaction) async {
      final markerInsideTransaction = await transaction.query(
        'app_settings',
        columns: const ['key'],
        where: 'key = ?',
        whereArgs: const [_migrationMarkerKey],
        limit: 1,
      );
      if (markerInsideTransaction.isNotEmpty) {
        return;
      }

      for (final entry in legacyValues.entries) {
        final databaseKey = _databaseKeys[entry.key];
        if (databaseKey == null) {
          continue;
        }

        final existing = await transaction.query(
          'app_settings',
          columns: const ['key'],
          where: 'key = ?',
          whereArgs: [databaseKey],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          continue;
        }

        await _upsertSetting(
          transaction,
          key: databaseKey,
          value: entry.value,
          updatedAt: now,
        );
      }

      await _upsertSetting(
        transaction,
        key: _migrationMarkerKey,
        value: 'completed',
        updatedAt: now,
      );
    });

    await _localSettingsStore.clearLegacyBusinessSettings();
  }

  Future<void> _upsertSetting(
    DatabaseExecutor database, {
    required String key,
    required String value,
    required String updatedAt,
  }) async {
    await database.insert(
      'app_settings',
      {
        'key': key,
        'value': value,
        'updated_at': updatedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
