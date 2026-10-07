import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/stock_document.dart';
import 'package:salonmanager/core/repositories/stock_document_repository.dart';
import 'package:salonmanager/core/services/sensitive_action_service.dart';
import 'support/stock_schema_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late SensitiveActionService security;
  late StockDocumentRepository repo;
  StockDocumentInput input(String id, {StockDocumentKind kind = StockDocumentKind.receipt,
    int quantity = 3, List<StockDocumentLineInput>? lines, int? revision}) => StockDocumentInput(
      id: id, kind: kind, date: DateTime(2026, 10, 6), preparedBy: 'Chủ salon',
      supplierId: kind == StockDocumentKind.receipt ? 'supplier' : null, note: 'Kiểm tra',
      expectedRevision: revision, lines: lines ?? [StockDocumentLineInput(productId: 'p1',
        quantity: quantity, unitCost: kind == StockDocumentKind.receipt ? 15000 : 0)]);

  setUp(() async {
    await SalonDatabase.instance.close();
    db = await SalonDatabase.instance.database;
    security = SensitiveActionService(SalonDatabase.instance);
    repo = StockDocumentRepository(SalonDatabase.instance, security);
    for (final id in ['p1', 'p2']) {
      await db.insert('retail_products', {'id': id, 'name': 'Dầu $id', 'brand': '', 'volume_label': '',
        'unit_name': 'Chai', 'product_type': 'Gội', 'sale_price': 100000,
        'created_at': '2026-10-06', 'updated_at': '2026-10-06'});
    }
    await repo.saveSupplier(const StockSupplier(id: 'supplier', name: 'NCC ban đầu', phone: '0901234567'));
  });
  tearDown(() async => SalonDatabase.instance.close());

  test('draft and creation replay never change stock, totals and snapshots stay historical', () async {
    final draft = await repo.saveDraft(input('draft'));
    expect(draft.number, startsWith('PN-'));
    expect(draft.total, 45000);
    expect((await repo.saveDraft(input('draft'))).number, draft.number);
    expect(await db.query('inventory_stock'), isEmpty);
    expect(await db.query('inventory_movements'), isEmpty);
    final posted = await repo.post(draft.id, expectedRevision: draft.revision);
    await repo.post(draft.id, expectedRevision: draft.revision);
    expect(posted.isPosted, isTrue);
    expect((await db.query('inventory_stock')).single['stock_on_hand'], 3);
    expect(await db.query('inventory_movements'), hasLength(1));
    await db.update('retail_products', {'name': 'Tên mới', 'sale_price': 120000}, where: 'id = ?', whereArgs: ['p1']);
    await repo.saveSupplier(const StockSupplier(id: 'supplier', name: 'NCC đổi tên'));
    final history = await repo.document(draft.id);
    expect(history.lines.single.productName, 'Dầu p1');
    expect(history.lines.single.unitName, 'Chai');
    expect(history.supplierName, 'NCC ban đầu');
    expect(history.total, 45000);
    await expectLater(db.update('stock_documents', {'note': 'overwrite'}, where: 'id = ?', whereArgs: [draft.id]), throwsA(isA<DatabaseException>()));
    await expectLater(db.delete('stock_document_lines', where: 'document_id = ?', whereArgs: [draft.id]), throwsA(isA<DatabaseException>()));
    await expectLater(db.delete('inventory_movements'), throwsA(isA<DatabaseException>()));
  });

  test('posting all lines and atomic audit roll back together on a movement failure', () async {
    final draft = await repo.saveDraft(input('rollback', lines: const [
      StockDocumentLineInput(productId: 'p1', quantity: 2, unitCost: 100),
      StockDocumentLineInput(productId: 'p2', quantity: 4, unitCost: 200)]));
    await db.execute("CREATE TRIGGER fail_second BEFORE INSERT ON inventory_movements WHEN NEW.product_id = 'p2' BEGIN SELECT RAISE(ABORT, 'forced'); END");
    await expectLater(repo.post(draft.id, expectedRevision: draft.revision), throwsA(isA<DatabaseException>()));
    expect(await db.query('inventory_stock'), isEmpty);
    expect(await db.query('inventory_movements'), isEmpty);
    expect((await repo.document(draft.id)).isDraft, isTrue);
    expect(await db.query('audit_events', where: "action = 'stock_document_post'"), isEmpty);
    await db.execute('DROP TRIGGER fail_second');
    await repo.post(draft.id, expectedRevision: draft.revision);
    expect(await db.query('inventory_movements'), hasLength(2));
    expect((await repo.document(draft.id)).total, 1000);
  });

  test('partial negative replenishment and cancellation reverse once against current stock', () async {
    await db.insert('inventory_stock', {'product_id': 'p1', 'stock_on_hand': -5, 'updated_at': '2026-10-06'});
    final draft = await repo.saveDraft(input('negative'));
    final posted = await repo.post(draft.id, expectedRevision: draft.revision);
    expect((await db.query('inventory_stock')).single['stock_on_hand'], -2);
    await db.update('inventory_stock', {'stock_on_hand': -4});
    await expectLater(repo.cancel(draft.id, expectedRevision: posted.revision, reason: ''), throwsArgumentError);
    await repo.cancel(draft.id, expectedRevision: posted.revision, reason: 'Sai chứng từ');
    await repo.cancel(draft.id, expectedRevision: posted.revision, reason: 'Sai chứng từ');
    expect((await db.query('inventory_stock')).single['stock_on_hand'], -7);
    final moves = await db.query('inventory_movements');
    expect(moves, hasLength(2));
    expect(moves.last['quantity_delta'], -3);
    expect(moves.last['document_id'], draft.id);
    expect(moves.last['document_line_id'], draft.lines.single.id);
    expect(await db.query('audit_events', where: "action = 'stock_document_cancel'"), hasLength(1));
  });

  test('two concurrent post requests apply once and stale draft revisions cannot overwrite', () async {
    final draft = await repo.saveDraft(input('parallel'));
    final updated = await repo.saveDraft(input('parallel', quantity: 4, revision: draft.revision));
    await expectLater(repo.saveDraft(input('parallel', quantity: 6, revision: draft.revision)), throwsStateError);
    await Future.wait([repo.post(draft.id, expectedRevision: updated.revision), repo.post(draft.id, expectedRevision: updated.revision)]);
    expect((await db.query('inventory_stock')).single['stock_on_hand'], 4);
    expect(await db.query('inventory_movements'), hasLength(1));
  });

  test('Owner guard denies domain writes and audit is recorded with authorized actor', () async {
    await security.configureOwnerPin('2468', actorName: 'Chủ Hà');
    security.lockOwnerSession();
    await expectLater(repo.saveDraft(input('owner')), throwsStateError);
    expect(await db.query('stock_documents'), isEmpty);
    expect(await db.query('audit_events', where: "result = 'denied'"), hasLength(1));
    expect(await security.unlockOwner('2468'), isTrue);
    final draft = await repo.saveDraft(input('owner'));
    final posted = await repo.post(draft.id, expectedRevision: draft.revision);
    expect(posted.postedBy, 'Chủ Hà');
    security.lockOwnerSession();
    await expectLater(repo.cancel(draft.id, expectedRevision: posted.revision, reason: 'Denied'), throwsStateError);
    expect((await repo.document(draft.id)).isPosted, isTrue);
  });

  test('manual issue permits negative; physical count and reversal use recorded deltas', () async {
    final issue = await repo.saveDraft(input('issue', kind: StockDocumentKind.issue, quantity: 5));
    await repo.post(issue.id, expectedRevision: issue.revision);
    expect((await db.query('inventory_stock')).single['stock_on_hand'], -5);
    final adjustment = await repo.saveDraft(input('count', kind: StockDocumentKind.adjustment, quantity: 2));
    final posted = await repo.post(adjustment.id, expectedRevision: adjustment.revision);
    expect((await db.query('inventory_stock')).single['stock_on_hand'], 2);
    await repo.cancel(posted.id, expectedRevision: posted.revision, reason: 'Đếm sai');
    expect((await db.query('inventory_stock')).single['stock_on_hand'], -5);
    await expectLater(repo.saveDraft(input('bad-count', kind: StockDocumentKind.adjustment, quantity: -1)), throwsArgumentError);
    await expectLater(repo.saveDraft(input('bad-receipt', quantity: 0)), throwsArgumentError);
    await expectLater(repo.saveDraft(input('duplicates', lines: const [
      StockDocumentLineInput(productId: 'p1', quantity: 1), StockDocumentLineInput(productId: 'p1', quantity: 2)])), throwsArgumentError);
  });

  test('inactive suppliers, changed units and products are rejected before posting', () async {
    final draft = await repo.saveDraft(input('inactive'));
    await repo.saveSupplier(const StockSupplier(id: 'supplier', name: 'NCC ban đầu', isActive: false));
    await expectLater(repo.post(draft.id, expectedRevision: draft.revision), throwsStateError);
    expect((await repo.document(draft.id)).isDraft, isTrue);
    await repo.saveSupplier(const StockSupplier(id: 'supplier', name: 'NCC ban đầu'));
    await db.update('retail_products', {'unit_name': 'Hộp'}, where: 'id = ?', whereArgs: ['p1']);
    await expectLater(repo.post(draft.id, expectedRevision: draft.revision), throwsStateError);
    await db.update('retail_products', {'unit_name': 'Chai', 'is_active': 0}, where: 'id = ?', whereArgs: ['p1']);
    await expectLater(repo.post(draft.id, expectedRevision: draft.revision), throwsStateError);
    expect(await db.query('inventory_movements'), isEmpty);
  });

  test('schema 19 migration preserves legacy stock movement values without invented supplier or price', () async {
    await db.insert('inventory_stock', {'product_id': 'p1', 'stock_on_hand': -7, 'updated_at': '2026-10-06'});
    await db.insert('inventory_movements', {'id': 'legacy', 'product_id': 'p1', 'movement_type': 'receive',
      'quantity_delta': 3, 'stock_before': -10, 'stock_after': -7, 'note': 'Old', 'created_at': '2026-10-06'});
    await removeStockDocumentSchema(db);
    final old = jsonEncode(await db.query('inventory_movements'));
    await db.setVersion(19);
    await SalonDatabase.instance.close();
    final upgraded = await SalonDatabase.instance.initialize(preserveExistingTestDatabase: true);
    expect(await upgraded.getVersion(), 22);
    final row = {...(await upgraded.query('inventory_movements')).single};
    expect(row['source'], 'legacy');
    expect(row['document_id'], isNull);
    row.remove('source'); row.remove('document_id'); row.remove('document_line_id');
    expect(jsonEncode([row]), old);
    expect((await upgraded.query('inventory_stock')).single['stock_on_hand'], -7);
    expect(await upgraded.query('stock_documents'), isEmpty);
    expect(await upgraded.query('stock_suppliers'), isEmpty);
  });
}
