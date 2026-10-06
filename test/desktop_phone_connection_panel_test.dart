import 'dart:async';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:salonmanager/core/lan/lan_connection_qr.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/lan/lan_setup_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/lan/desktop_backend_scope.dart';
import 'package:salonmanager/core/lan/desktop_phone_connection_panel.dart';

void main() {
  late DesktopBackendStatus original;
  setUp(() => original = desktopBackendStatus.value);
  tearDown(() => desktopBackendStatus.value = original);

  Future<void> showPanel(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: DesktopPhoneConnectionPanel()),
      ),
    )));
    await tester.pumpAndSettle();
  }

  testWidgets('copies exact address and certificate pin with phone labels', (tester) async {
    const address = 'https://192.168.1.20:8743/api/staff/v1';
    final pin = 'a' * 64;
    desktopBackendStatus.value = DesktopBackendStatus(
      'Sẵn sàng', apiUrl: Uri.parse(address), certificateSha256: pin,
    );
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
    await showPanel(tester);
    expect(find.text('Địa chỉ máy salon'), findsOneWidget);
    expect(find.text('Mã xác minh máy salon'), findsOneWidget);
    for (final field in ['address', 'verification']) {
      final button = find.byKey(Key('desktop-phone-copy-$field'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }
    expect(copied, [address, pin]);
    final qr = tester.widget<QrImageView>(find.byKey(const Key('desktop-phone-qr')));
    // Copying and scanning use the same strict discovery protocol.
    final qrCopy = find.byKey(const Key('desktop-phone-copy-qr'));
    await tester.ensureVisible(qrCopy); await tester.tap(qrCopy); await tester.pumpAndSettle();
    final decoded = LanConnectionQr.decode(copied.last);
    expect(decoded.apiUrl.toString(), address); expect(decoded.certificateSha256, pin);
    expect(qr.size, 220);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unconfigured and stopped host never expose stale connection values', (tester) async {
    desktopBackendStatus.value = const DesktopBackendStatus('Chưa cấu hình');
    await showPanel(tester);
    expect(find.byKey(const Key('desktop-phone-address')), findsNothing);
    expect(find.byKey(const Key('desktop-phone-verification')), findsNothing);
    expect(find.textContaining('Chưa có thông tin'), findsOneWidget);

    desktopBackendStatus.value = DesktopBackendStatus(
      'Sẵn sàng', apiUrl: Uri.parse('https://192.168.1.20:8743/api/staff/v1'),
      certificateSha256: 'b' * 64,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('desktop-phone-address')), findsOneWidget);
    desktopBackendStatus.value = const DesktopBackendStatus('Đã dừng');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('desktop-phone-address')), findsNothing);
    expect(find.byKey(const Key('desktop-phone-copy-verification')), findsNothing);
    expect(find.byKey(const Key('desktop-phone-qr')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('enable uses selected network, blocks double tap and shows ready without restart', (tester) async {
    desktopBackendStatus.value = const DesktopBackendStatus('Chưa cấu hình');
    final done = Completer<void>();
    final calls = <String>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [appDataBackendProvider.overrideWithValue(AppDataBackend.fake)],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: DesktopPhoneConnectionPanel(
          networkLoader: () async => [LanNetwork('Wi-Fi', InternetAddress('192.168.1.20'))],
          onEnable: (address) async {
            calls.add(address.address);
            await done.future;
            desktopBackendStatus.value = DesktopBackendStatus('Đã bật',
              apiUrl: Uri.parse('https://192.168.1.20:8743/api/staff/v1'),
              certificateSha256: 'a' * 64);
          },
        ),
      ))),
    ));
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('desktop-phone-enable'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(calls, ['192.168.1.20']);
    done.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('desktop-phone-verification')), findsOneWidget);
    expect(find.text('Áp dụng mạng đã chọn'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no network gives actionable recovery and disables enable', (tester) async {
    desktopBackendStatus.value = const DesktopBackendStatus('Chưa cấu hình');
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: DesktopPhoneConnectionPanel(
          networkLoader: () async => [], onEnable: (_) async {},
        ),
      ))),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Chưa tìm thấy mạng phù hợp'), findsOneWidget);
    expect(tester.widget<FilledButton>(
      find.byKey(const Key('desktop-phone-enable'))).onPressed, isNull);
    expect(find.text('Tìm lại mạng'), findsOneWidget);
  });

}

