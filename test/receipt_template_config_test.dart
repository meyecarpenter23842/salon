import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/core/models/receipt_template_config.dart';
import 'package:salonmanager/core/settings/receipt_template_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

  test('receipt template store persists owner settings locally', () async {
    final store = ReceiptTemplateStore.instance;
    final saved = ReceiptTemplateConfig.defaults(salonName: 'Salon Test').copyWith(
      paperSize: ReceiptTemplateConfig.paper58,
      printerName: 'Máy in quầy',
      copies: 2,
      address: '123 Nguyễn Huệ',
      phone: '0909 123 456',
      showLogo: true,
      logoPath: r'C:\logo.png',
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
  });
}
