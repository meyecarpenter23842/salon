import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salonmanager/core/lan/lan_health_client.dart';
import 'package:salonmanager/features/companion/companion_app.dart';

class _Checker implements LanHealthChecker {
  int calls = 0;
  Completer<void>? completion;
  bool fail = false;
  @override
  Future<void> check(LanConnection connection) async {
    calls++;
    if (fail) throw StateError('private diagnostics must not appear');
    if (completion != null) await completion!.future;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> fill(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('companion-url')),
      'https://192.168.1.20:8743/api/staff/v1');
    await tester.enterText(find.byKey(const Key('companion-pin')), 'a' * 64);
  }

  testWidgets('phone shell starts without desktop bootstrap and validates form',
    (tester) async {
      final checker = _Checker();
      await tester.pumpWidget(SalonCompanionApp(checker: checker));
      await tester.pumpAndSettle();
      expect(find.text('Kết nối máy salon'), findsOneWidget);
      await tester.tap(find.byKey(const Key('companion-check')));
      await tester.pumpAndSettle();
      expect(checker.calls, 0);
      expect(find.textContaining('Nhập URL HTTPS'), findsOneWidget);
    });

  testWidgets('success saves endpoint and pin; reopened shell restores inputs',
    (tester) async {
      final checker = _Checker();
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(SalonCompanionApp(checker: checker));
      await tester.pumpAndSettle();
      await fill(tester);
      await tester.ensureVisible(find.byKey(const Key('companion-check')));
      await tester.tap(find.byKey(const Key('companion-check')));
      await tester.pumpAndSettle();
      expect(checker.calls, 1);
      expect(find.textContaining('Máy salon đang phản hồi'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(SalonCompanionApp(checker: checker));
      await tester.pumpAndSettle();
      final url = tester.widget<TextFormField>(
        find.byKey(const Key('companion-url')));
      expect(url.controller!.text, 'https://192.168.1.20:8743/api/staff/v1');
      expect(find.byKey(const Key('companion-result')), findsNothing);
    });

  testWidgets('failure is safe and does not persist a new endpoint', (tester) async {
    final checker = _Checker()..fail = true;
    await tester.pumpWidget(SalonCompanionApp(checker: checker));
    await tester.pumpAndSettle();
    await fill(tester);
    await tester.tap(find.byKey(const Key('companion-check')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Không kết nối được'), findsOneWidget);
    expect(find.textContaining('private diagnostics'), findsNothing);
    expect((await SharedPreferences.getInstance()).getString('companion_api_url'),
      isNull);
  });

  testWidgets('busy disables double tap; background invalidates late success',
    (tester) async {
      final checker = _Checker()..completion = Completer<void>();
      await tester.pumpWidget(SalonCompanionApp(checker: checker));
      await tester.pumpAndSettle();
      await fill(tester);
      await tester.tap(find.byKey(const Key('companion-check')));
      await tester.pump();
      expect(tester.widget<FilledButton>(
        find.byKey(const Key('companion-check'))).onPressed, isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      checker.completion!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('companion-result')), findsNothing);
      expect(checker.calls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
}
