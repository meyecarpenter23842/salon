import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/stock_document.dart';
import 'package:salonmanager/core/providers/stock_document_providers.dart';
import 'package:salonmanager/core/repositories/stock_document_repository.dart';
import 'package:salonmanager/core/services/sensitive_action_service.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';
import 'package:salonmanager/features/inventory/presentation/pages/inventory_page.dart';
import 'package:salonmanager/features/inventory/presentation/pages/stock_documents_page.dart';
import 'package:salonmanager/features/inventory/presentation/pages/stock_document_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StockDocumentRepository repo;
  setUp(() async {
    await SalonDatabase.instance.close();
    SharedPreferences.setMockInitialValues({});
    await LocalSettingsStore.instance.initialize();
    final db = await SalonDatabase.instance.database;
    await db.insert('retail_products', {'id': 'p', 'name': 'Dầu gội Việt', 'brand': '', 'volume_label': '',
      'unit_name': 'Chai', 'product_type': 'Gội', 'sale_price': 100000, 'created_at': '2026-10-06', 'updated_at': '2026-10-06'});
    repo = StockDocumentRepository(SalonDatabase.instance, SensitiveActionService(SalonDatabase.instance));
  });
  tearDown(() async => SalonDatabase.instance.close());
  StockDocumentInput input(String id) => StockDocumentInput(id: id, kind: StockDocumentKind.receipt,
    date: DateTime(2026, 10, 6), preparedBy: 'Chủ Việt', externalReference: 'HD-123', note: 'Nhập mới',
    lines: const [StockDocumentLineInput(productId: 'p', quantity: 3, unitCost: 12000)]);

  test('Unicode PDF uses frozen document content and produces an A4 print artifact', () async {
    final doc = await repo.saveDraft(input('print'));
    final bytes = await buildStockDocumentPdf(doc);
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(1000));
    final db = await SalonDatabase.instance.database;
    await repo.post(doc.id, expectedRevision: doc.revision);
    await db.update('retail_products', {'name': 'Tên đã thay đổi'});
    expect((await repo.document(doc.id)).lines.single.productName, 'Dầu gội Việt');
  });

  test('movement lookup covers whole document and history pagination retains legacy source', () async {
    final doc = await repo.saveDraft(input('history'));
    await repo.post(doc.id, expectedRevision: doc.revision);
    final db = await SalonDatabase.instance.database;
    final batch = db.batch();
    for (var i = 0; i < 155; i++) {
      batch.insert('inventory_movements', {'id': 'legacy-$i', 'product_id': 'p', 'movement_type': 'receive',
        'quantity_delta': 1, 'stock_before': i, 'stock_after': i + 1, 'note': 'Old', 'created_at': '2026-10-06'});
    }
    await batch.commit(noResult: true);
    expect(await repo.movementHistory(documentId: doc.id, limit: 500), hasLength(1));
    final legacy = await repo.movementHistory(source: 'legacy', from: DateTime(2026,10,6), to: DateTime(2026,10,6));
    expect(legacy, hasLength(50));
    expect(legacy.first.sourceLabel, 'Lịch sử cũ (legacy)');
    expect(await repo.movementHistory(source: 'legacy', offset: 150), hasLength(5));
    expect(await repo.movementHistory(query: '%'), isEmpty);
    expect((await repo.movementHistory(query: doc.number)).single.documentId, doc.id);
  });

  test('document search and status filters precede page materialization', () async {
    for (var i = 0; i < 5; i++) { await repo.saveDraft(input('page-$i')); }
    expect(await repo.documents(limit: 2), hasLength(2));
    expect(await repo.documents(offset: 4, limit: 2), hasLength(1));
    expect(await repo.documents(query: 'CHỦ VIỆT', limit: 2), hasLength(2));
    expect(await repo.documents(status: 'posted'), isEmpty);
    final first = (await repo.documents()).first;
    await repo.post(first.id, expectedRevision: first.revision);
    expect((await repo.documents(status: 'posted')).single.id, first.id);
    await expectLater(repo.post(first.id, expectedRevision: first.revision + 10), throwsStateError);
    expect(await repo.documents(excludeReceipts: true), isEmpty);
  });

  test('cancelling a draft records the reason without stock or movements', () async {
    final draft = await repo.saveDraft(input('cancel-draft'));
    final cancelled = await repo.cancel(draft.id, expectedRevision: draft.revision, reason: 'Không nhập nữa');
    expect(cancelled.status, 'cancelled');
    expect(cancelled.cancellationReason, 'Không nhập nữa');
    await repo.cancel(draft.id, expectedRevision: draft.revision, reason: 'Không nhập nữa');
    await expectLater(repo.post(draft.id, expectedRevision: cancelled.revision), throwsStateError);
    expect(await repo.movementHistory(documentId: draft.id), isEmpty);
    expect(await (await SalonDatabase.instance.database).query('inventory_stock'), isEmpty);
  });

  test('cancel rollback preserves posted document and all original movements when a reversal fails', () async {
    final db = await SalonDatabase.instance.database;
    await db.insert('retail_products', {'id': 'p2', 'name': 'Dầu thứ hai', 'brand': '', 'volume_label': '',
      'unit_name': 'Chai', 'product_type': 'Gội', 'sale_price': 100000, 'created_at': '2026-10-06', 'updated_at': '2026-10-06'});
    final draft = await repo.saveDraft(StockDocumentInput(id: 'cancel-atomic', kind: StockDocumentKind.receipt,
      date: DateTime(2026,10,6), preparedBy: 'Owner', lines: const [
        StockDocumentLineInput(productId: 'p', quantity: 2, unitCost: 10000),
        StockDocumentLineInput(productId: 'p2', quantity: 4, unitCost: 15000)]));
    final posted = await repo.post(draft.id, expectedRevision: draft.revision);
    final before = jsonEncode(await db.query('inventory_stock', orderBy: 'product_id'));
    await db.execute("CREATE TRIGGER fail_reverse BEFORE INSERT ON inventory_movements WHEN NEW.product_id = 'p2' AND NEW.movement_type = 'reverse' BEGIN SELECT RAISE(ABORT, 'forced reversal'); END");
    await expectLater(repo.cancel(posted.id, expectedRevision: posted.revision, reason: 'Sai phiếu'), throwsA(anything));
    expect((await repo.document(posted.id)).isPosted, isTrue);
    expect(jsonEncode(await db.query('inventory_stock', orderBy: 'product_id')), before);
    expect(await repo.movementHistory(documentId: posted.id), hasLength(2));
    expect(await db.query('audit_events', where: "action = 'stock_document_cancel'"), isEmpty);
    await db.execute('DROP TRIGGER fail_reverse');
    await repo.cancel(posted.id, expectedRevision: posted.revision, reason: 'Sai phiếu');
    expect((await repo.movementHistory(documentId: posted.id)).where((m) => m.movementType == 'reverse'), hasLength(2));
  });

  testWidgets('five inventory tabs fit small desktop and expose draft, confirmation and supplier setup', (tester) async {
    tester.view.physicalSize = const Size(1024,768); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
    final draft = await repo.saveDraft(input('ui'));
    await tester.pumpWidget(ProviderScope(overrides: [stockDocumentRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: Scaffold(body: Padding(padding: EdgeInsets.all(18), child: InventoryPage())))));
    await _settle(tester);
    expect(find.text('Tồn kho'), findsOneWidget);
    await tester.tap(find.text('Phiếu nhập')); await _waitFor(tester, find.byKey(const Key('stock-document-ui')));
    expect(find.byKey(const Key('stock-new-receipt')), findsOneWidget);
    await tester.tap(find.byKey(const Key('stock-document-ui'))); await _waitFor(tester, find.byKey(const Key('stock-post')));
    expect(find.byKey(const Key('stock-post')), findsOneWidget);
    expect(find.text('Nháp — chưa thay đổi tồn kho.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('stock-post'))); await _settle(tester);
    await tester.tap(find.text('Ghi kho')); await _waitFor(tester, find.text('Bút toán đối chiếu chứng từ'));
    expect((await repo.document(draft.id)).isPosted, isTrue);
    expect(find.byKey(const Key('stock-post')), findsNothing);
    expect(find.text('Bút toán đối chiếu chứng từ'), findsOneWidget);
    await tester.tap(find.text('Đóng')); await _settle(tester);
    await tester.tap(find.text('Thiết lập')); await _settle(tester);
    await tester.tap(find.text('Nhà cung cấp')); await _settle(tester);
    expect(find.byKey(const Key('stock-new-supplier')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('document editor saves a draft with quantity cost and totals without changing stock', (tester) async {
    tester.view.physicalSize = const Size(1024,768); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
    await tester.pumpWidget(ProviderScope(overrides: [stockDocumentRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: Scaffold(body: Builder(builder: (context) => Consumer(builder: (context, ref, _) =>
        FilledButton(onPressed: () => openStockDocumentEditor(context, ref, kind: StockDocumentKind.receipt),
          child: const Text('Open'))))))));
    await tester.tap(find.text('Open')); await _waitFor(tester, find.byKey(const Key('stock-save-draft')));
    await tester.ensureVisible(find.text('Sản phẩm dòng 1')); await tester.tap(find.text('Sản phẩm dòng 1')); await _settle(tester);
    await tester.tap(find.text('Dầu gội Việt • Chai').last); await _settle(tester);
    final quantity = find.widgetWithText(TextFormField, 'Số lượng');
    await tester.ensureVisible(quantity); await tester.enterText(quantity, '4');
    final cost = find.widgetWithText(TextFormField, 'Giá nhập / đơn vị (đ)');
    await tester.enterText(cost, '10000');
    await tester.tap(find.byKey(const Key('stock-save-draft'))); await _waitFor(tester, find.text('Open'), absent: find.byKey(const Key('stock-save-draft')));
    final saved = (await repo.documents()).single;
    expect(saved.isDraft, isTrue); expect(saved.total, 40000);
    expect(await (await SalonDatabase.instance.database).query('inventory_stock'), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

Future<void> _waitFor(WidgetTester tester, Finder finder, {Finder? absent}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  bool ready() => finder.evaluate().isNotEmpty && (absent == null || absent.evaluate().isEmpty);
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(ready(), isTrue, reason: 'Stock document operation did not complete');
  await _settle(tester);
}
