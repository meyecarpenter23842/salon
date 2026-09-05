import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../database/salon_database.dart';
import '../models/receipt_template_config.dart';

class ReceiptTemplateStore {
  ReceiptTemplateStore._();

  static final ReceiptTemplateStore instance = ReceiptTemplateStore._();

  static const legacyStorageKey = 'salon.receipt_template.v1';
  static const deviceStorageKey = 'salon.receipt_device.v1';
  static const businessStorageKey = 'business.receipt_template.v1';

  Future<ReceiptTemplateConfig> load({
    String fallbackSalonName = 'Hair Spa Manager',
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final database = await SalonDatabase.instance.database;

    Map<String, Object?> business = await _readBusiness(database);
    if (business.isEmpty) {
      final legacyRaw = preferences.getString(legacyStorageKey);
      final legacy = _decodeMap(legacyRaw);
      if (legacy.isNotEmpty) {
        final config = ReceiptTemplateConfig.fromJson(
legacy,
fallbackSalonName: fallbackSalonName,
        );
        await _writeBusiness(database, config);
        await preferences.setString(
deviceStorageKey,
jsonEncode(_deviceJson(config)),
        );
        await preferences.remove(legacyStorageKey);
        business = _businessJson(config);
      }
    } else if (preferences.containsKey(legacyStorageKey)) {
      await preferences.remove(legacyStorageKey);
    }

    final device = _decodeMap(preferences.getString(deviceStorageKey));
    if (business.isEmpty && device.isEmpty) {
      return ReceiptTemplateConfig.defaults(salonName: fallbackSalonName);
    }

    return ReceiptTemplateConfig.fromJson(
      <String, Object?>{...business, ...device},
      fallbackSalonName: fallbackSalonName,
    );
  }

  Future<void> save(ReceiptTemplateConfig config) async {
    final database = await SalonDatabase.instance.database;
    final preferences = await SharedPreferences.getInstance();
    await _writeBusiness(database, config);
    await preferences.setString(deviceStorageKey, jsonEncode(_deviceJson(config)));
    await preferences.remove(legacyStorageKey);
  }

  Future<ReceiptTemplateConfig> reset({
    String fallbackSalonName = 'Hair Spa Manager',
  }) async {
    final database = await SalonDatabase.instance.database;
    final preferences = await SharedPreferences.getInstance();
    await database.delete(
      'app_settings',
      where: 'key = ?',
      whereArgs: const [businessStorageKey],
    );
    await preferences.remove(deviceStorageKey);
    await preferences.remove(legacyStorageKey);
    return ReceiptTemplateConfig.defaults(salonName: fallbackSalonName);
  }

  Future<Map<String, Object?>> _readBusiness(Database database) async {
    final rows = await database.query(
      'app_settings',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const [businessStorageKey],
      limit: 1,
    );
    if (rows.isEmpty) return const <String, Object?>{};
    return _decodeMap(rows.single['value']?.toString());
  }

  Future<void> _writeBusiness(
    Database database,
    ReceiptTemplateConfig config,
  ) async {
    final value = jsonEncode(_businessJson(config));
    final now = DateTime.now().toIso8601String();
    final updated = await database.update(
      'app_settings',
      {'value': value, 'updated_at': now},
      where: 'key = ?',
      whereArgs: const [businessStorageKey],
    );
    if (updated == 0) {
      await database.insert('app_settings', {
        'key': businessStorageKey,
        'value': value,
        'updated_at': now,
      });
    }
  }

  Map<String, Object?> _businessJson(ReceiptTemplateConfig config) => {
    'salonName': config.salonName,
    'address': config.address,
    'phone': config.phone,
    'tagline': config.tagline,
    'showInvoiceId': config.showInvoiceId,
    'showDateTime': config.showDateTime,
    'showCustomerName': config.showCustomerName,
    'showCustomerPhone': config.showCustomerPhone,
    'showPaymentMethod': config.showPaymentMethod,
    'showQuantity': config.showQuantity,
    'showUnitPrice': config.showUnitPrice,
    'showDiscount': config.showDiscount,
    'fontSize': config.fontSize,
    'layoutStyle': config.layoutStyle,
    'footerMessage': config.footerMessage,
    'footerNote': config.footerNote,
    'showQr': config.showQr,
  };

  Map<String, Object?> _deviceJson(ReceiptTemplateConfig config) => {
    'paperSize': config.paperSize,
    'printerName': config.printerName,
    'copies': config.copies,
    // A filesystem path is meaningful only on this Windows device.
    'logoPath': config.logoPath,
    'showLogo': config.showLogo,
  };

  Map<String, Object?> _decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const <String, Object?>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return Map<String, Object?>.from(decoded);
      }
    } catch (_) {
      // Corrupt preference/settings value falls back to defaults.
    }
    return const <String, Object?>{};
  }
}
