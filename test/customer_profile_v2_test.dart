import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/providers/repository_providers.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';
import 'package:salonmanager/core/theme/app_theme.dart';
import 'package:salonmanager/core/theme/salon_theme_template.dart';
import 'package:salonmanager/features/customers/presentation/pages/customers_page.dart';

void main() {
  testWidgets('customer list opens a full profile with four detail tabs', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = await _pumpCustomers(tester);
    final customers = await container.read(customersViewProvider.future);
    expect(customers, isNotEmpty);
    final customer = customers.first;

    container.read(customerProfileDetailIdProvider.notifier).state = customer.id;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.byKey(const Key('customer-full-profile')), findsOneWidget);
    expect(find.text(customer.fullName), findsWidgets);
    expect(find.text(customer.phone), findsWidgets);
    expect(find.byKey(const Key('customer-profile-book')), findsOneWidget);
    expect(find.byKey(const Key('customer-profile-billing')), findsOneWidget);
    expect(find.byKey(const Key('customer-profile-edit')), findsOneWidget);
    for (var index = 0; index < 4; index++) {
      expect(find.byKey(Key('customer-profile-tab-$index')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}

Future<ProviderContainer> _pumpCustomers(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await LocalSettingsStore.instance.initialize();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDataBackendProvider.overrideWithValue(AppDataBackend.fake)],
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

  return ProviderScope.containerOf(tester.element(find.byType(CustomersPage)));
}
