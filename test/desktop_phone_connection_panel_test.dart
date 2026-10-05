import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/lan/desktop_backend_scope.dart';
import 'package:salonmanager/core/lan/desktop_phone_connection_panel.dart';

void main() {
  late DesktopBackendStatus original;
  setUp(() => original = desktopBackendStatus.value);
  tearDown(() => desktopBackendStatus.value = original);

  Future<void> showPanel(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: DesktopPhoneConnectionPanel()),
      ),
    ));
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
    expect(tester.takeException(), isNull);
  });
}
