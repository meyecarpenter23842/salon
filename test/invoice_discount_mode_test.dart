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
  testWidgets('line discount accepts percent and converts it to money', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Giảm giá dòng'), findsOneWidget);

    await tester.tap(find.text('Giảm giá dòng'));
    await tester.pumpAndSettle();
    expect(find.text('Số tiền'), findsOneWidget);
    expect(find.text('Phần trăm'), findsOneWidget);

    await tester.tap(find.text('Phần trăm'));
    await tester.pumpAndSettle();
    final discountField = find.byType(TextFormField).last;
    await tester.enterText(discountField, '10');
    await tester.tap(find.text('Lưu giảm giá'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('120.000'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
