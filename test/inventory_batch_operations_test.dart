import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';
import 'package:salonmanager/core/theme/app_theme.dart';
import 'package:salonmanager/core/theme/salon_theme_template.dart';
import 'package:salonmanager/features/inventory/presentation/pages/inventory_page.dart';

void main() {
  testWidgets('inventory supports selecting multiple products and final yes no confirmation', (
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
              child: InventoryPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('inventory-batch-actions')), findsOneWidget);
    expect(find.byKey(const Key('inventory-batch-receive')), findsOneWidget);
    expect(find.byKey(const Key('inventory-batch-adjust')), findsOneWidget);

    final checkboxes = find.byType(Checkbox);
    expect(checkboxes, findsWidgets);
    await tester.tap(checkboxes.at(1));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('inventory-batch-receive')));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    final quantityField = find.descendant(
      of: dialog,
      matching: find.byType(TextFormField),
    ).first;
    await tester.enterText(quantityField, '3');
    await tester.tap(find.byKey(const Key('inventory-batch-submit')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('inventory-final-confirm-dialog')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('inventory-confirm-no')), findsOneWidget);
    expect(find.byKey(const Key('inventory-confirm-yes')), findsOneWidget);

    await tester.tap(find.byKey(const Key('inventory-confirm-no')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('inventory-final-confirm-dialog')),
      findsNothing,
    );
  });
}
