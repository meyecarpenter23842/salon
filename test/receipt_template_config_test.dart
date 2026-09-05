import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/receipt_template_config.dart';
import 'package:salonmanager/core/settings/receipt_template_store.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('receipt template defaults to 80mm standard receipt', () {
    final config = ReceiptTemplateConfig.defaults(salonName: 'Salon Test');

    expect(config.paperSize, ReceiptTemplateConfig.paper80);
    expect(config.copies, 1);
    expect(config.salonName, 'Salon Test');
    expect(config.layoutStyle, ReceiptTemplateConfig.layoutStandard);
    expect(config.fontSize, ReceiptTemplateConfig.fontMedium);
    expect(config.showInvoiceId, isTrue);
    expect(config.showCustomerName, isTrue);
  });

  test('receipt template sanitizes invalid persisted values', () {
    final config = ReceiptTemplateConfig.fromJson(
      {
        'paperSize': '100mm',
        'copies': 99,
        'fontSize': 'huge',
        'layoutStyle': 'freeform',
        'showCustomerPhone': false,
      },
      fallbackSalonName: 'Salon Test',
    );

    expect(config.paperSize, ReceiptTemplateConfig.paper80);
    expect(config.copies, 3);
    expect(config.fontSize, ReceiptTemplateConfig.fontMedium);
    expect(config.layoutStyle, ReceiptTemplateConfig.layoutStandard);
    expect(config.showCustomerPhone, isFalse);
  });

  test('receipt business template is in SQLite while device output stays local', () async {
    final store = ReceiptTemplateStore.instance;
    final saved = ReceiptTemplateConfig.defaults(salonName: 'Salon Test').copyWith(
      paperSize: ReceiptTemplateConfig.paper58,
      printerName: 'Máy in quầy',
      copies: 2,
      address: '123 Nguyễn Huệ',
      phone: '0909 123 456',
      showLogo: true,
      logoPath: r'C:\\logo.png',
      showCustomerPhone: false,
      fontSize: ReceiptTemplateConfig.fontLarge,
      layoutStyle: ReceiptTemplateConfig.layoutCompact,
      footerMessage: 'Cảm ơn quý khách!',
      showQr: true,
    );

    await store.save(saved);
    final loaded = await store.load(fallbackSalonName: 'Khác');

    expect(loaded.paperSize, ReceiptTemplateConfig.paper58);
    expect(loaded.printerName, 'Máy in quầy');
    expect(loaded.copies, 2);
    expect(loaded.address, '123 Nguyễn Huệ');
    expect(loaded.showCustomerPhone, isFalse);
    expect(loaded.fontSize, ReceiptTemplateConfig.fontLarge);
    expect(loaded.layoutStyle, ReceiptTemplateConfig.layoutCompact);
    expect(loaded.footerMessage, 'Cảm ơn quý khách!');
    expect(loaded.showQr, isTrue);

    final database = await SalonDatabase.instance.database;
    final rows = await database.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: const [ReceiptTemplateStore.businessStorageKey],
    );
    expect(rows, hasLength(1));
    final business = jsonDecode(rows.single['value']!.toString()) as Map<String, dynamic>;
    expect(business['address'], '123 Nguyễn Huệ');
    expect(business.containsKey('printerName'), isFalse);
    expect(business.containsKey('paperSize'), isFalse);
    expect(business.containsKey('copies'), isFalse);

    final preferences = await SharedPreferences.getInstance();
    final deviceRaw = preferences.getString(ReceiptTemplateStore.deviceStorageKey);
    expect(deviceRaw, isNotNull);
    final device = jsonDecode(deviceRaw!) as Map<String, dynamic>;
    expect(device['printerName'], 'Máy in quầy');
    expect(device['paperSize'], ReceiptTemplateConfig.paper58);
    expect(device['copies'], 2);
    expect(device.containsKey('address'), isFalse);
  });
}
