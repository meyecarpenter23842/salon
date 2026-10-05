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
  testWidgets('split payment editor validates exact bill total', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1366, 768);
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

    final splitAction = find.byKey(
      const Key('billing-split-payment-action'),
    );
    expect(splitAction, findsOneWidget);
    await tester.tap(splitAction);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('billing-split-payment-dialog')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('billing-split-cash')), findsOneWidget);
    expect(find.byKey(const Key('billing-split-transfer')), findsOneWidget);
    expect(find.byKey(const Key('billing-split-card')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('billing-split-transfer')),
      '1',
    );
    await tester.tap(find.byKey(const Key('billing-split-payment-save')));
    await tester.pumpAndSettle();

    expect(
      find.text('Tổng các phương thức phải bằng đúng tổng bill.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
