import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/core/models/invoice_draft.dart';
import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/providers/repository_providers.dart';
import 'package:salonmanager/core/repositories/invoice_line_actions_repository.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';
import 'package:salonmanager/core/theme/app_theme.dart';
import 'package:salonmanager/core/theme/salon_theme_template.dart';
import 'package:salonmanager/features/invoices/presentation/pages/invoices_page.dart';

void main() {
  testWidgets('line menu edits selling price for the current bill only', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    await LocalSettingsStore.instance.initialize();
    final actions = _RecordingLineActions();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDataBackendProvider.overrideWithValue(AppDataBackend.fake),
          invoiceLineActionsRepositoryProvider.overrideWithValue(actions),
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
    expect(find.text('Sửa giá bán'), findsOneWidget);
    expect(find.text('Chỉ áp dụng cho dòng trên bill này'), findsOneWidget);

    await tester.tap(find.text('Sửa giá bán'));
    await tester.pumpAndSettle();
    expect(find.text('Giá bán trên bill (đ)'), findsOneWidget);
    expect(
      find.text('Chỉ đổi dòng này; giá gốc trong catalog không thay đổi.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextFormField).last, '280.000');
    await tester.tap(find.text('Lưu giá bán'));
    await tester.pump(const Duration(seconds: 1));

    expect(actions.unitPrice, 280000);
    expect(actions.lineId, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}

class _RecordingLineActions implements InvoiceLineActionsRepository {
  String? lineId;
  int? unitPrice;

  @override
  Future<InvoiceDraft> splitInvoiceLine(String lineId) async => _emptyDraft();

  @override
  Future<InvoiceDraft> updateInvoiceLineUnitPrice(
    String lineId,
    int unitPrice,
  ) async {
    this.lineId = lineId;
    this.unitPrice = unitPrice;
    return _emptyDraft();
  }

  InvoiceDraft _emptyDraft() {
    final now = DateTime.now();
    return InvoiceDraft(
      id: 'invoice-draft-test',
      customerId: '',
      discountAmount: 0,
      paymentMethod: InvoiceDraft.paymentMethods.first,
      createdAt: now,
      updatedAt: now,
      lines: const [],
    );
  }
}
