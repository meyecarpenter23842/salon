import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/app/app.dart';
import 'package:salonmanager/app/navigation/desktop_navigation.dart';
import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';
import 'package:salonmanager/features/customers/presentation/pages/customers_page.dart';
import 'package:salonmanager/features/invoices/presentation/pages/invoices_page.dart';
import 'package:salonmanager/features/services/presentation/pages/services_page.dart';
import 'package:salonmanager/features/settings/presentation/pages/settings_page.dart';

void main() {
  testWidgets('Quick smoke test - all tabs load', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(tester.view.resetPhysicalSize);

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
    await tester.pump(const Duration(seconds: 2));

    final container = _containerOf(tester);

    container.read(desktopSectionProvider.notifier).state =
        DesktopSection.customers;
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CustomersPage), findsOneWidget);

    container.read(desktopSectionProvider.notifier).state =
        DesktopSection.services;
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ServicesPage), findsOneWidget);

    container.read(desktopSectionProvider.notifier).state =
        DesktopSection.invoices;
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(InvoicesPage), findsOneWidget);

    container.read(desktopSectionProvider.notifier).state =
        DesktopSection.settings;
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('Theme templates load without crash', (
    WidgetTester tester,
  ) async {
    final templates = ['salonNoirGold', 'salonEmerald', 'salonSapphire'];

    for (final template in templates) {
      tester.view.physicalSize = const Size(1366, 768);
      SharedPreferences.setMockInitialValues({'theme_template': template});
      await LocalSettingsStore.instance.initialize();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDataBackendProvider.overrideWithValue(AppDataBackend.fake),
          ],
          child: const SalonManagerApp(),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(SalonManagerApp), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    addTearDown(tester.view.resetPhysicalSize);
  });

  testWidgets('Common desktop sizes render core tabs', (
    WidgetTester tester,
  ) async {
    const sizes = [
      Size(1920, 1080),
      Size(1600, 900),
      Size(1366, 768),
      Size(1280, 720),
      Size(1024, 768),
    ];

    // Track overflow errors to surface in reason message
    final List<String> overflowErrors = [];
    final void Function(FlutterErrorDetails)? prevHandler =
        FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final msg = details.toString();
      overflowErrors.add(msg);
      // Print full diagnostics so overflow location can be identified from logs.
      FlutterError.dumpErrorToConsole(details, forceReport: true);
      // still delegate to original handler if present
      prevHandler?.call(details);
    };

    try {
      for (final size in sizes) {
        tester.view.physicalSize = size;
        SharedPreferences.setMockInitialValues({
          'theme_template': 'salonNoirGold',
        });
        await LocalSettingsStore.instance.initialize();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDataBackendProvider.overrideWithValue(AppDataBackend.fake),
            ],
            child: const SalonManagerApp(),
          ),
        );
        await tester.pump(const Duration(seconds: 2));

        final container = _containerOf(tester);
        for (final section in [
          DesktopSection.overview,
          DesktopSection.appointments,
          DesktopSection.customers,
          DesktopSection.services,
          DesktopSection.employees,
          DesktopSection.invoices,
          DesktopSection.reports,
          DesktopSection.settings,
        ]) {
          overflowErrors.clear();
          container.read(desktopSectionProvider.notifier).state = section;
          await tester.pump(const Duration(milliseconds: 800));
          // Consume any exception - if it's overflow, fail with detail
          final exception = tester.takeException();
          if (exception != null) {
            final detail = overflowErrors.isNotEmpty ? overflowErrors.last : '';
            fail(
              '${size.width}x${size.height} / ${section.name}: $exception\n$detail',
            );
          }
        }
      }
    } finally {
      FlutterError.onError = prevHandler;
    }

    addTearDown(tester.view.resetPhysicalSize);
  });
}

ProviderContainer _containerOf(WidgetTester tester) {
  final context = tester.element(find.byType(SalonManagerApp));
  return ProviderScope.containerOf(context);
}
