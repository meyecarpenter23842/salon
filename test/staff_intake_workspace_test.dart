import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/features/overview/presentation/pages/staff_intake_workspace.dart';
import 'package:salonmanager/features/overview/presentation/pages/staff_window_workspace.dart';

void main() {
  testWidgets('Staff intake exposes add appointment and receive customer', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDataBackendProvider.overrideWithValue(AppDataBackend.fake),
        ],
        child: MaterialApp(
          navigatorObservers: [staffWindowRouteObserver],
          home: const StaffIntakeWorkspace(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle(const Duration(milliseconds: 120));

    expect(find.byKey(const Key('staff-intake-bar')), findsOneWidget);
    expect(find.byKey(const Key('staff-add-appointment')), findsOneWidget);
    expect(find.byKey(const Key('staff-receive-customer')), findsOneWidget);
    expect(find.text('Thêm lịch'), findsOneWidget);
    expect(find.text('Nhận khách'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Receive customer reuses appointment editor with current time', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDataBackendProvider.overrideWithValue(AppDataBackend.fake),
        ],
        child: MaterialApp(
          navigatorObservers: [staffWindowRouteObserver],
          home: const StaffIntakeWorkspace(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle(const Duration(milliseconds: 120));

    final before = DateFormat('HH:mm').format(DateTime.now());
    await tester.tap(find.byKey(const Key('staff-receive-customer')));
    await tester.pumpAndSettle();
    final after = DateFormat('HH:mm').format(DateTime.now());

    expect(find.text('Tạo lịch hẹn'), findsOneWidget);
    expect(find.text('Hôm nay'), findsWidgets);

    final fieldValues = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .map((field) => field.controller?.text)
        .whereType<String>()
        .toList(growable: false);
    expect(fieldValues.any((value) => value == before || value == after), isTrue);
    expect(tester.takeException(), isNull);
  });
}
