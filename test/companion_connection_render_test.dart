import 'dart:io';
import 'dart:async';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:salonmanager/core/lan/lan_changes.dart';
import 'package:salonmanager/core/lan/lan_contract.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/lan/lan_pairing_client.dart';
import 'package:salonmanager/core/lan/lan_write_contract.dart';
import 'package:salonmanager/features/companion/companion_access_panel.dart';
import 'package:salonmanager/features/companion/companion_theme.dart';
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
class _Pair implements LanPairingClient {
  bool offline = false;
  PairedPhone get phone => PairedPhone('a' * 64, 'Phone', PhoneAccess.approved, DateTime.utc(2026),
    canReadSalon: true, writeRole: PhoneWriteRole.cashier);
  @override Future<PairedPhone> status(LanConnection c, String token) async {
    if (offline) throw const PairingFailure(LanErrorCode.unavailable); return phone;
  }
  @override Future<PairedPhone> bootstrap(LanConnection c, String token) async => status(c, token);
  @override Future<PairedPhone> request(LanConnection c, String code, String name, String token) async => phone;
}
class _Changes implements LanChangeClient {
  Completer<LanChangeSnapshot>? delayed;
  @override Future<LanChangeSnapshot> read(LanConnection c, String token, String? epoch, int cursor) async =>
    delayed == null ? const LanChangeSnapshot('epoch-a', 1, reset: true, changed: true) : delayed!.future;
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
    Future<void> capture(String name, {bool settle = true}) async {
      if (settle) { await tester.pumpAndSettle(); } else { await tester.pump(const Duration(milliseconds: 100)); }
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
    tester.view.physicalSize = const Size(390, 844);
    final pair = _Pair(), changes = _Changes();
    await tester.pumpWidget(RepaintBoundary(key: boundary, child: MaterialApp(debugShowCheckedModeBanner: false,
      locale: const Locale('vi'), supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates, theme: companionTheme(fontFamily: 'Roboto'),
      home: Scaffold(body: CompanionAccessPanel(connection: LanConnection('https://192.168.1.20:8743/api/staff/v1', 'b' * 64),
        client: pair, store: store, readClient: client, workflowClient: client, changeClient: changes, onAccess: (_) {})))));
    await tester.pumpAndSettle(); await billTap(tester, 'mobile-tab-invoices'); await billTap(tester, 'bill-list-bill-a');
    await billTap(tester, 'bill-edit-line-service'); await tester.enterText(find.byKey(const Key('bill-line-quantity')), '3');
    FocusManager.instance.primaryFocus?.unfocus(); await tester.pumpAndSettle();
    pair.offline = true; await tester.pump(const Duration(seconds: 5)); await capture('22-connection-offline-draft');
    pair.offline = false; changes.delayed = Completer<LanChangeSnapshot>();
    await tester.tap(find.byKey(const Key('mobile-reconnect'))); await tester.pump(); await capture('23-connection-resync', settle: false);
    changes.delayed!.complete(const LanChangeSnapshot('epoch-restarted', 1, reset: true, changed: true));
    await tester.pumpAndSettle(); await capture('24-connection-stale-editor'); await tester.pumpWidget(const SizedBox());
  }, skip: !Platform.isLinux || Platform.environment['GITHUB_ACTIONS'] != 'true');
}
