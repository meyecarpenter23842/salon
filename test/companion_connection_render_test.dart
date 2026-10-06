import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salonmanager/core/lan/desktop_backend_scope.dart';
import 'package:salonmanager/core/lan/desktop_phone_connection_panel.dart';
import 'package:salonmanager/core/lan/lan_connection_qr.dart';
import 'package:salonmanager/core/lan/lan_health_client.dart';
import 'package:salonmanager/features/companion/companion_app.dart';
import 'companion_mobile_bill_test.dart' show billTap;
import 'support/mobile_bill_fixture.dart';
class _Health implements LanHealthChecker {
  @override Future<void> check(LanConnection c) async {}
}
void main() {
  testWidgets('CI connection images: onboarding, QR trust and desktop QR', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final font = await tester.runAsync(() => File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf').readAsBytes());
    final icon = await tester.runAsync(() => File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes());
    await tester.runAsync((FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(font!)))).load);
    await tester.runAsync((FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icon!)))).load);
    final boundary = GlobalKey(), output = Directory('build/mobile-ui-review');
    await tester.runAsync(() => output.create(recursive: true));
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 1), png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${output.path}/$name.png').writeAsBytes(png!.buffer.asUint8List()); image.dispose();
      }); expect(tester.takeException(), isNull);
    }
    SharedPreferences.setMockInitialValues({});
    final client = BillTestClient(), store = BillTestStore();
    ValueChanged<String>? detect;
    await tester.pumpWidget(RepaintBoundary(key: boundary, child: SalonCompanionApp(
      checker: _Health(), credentialStore: store, readClient: client, workflowClient: client,
      scannerPreview: (context, callback) { detect = callback; return const Center(child: Icon(Icons.qr_code_scanner, size: 120)); })));
    await tester.pumpAndSettle(); await capture('18-connection-qr-onboarding');
    await billTap(tester, 'companion-scan-qr'); await capture('19-connection-scanner');
    detect!(LanConnectionQr.encode(LanConnection('https://192.168.1.20:8743/api/staff/v1', 'b' * 64)));
    await tester.pumpAndSettle(); await capture('20-connection-qr-confirm');
    await tester.pumpWidget(const SizedBox());
    final original = desktopBackendStatus.value;
    desktopBackendStatus.value = DesktopBackendStatus('Kết nối HTTPS đã bật',
      apiUrl: Uri.parse('https://192.168.1.20:8743/api/staff/v1'), certificateSha256: 'b' * 64);
    tester.view.physicalSize = const Size(640, 1120);
    await tester.pumpWidget(RepaintBoundary(key: boundary, child: ProviderScope(child: MaterialApp(
      debugShowCheckedModeBanner: false, theme: ThemeData(fontFamily: 'Roboto'),
      home: const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(24), child: DesktopPhoneConnectionPanel()))))));
    await tester.pumpAndSettle(); await capture('21-desktop-connection-qr');
    await tester.pumpWidget(const SizedBox()); desktopBackendStatus.value = original;
  }, skip: !Platform.isLinux || Platform.environment['GITHUB_ACTIONS'] != 'true');
}
