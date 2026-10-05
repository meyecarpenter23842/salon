
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/models/catalog_option.dart';
import 'package:salonmanager/core/providers/catalog_options_providers.dart';
import 'package:salonmanager/core/repositories/catalog_options_repository.dart';
import 'package:salonmanager/shared/widgets/catalog_management_tabs.dart';

void main() {
  testWidgets('settings tabs create rename archive and restore shared catalog', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeCatalogOptionsRepository();
    await tester.pumpWidget(ProviderScope(overrides: [
      catalogOptionsRepositoryProvider.overrideWithValue(repository),
    ], child: const MaterialApp(home: Scaffold(body: CatalogManagementTabs(
      kinds: [CatalogOptionKind.productUnit], child: Text('Danh sách sản phẩm')))))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thiết lập'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thêm đơn vị tính'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Bộ');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(await repository.fetchOptionNames(CatalogOptionKind.productUnit), contains('Bộ'));
    final row = find.ancestor(of: find.text('Bộ'), matching: find.byType(ListTile));
    await tester.ensureVisible(row);
    await tester.tap(find.descendant(of: row, matching: find.byTooltip('Đổi tên')));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Bộ sản phẩm');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    final renamed = find.ancestor(of: find.text('Bộ sản phẩm'), matching: find.byType(ListTile));
    await tester.ensureVisible(renamed);
    await tester.tap(find.descendant(of: renamed, matching: find.byTooltip('Ngừng sử dụng')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(await repository.fetchOptionNames(CatalogOptionKind.productUnit), isNot(contains('Bộ sản phẩm')));
    await tester.tap(find.text('Hiện mục ngừng sử dụng'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(renamed);
    await tester.tap(find.descendant(of: renamed, matching: find.byTooltip('Bật lại')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(await repository.fetchOptionNames(CatalogOptionKind.productUnit), contains('Bộ sản phẩm'));
    expect(tester.takeException(), isNull);
  });
}
