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
  testWidgets(
    'checkout confirms, shows success receipt and lets history reopen invoice',
    (WidgetTester tester) async {
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
              body: Padding(padding: EdgeInsets.all(16), child: InvoicesPage()),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byTooltip('Tìm và đổi khách'));
      await tester.pumpAndSettle();
      expect(find.text('Chọn khách cho bill'), findsOneWidget);
      final customer = find.text('Chị Lan');
      expect(customer, findsWidgets);
      await tester.tap(customer.last);
      await tester.pumpAndSettle();

      final checkout = find.byKey(const Key('billing-checkout-action'));
      expect(checkout, findsOneWidget);
      await tester.tap(checkout);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('checkout-confirm-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('checkout-confirm-yes')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('checkout-success-dialog')), findsOneWidget);
      expect(find.text('Thanh toán thành công'), findsOneWidget);
      expect(find.text('Xem phiếu'), findsOneWidget);
      expect(find.text('In phiếu'), findsOneWidget);

      await tester.tap(find.byKey(const Key('checkout-success-view-receipt')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('invoice-receipt-dialog')), findsOneWidget);
      expect(find.text('Phiếu thanh toán'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Đóng'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('checkout-success-dialog')), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Hóa đơn mới'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('billing-history-action')));
      await tester.pumpAndSettle();
      expect(find.text('Hóa đơn gần đây'), findsOneWidget);

      final historyTile = find.byWidgetPredicate(
        (widget) => widget is ListTile && widget.onTap != null,
      );
      expect(historyTile, findsWidgets);
      await tester.tap(historyTile.first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('invoice-receipt-dialog')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
