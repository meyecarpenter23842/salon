import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/lan/lan_write_contract.dart';
import 'package:salonmanager/features/companion/companion_command_controller.dart';
import 'package:salonmanager/features/companion/companion_mobile_bill.dart';
import 'package:salonmanager/features/companion/companion_theme.dart';
import 'package:salonmanager/features/companion/companion_workspace.dart';
import 'companion_mobile_bill_test.dart' as actions;
import 'support/mobile_bill_fixture.dart';

/// Exact-head CI engine images for review, not physical Android verification.
void main() {
  testWidgets('CI billing renders: lists, bill, line, split, review, receipt, large text and uncertainty', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final bytes = await tester.runAsync(() => File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf').readAsBytes());
    final iconBytes = await tester.runAsync(() => File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes());
    final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(iconBytes!)));
    final text = FontLoader('SalonPreview')..addFont(Future.value(ByteData.sublistView(bytes!)));
    await tester.runAsync(icons.load); await tester.runAsync(text.load);
    final output = Directory('build/mobile-ui-review');
    await tester.runAsync(() => output.create(recursive: true));
    final boundary = GlobalKey();
    CompanionCommandController? commands;
    late BillTestClient client;
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
    Future<void> mount({bool workspace = false, double scale = 1, bool uncertain = false}) async {
      await tester.pumpWidget(const SizedBox()); commands?.dispose();
      final store = BillTestStore(); client = BillTestClient()..loseCheckout = uncertain;
      commands = CompanionCommandController(connection: actions.billConnection, client: client,
        store: store, credential: store.value, onCredential: (_) {});
      await tester.pumpWidget(RepaintBoundary(key: boundary, child: MaterialApp(debugShowCheckedModeBanner: false,
        locale: const Locale('vi'), supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates, theme: companionTheme(fontFamily: 'SalonPreview'),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: workspace ? CompanionWorkspace(connection: actions.billConnection, readClient: client, client: client,
          commands: commands!, role: PhoneWriteRole.owner, onDenied: () {})
          : CompanionMobileBill(connection: actions.billConnection, readClient: client, client: client,
            commands: commands!, role: PhoneWriteRole.owner, onDenied: () {}, id: 'bill-a'))));
      await tester.pumpAndSettle();
    }
    await mount(workspace: true); await actions.billTap(tester, 'mobile-tab-invoices'); await capture('09-bills-active');
    await actions.billTap(tester, 'bill-list-paid'); await capture('10-invoices-paid');
    await mount(); await capture('11-bill');
    await actions.billTap(tester, 'bill-edit-line-service'); await capture('12-bill-line-editor');
    await tester.tap(find.byType(BackButton)); await tester.pumpAndSettle();
    await actions.billTap(tester, 'bill-edit-payment'); await actions.billTap(tester, 'bill-payment-split');
    await tester.enterText(find.byKey(const Key('bill-payment-Tiền mặt')), '50000');
    await tester.enterText(find.byKey(const Key('bill-payment-Chuyển khoản')), '100000');
    FocusManager.instance.primaryFocus?.unfocus(); await tester.pumpAndSettle(); await capture('13-bill-split-payment');
    await actions.billTap(tester, 'bill-payment-done'); await actions.billTap(tester, 'bill-checkout'); await capture('14-bill-checkout-review');
    await actions.billTap(tester, 'bill-confirm-checkout'); await capture('15-bill-receipt');
    await mount(scale: 1.5); await capture('16-bill-large-text');
    await mount(uncertain: true); await actions.billTap(tester, 'bill-checkout'); await actions.billTap(tester, 'bill-confirm-checkout');
    await capture('17-bill-uncertain');
    await tester.pumpWidget(const SizedBox()); commands?.dispose();
  }, skip: !Platform.isLinux || Platform.environment['GITHUB_ACTIONS'] != 'true');
}
