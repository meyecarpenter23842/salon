import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/app/app.dart';
import 'package:salonmanager/app/navigation/desktop_navigation.dart';
import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';
import 'package:salonmanager/features/customers/presentation/pages/customers_page.dart';

void main() {
  testWidgets(
    'creating a customer keeps the current customer search unchanged',
    (tester) async {
      tester.view.physicalSize = const Size(1724, 908);
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
      await _pumpUi(tester);

      final container = _containerOf(tester);
      container.read(desktopSectionProvider.notifier).state =
          DesktopSection.customers;
      await _pumpUi(tester);

      expect(container.read(customerSearchQueryProvider), isEmpty);
      expect(find.text('Chị Lan'), findsWidgets);

      await tester.tap(find.text('Thêm khách').first);
      await tester.pump();

      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      final fields = find.descendant(
        of: dialog,
        matching: find.byType(TextFormField),
      );
      expect(fields, findsNWidgets(6));

      await tester.enterText(fields.at(0), 'Minh Test');
      await tester.enterText(fields.at(1), '0900000001');
      await tester.tap(find.text('Tạo hồ sơ'));
      await _pumpUi(tester);

      expect(container.read(customerSearchQueryProvider), isEmpty);
      final visibleCustomers = await container.read(filteredCustomersProvider.future);
      final visibleNames = visibleCustomers
          .map((customer) => customer.fullName)
          .toList(growable: false);
      expect(visibleNames, contains('Minh Test'));
      expect(visibleNames, contains('Chị Lan'));
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

ProviderContainer _containerOf(WidgetTester tester) {
  final context = tester.element(find.byType(SalonManagerApp));
  return ProviderScope.containerOf(context);
}
