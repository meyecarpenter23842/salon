import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/features/overview/presentation/pages/staff_intake_workspace.dart';
import 'package:salonmanager/features/overview/presentation/pages/staff_window_workspace.dart';

void main() {
  Widget buildHarness() {
    return ProviderScope(
      overrides: [
        appDataBackendProvider.overrideWithValue(AppDataBackend.fake),
      ],
      child: MaterialApp(
        navigatorObservers: [staffWindowRouteObserver],
        home: const StaffIntakeWorkspace(),
      ),
    );
  }

  Future<void> pumpHarness(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildHarness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle(const Duration(milliseconds: 120));
  }

  testWidgets('Staff intake exposes add appointment and receive customer', (
    WidgetTester tester,
  ) async {
    await pumpHarness(tester);

    expect(find.byKey(const Key('staff-intake-bar')), findsOneWidget);
    expect(find.byKey(const Key('staff-add-appointment')), findsOneWidget);
    expect(find.byKey(const Key('staff-receive-customer')), findsOneWidget);
    expect(find.text('Thêm lịch'), findsOneWidget);
    expect(find.text('Nhận khách'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Add appointment starts without silently selecting a customer', (
    WidgetTester tester,
  ) async {
    await pumpHarness(tester);

    await tester.tap(find.byKey(const Key('staff-add-appointment')));
    await tester.pumpAndSettle();

    expect(find.text('Tạo lịch hẹn'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('appointment-customer-none')),
      findsOneWidget,
    );
    expect(find.text('Chọn khách hàng'), findsOneWidget);
    expect(
      find.byKey(const Key('appointment-customer-search-action')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('appointment-customer-new-action')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Receive customer has its own mode and current arrival time', (
    WidgetTester tester,
  ) async {
    await pumpHarness(tester);

    final before = DateFormat('HH:mm').format(DateTime.now());
    await tester.tap(find.byKey(const Key('staff-receive-customer')));
    await tester.pumpAndSettle();
    final after = DateFormat('HH:mm').format(DateTime.now());

    expect(find.text('Tạo lịch hẹn'), findsNothing);
    expect(find.text('Hôm nay'), findsWidgets);
    expect(find.byKey(const Key('appointment-receive-day')), findsOneWidget);
    expect(find.byKey(const Key('appointment-status-field')), findsNothing);
    expect(
      find.byKey(const ValueKey('appointment-customer-none')),
      findsOneWidget,
    );

    final timeField = tester.widget<TextFormField>(
      find.byKey(const Key('appointment-time-field')),
    );
    final timeValue = timeField.controller?.text;
    expect(timeValue == before || timeValue == after, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Receive customer can create and select a new customer inline', (
    WidgetTester tester,
  ) async {
    await pumpHarness(tester);

    await tester.tap(find.byKey(const Key('staff-receive-customer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appointment-customer-new-action')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('appointment-quick-customer-dialog')),
      findsOneWidget,
    );
    expect(find.text('Thêm khách mới'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('appointment-quick-customer-name')),
      'Khách mới CI',
    );
    await tester.enterText(
      find.byKey(const Key('appointment-quick-customer-phone')),
      '0987654321',
    );
    await tester.tap(find.byKey(const Key('appointment-quick-customer-save')));
    await tester.pumpAndSettle();

    expect(find.text('Khách mới CI • 0987654321'), findsOneWidget);
    expect(find.text('Chọn khách hàng'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
