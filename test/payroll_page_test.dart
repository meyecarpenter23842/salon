import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/payroll.dart';
import 'package:salonmanager/core/providers/repository_providers.dart';
import 'package:salonmanager/core/repositories/sqlite_payroll_repository.dart';
import 'package:salonmanager/core/services/sensitive_action_service.dart';
import 'package:salonmanager/features/employees/presentation/pages/payroll_page.dart';

class _Security extends SensitiveActionService {
  _Security() : super(SalonDatabase.instance);
  bool active = true;
  @override
  bool get isOwnerSessionActive => active;
  @override
  Future<bool> isProtectionConfigured() async => true;
  @override
  void lockOwnerSession() {
    active = false;
  }
}

class _Repository extends SqlitePayrollRepository {
  _Repository(super.database, super.security);
  final run = PayrollView(
    row: {
      'id': 'pay',
      'employee_id': 'emp',
      'employee_name': 'Nguyễn Thị Mai',
      'period': '2026-09',
      'revision': 2,
      'state': 'closed',
      'closed_by': 'Chủ salon',
      'closed_at': '2026-10-01',
    },
    snapshot: {
      'policy': {
        'mode': 'monthly_work',
        'rate': 8000000,
        'standard_minutes': 12000,
        'revision': 1,
        'effective_period': '2026-09',
      },
      'base': 7200000,
      'extras': 200000,
      'net': 7400000,
      'worked_seconds': 648000,
      'unresolved': 0,
      'attendance': [],
    },
    items: [],
    payouts: [
      {
        'amount': 2000000,
        'kind': 'advance',
        'method': 'transfer',
        'reference': 'VCB-ABC',
        'actor': 'Chủ salon',
        'created_at': '2026-09-20',
        'note': 'Tạm ứng',
      },
    ],
    policyHistory: [],
    sourceChanged: false,
    commissionBalance: 1000000,
  );
  @override
  Future<PayrollWorkspace> fetch(String period) async => PayrollWorkspace(
    [
      {'id': 'emp', 'full_name': 'Nguyễn Thị Mai'},
    ],
    [run.policy..['employee_id'] = 'emp'],
    [run],
    null,
  );
  @override
  Future<PayrollView> document(String id) async => run;
  @override
  Future<List<Map<String, Object?>>> history(String id) async => [];
}

void main() {
  for (final size in [const Size(800, 600), const Size(1366, 768)]) {
    testWidgets(
      'payroll payslip, salary setup and payment dialog fit ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey(), security = _Security();
        if (Platform.isLinux) {
          final font = await tester.runAsync(
            () => File(
              '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
            ).readAsBytes(),
          );
          final icon = await tester.runAsync(
            () => File(
              '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes(),
          );
          await tester.runAsync(
            (FontLoader(
              'Roboto',
            )..addFont(Future.value(ByteData.sublistView(font!)))).load,
          );
          await tester.runAsync(
            (FontLoader(
              'MaterialIcons',
            )..addFont(Future.value(ByteData.sublistView(icon!)))).load,
          );
        }
        Future<void> capture(String name) async {
          if (!Platform.isLinux) {
            return;
          }
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final output = Directory('build/mobile-ui-review')
              ..createSync(recursive: true);
            await File(
              '${output.path}/$name.png',
            ).writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
        }

        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: ProviderScope(
              overrides: [
                payrollRepositoryProvider.overrideWithValue(
                  _Repository(SalonDatabase.instance, security),
                ),
                sensitiveActionServiceProvider.overrideWithValue(security),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(fontFamily: 'Roboto'),
                home: const PayrollPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Nguyễn Thị Mai'), findsOneWidget);
        expect(find.text('Ghi trả lương'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture('30-payroll-${size.width.toInt()}');
        await tester.tap(find.text('Thiết lập lương'));
        await tester.pumpAndSettle();
        expect(find.text('Thiết lập lương nhân viên'), findsOneWidget);
        await capture('31-payroll-policy-${size.width.toInt()}');
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Hủy'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ghi trả lương'));
        await tester.pumpAndSettle();
        expect(
          find.text('Đã chi tiền / đã chuyển khoản cho nhân viên'),
          findsOneWidget,
        );
        await capture('32-payroll-payment-${size.width.toInt()}');
        expect(tester.takeException(), isNull);
        security.active = false;
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(find.text('Bảng lương cần quyền chủ salon'), findsOneWidget);
        expect(find.text('Nguyễn Thị Mai'), findsNothing);
        expect(
          find.text('Đã chi tiền / đã chuyển khoản cho nhân viên'),
          findsNothing,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('background lifecycle masks payroll and policy dialog', (
    tester,
  ) async {
    final security = _Security();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          payrollRepositoryProvider.overrideWithValue(
            _Repository(SalonDatabase.instance, security),
          ),
          sensitiveActionServiceProvider.overrideWithValue(security),
        ],
        child: const MaterialApp(home: PayrollPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thiết lập lương'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.text('Thiết lập lương nhân viên'), findsNothing);
    expect(find.text('Nguyễn Thị Mai'), findsNothing);
    expect(security.active, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

