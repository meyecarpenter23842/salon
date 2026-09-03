import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';
import 'package:salonmanager/core/theme/app_theme.dart';
import 'package:salonmanager/core/theme/salon_theme_template.dart';
import 'package:salonmanager/features/invoices/presentation/pages/invoices_page.dart';

void main() {
  testWidgets('billing POS stays viewport-bound with three operation zones', (
    WidgetTester tester,
  ) async {
    const sizes = [
      Size(1724, 908),
      Size(1366, 768),
      Size(1024, 768),
    ];

    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in sizes) {
      tester.view.physicalSize = size;
      SharedPreferences.setMockInitialValues({});
      await LocalSettingsStore.instance.initialize();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDataBackendProvider.overrideWithValue(AppDataBackend.fake),
          ],
          child: MaterialApp(
            theme: AppTheme.build(SalonThemeTemplate.salonNoirGold),
            home: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: InvoicesPage(),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      final workspace = find.byKey(const Key('billing-premium-workspace'));
      expect(workspace, findsOneWidget);
      expect(tester.widget(workspace), isA<Column>());
      expect(find.byKey(const Key('billing-premium-header')), findsOneWidget);
      expect(find.byKey(const Key('billing-pos-bill')), findsOneWidget);
      expect(find.byKey(const Key('billing-pos-catalog')), findsOneWidget);
      expect(find.byKey(const Key('billing-pos-checkout')), findsOneWidget);
      expect(find.text('Bill'), findsOneWidget);
      expect(find.text('Dịch vụ / Sản phẩm'), findsOneWidget);
      expect(find.text('Khách + Thanh toán'), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: '${size.width}x${size.height}',
      );
    }
  });
}
