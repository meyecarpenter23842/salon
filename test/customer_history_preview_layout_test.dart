import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';
import 'package:salonmanager/core/theme/app_theme.dart';
import 'package:salonmanager/core/theme/salon_theme_template.dart';
import 'package:salonmanager/features/customers/presentation/pages/customers_page.dart';

void main() {
  testWidgets('customer recent history preview stays compact on desktop', (
    tester,
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
              padding: EdgeInsets.all(18),
              child: CustomersPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pumpAndSettle(const Duration(milliseconds: 120));

    final preview = find.byKey(const Key('customer-history-preview-card'));
    expect(preview, findsOneWidget);
    expect(
      tester.getSize(preview).height,
      lessThan(190),
      reason: 'two preview rows must not stretch to fill the detail panel',
    );
    expect(tester.takeException(), isNull);
  });
}
