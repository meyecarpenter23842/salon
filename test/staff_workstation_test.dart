import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/app/app.dart';
import 'package:salonmanager/app/navigation/desktop_navigation.dart';
import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';

void main() {
  testWidgets('staff workstation opens and core actions navigate to billing', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
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
        child: const SalonManagerApp(),
      ),
    );

    await pumpUi(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SalonManagerApp)),
      listen: false,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Bàn nhân viên'));
    await pumpUi(tester);

    expect(find.text('Bàn thao tác nhân viên'), findsOneWidget);
    expect(find.textContaining('Chị Lan'), findsWidgets);

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Bắt đầu dịch vụ').first,
    );
    await pumpUi(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Tính tiền').first);
    await pumpUi(tester);

    expect(container.read(desktopSectionProvider), DesktopSection.invoices);
    expect(find.byKey(const Key('billing-premium-workspace')), findsOneWidget);
    expect(find.text('Tính tiền'), findsWidgets);
  });
}

Future<void> pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pumpAndSettle(const Duration(milliseconds: 120));
}
