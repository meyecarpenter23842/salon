import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/receipt_template_config.dart';

class ReceiptTemplateStore {
  ReceiptTemplateStore._();

  static final ReceiptTemplateStore instance = ReceiptTemplateStore._();

  static const _storageKey = 'salon.receipt_template.v1';

  Future<ReceiptTemplateConfig> load({
    String fallbackSalonName = 'Hair Spa Manager',
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return ReceiptTemplateConfig.defaults(salonName: fallbackSalonName);
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return ReceiptTemplateConfig.defaults(salonName: fallbackSalonName);
      }
      return ReceiptTemplateConfig.fromJson(
        decoded,
        fallbackSalonName: fallbackSalonName,
      );
    } catch (_) {
      return ReceiptTemplateConfig.defaults(salonName: fallbackSalonName);
    }
  }

  Future<void> save(ReceiptTemplateConfig config) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(config.toJson()));
  }

  Future<ReceiptTemplateConfig> reset({
    String fallbackSalonName = 'Hair Spa Manager',
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
    return ReceiptTemplateConfig.defaults(salonName: fallbackSalonName);
  }
}
