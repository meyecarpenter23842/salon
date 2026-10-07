import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
import 'package:salonmanager/core/models/employee_upsert_input.dart';
import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/providers/repository_providers.dart';
import 'package:salonmanager/core/repositories/fake_repositories.dart';
import 'package:salonmanager/core/theme/app_theme.dart';
import 'package:salonmanager/core/theme/salon_theme_template.dart';
import 'package:salonmanager/features/employees/presentation/pages/employees_page.dart';

class _Employees extends FakeEmployeesRepository {
  _Employees() : super(FakeSalonDataSource());
  EmployeeUpsertInput? saved;
  final employee = <String, Object?>{
    'id': 'legacy',
    'name': 'Nguyễn Mai',
    'role': 'Chuyên viên riêng',
    'status': 'Đang làm việc',
    'initials': 'NM',
    'phone': '0900000000',
    'shift': 'Ca sáng',
    'commission': '10%',
    'specialty': 'Tóc',
    'rating': '5',
    'note': 'Cũ',
    'servicesDone': 0,
    'monthlyRevenue': '0 đ',
    'todaySchedule': '',
  };
  @override
  Future<List<Map<String, Object?>>> fetchEmployeesView() async => [employee];
  @override
  Future<Map<String, Object?>> saveEmployee(
    EmployeeUpsertInput input, {
    String? existingId,
  }) async {
    saved = input;
    employee['name'] = input.fullName;
    employee['role'] = input.role;
    return employee;
  }
}

void main() {
  for (final size in [const Size(1024, 768), const Size(1366, 768)]) {
    testWidgets(
      'title settings and legacy editor preserve custom role at ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey(), repository = _Employees();
        if (Platform.isLinux) {
          final font = await tester.runAsync(
            () => File(
              '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
            ).readAsBytes(),
          );
          final icons = await tester.runAsync(
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
            )..addFont(Future.value(ByteData.sublistView(icons!)))).load,
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
            final dir = Directory('build/mobile-ui-review')
              ..createSync(recursive: true);
            await File(
              '${dir.path}/$name.png',
            ).writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
        }

        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: ProviderScope(
              overrides: [
                appDataBackendProvider.overrideWithValue(AppDataBackend.fake),
                employeesRepositoryProvider.overrideWithValue(repository),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.build(SalonThemeTemplate.salonNoirGold),
                home: const Scaffold(
                  body: Padding(
                    padding: EdgeInsets.all(16),
                    child: EmployeesPage(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Chức danh'), findsOneWidget);
        expect(find.textContaining('Chuyên viên riêng'), findsWidgets);
        await tester.tap(find.byTooltip('Sửa hồ sơ'));
        await tester.pumpAndSettle();
        expect(find.text('Sửa hồ sơ nhân viên'), findsOneWidget);
        expect(find.text('Chuyên viên riêng'), findsWidgets);
        expect(tester.takeException(), isNull);
        await capture('34-employee-title-editor-${size.width.toInt()}');
        await tester.tap(find.text('Lưu hồ sơ'));
        await tester.pumpAndSettle();
        expect(repository.saved!.role, 'Chuyên viên riêng');
        await tester.tap(find.text('Thiết lập'));
        await tester.pumpAndSettle();
        expect(find.text('Chức danh nhân viên'), findsOneWidget);
        expect(find.text('Thêm chức danh'), findsOneWidget);
        await capture('33-employee-titles-${size.width.toInt()}');
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Thêm chức danh'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, 'Thợ spa');
        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();
        expect(find.text('Thợ spa'), findsOneWidget);
        await tester.ensureVisible(find.byTooltip('Ngừng sử dụng').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Ngừng sử dụng').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Xác nhận'));
        await tester.pumpAndSettle();
        expect(find.text('Thợ spa'), findsNothing);
        await tester.tap(find.text('Hiện mục ngừng sử dụng'));
        await tester.pumpAndSettle();
        expect(find.text('Thợ spa'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

