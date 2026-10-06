import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/lan/lan_health_client.dart';
import 'package:salonmanager/core/lan/lan_read_client.dart';
import 'package:salonmanager/core/lan/lan_read_models.dart';
import 'package:salonmanager/core/lan/lan_write_contract.dart';
import 'package:salonmanager/features/companion/companion_command_controller.dart';
import 'package:salonmanager/features/companion/companion_workspace.dart';
import 'companion_mobile_navigation_test.dart' as fixture;

/// CI engine renders for review, never evidence of a physical Android device.
class _PreviewReader implements SalonReadClient {
  @override Future<SalonReadPage> read(LanConnection c, String t, SalonReadQuery q) async {
    final customer = q.kind == SalonReadKind.customers;
    return SalonReadPage(salonDate: '2026-10-06', records: List.generate(q.id == null ? 4 : 1, (i) =>
      SalonReadRecord(id: q.id ?? '${q.kind.name}-$i',
        title: customer ? ['Nguyễn Ngọc Lan', 'Trần Minh Anh', 'Lê Thanh Hà', 'Phạm Hoàng Yến'][i] : '${9 + i}:00 · Nguyễn Ngọc Lan',
        subtitle: customer ? '0901 234 567 · Member' : 'Gội dưỡng + Chăm sóc tóc · ${i == 0 ? 'Đã đến' : 'Đã đặt'}',
        fields: q.id == null ? {} : {'Điện thoại': '0901 234 567', 'Email': 'lan@example.com',
          'Hạng khách': 'Member', 'Dịch vụ yêu thích': 'Gội dưỡng', 'Hồ sơ tóc': 'Tóc dài, da đầu nhạy cảm',
          'Ghi chú': 'Thích lịch hẹn buổi sáng'})));
  }
}
void main() {
  testWidgets('CI mobile renders: timeline, customers, profile, edit, pickers, offline and large text', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final font = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    final bytes = await tester.runAsync(font.readAsBytes);
    final loader = FontLoader('SalonPreview')..addFont(Future.value(ByteData.sublistView(bytes!)));
    await loader.load();
    final output = Directory('build/mobile-ui-review');
    await tester.runAsync(() => output.create(recursive: true));
    final boundary = GlobalKey();
    final store = fixture.MobileTestStore(), client = fixture.MobileTestClient();
    final connection = LanConnection('https://192.168.1.20:8743/api/staff/v1', 'b' * 64);
    final commands = CompanionCommandController(connection: connection, client: client, store: store, credential: store.value, onCredential: (_) {});
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${output.path}/$name.png').writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    }
    Future<void> mount({double scale = 1, SalonReadClient? reader}) async {
      await tester.pumpWidget(RepaintBoundary(key: boundary, child: MaterialApp(
        theme: ThemeData(useMaterial3: true, fontFamily: 'SalonPreview', colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff735343)),
          scaffoldBackgroundColor: const Color(0xffFAF7F2),
          inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
          cardTheme: CardThemeData(color: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(48, 48)))),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: CompanionWorkspace(connection: connection, readClient: reader ?? _PreviewReader(), client: client,
          commands: commands, role: PhoneWriteRole.staff, onDenied: () {}))));
      await tester.pumpAndSettle();
    }
    await mount(); await capture('01-today');
    await fixture.tapMobile(tester, 'mobile-tab-customers'); await capture('02-customers');
    await fixture.tapMobile(tester, 'salon-record-customers-0'); await capture('03-customer-profile');
    await fixture.tapMobile(tester, 'salon-edit'); await capture('04-customer-editor');
    await tester.pageBack(); await tester.pumpAndSettle(); await tester.pageBack(); await tester.pumpAndSettle();
    await fixture.tapMobile(tester, 'mobile-tab-appointments'); await fixture.tapMobile(tester, 'write-new-appointment');
    await capture('05-appointment-editor');
    await fixture.tapMobile(tester, 'mobile-select-services'); await capture('06-service-picker');
    await tester.pageBack(); await tester.pumpAndSettle(); await tester.pageBack(); await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox()); await mount(scale: 1.5); await capture('07-today-large-text');
    await tester.pumpWidget(const SizedBox());
    await mount(reader: fixture.MobileTestReader()..fail = true); await capture('08-offline');
    await tester.pumpWidget(const SizedBox()); commands.dispose();
  }, skip: !Platform.isLinux || Platform.environment['GITHUB_ACTIONS'] != 'true');
}
