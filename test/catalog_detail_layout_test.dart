import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/theme/app_theme.dart';
import 'package:salonmanager/core/theme/salon_theme_template.dart';
import 'package:salonmanager/features/sales/presentation/pages/sales_page.dart';
import 'package:salonmanager/features/services/presentation/pages/services_page.dart';

void main() {
  testWidgets('V2-6 detail panels render on desktop sizes', (tester) async {
    const sizes = [Size(1366, 768), Size(1024, 768)];

    for (final size in sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;

      await _pumpPage(tester, const ServicesPage());
      expect(find.byKey(const Key('services-premium-workspace')), findsOneWidget);
      expect(find.byKey(const Key('service-detail-performance')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'services ${size.width}x${size.height}');

      await _pumpPage(tester, const SalesPage());
      expect(find.byKey(const Key('sales-premium-workspace')), findsOneWidget);
      expect(find.byKey(const Key('product-detail-performance')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'products ${size.width}x${size.height}');
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}

Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDataBackendProvider.overrideWithValue(AppDataBackend.fake)],
      child: MaterialApp(
        theme: AppTheme.build(SalonThemeTemplate.salonNoirGold),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: page,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 220));
  await tester.pumpAndSettle(const Duration(milliseconds: 120));
}
