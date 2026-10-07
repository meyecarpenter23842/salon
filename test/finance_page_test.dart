import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/finance_workspace.dart';
import 'package:salonmanager/core/models/stock_document.dart';
import 'package:salonmanager/core/providers/stock_document_providers.dart';
import 'package:salonmanager/core/repositories/stock_document_repository.dart';
import 'package:salonmanager/core/providers/repository_providers.dart';
import 'package:salonmanager/core/repositories/finance_workspace_repository.dart';
import 'package:salonmanager/core/services/sensitive_action_service.dart';
import 'package:salonmanager/core/theme/app_theme.dart';
import 'package:salonmanager/core/theme/salon_theme_template.dart';
import 'package:salonmanager/features/finance/presentation/finance_page.dart';
import 'package:salonmanager/features/finance/presentation/finance_dialogs.dart';

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

FinanceAccount fixtureAccount(
  FinanceBook book,
  String id, {
  int paid = 400000,
}) => FinanceAccount(
  book,
  {
    'id': id,
    'category_id': 'cat',
    'category_name': 'Thuê mặt bằng',
    'supplier_id': 'ncc',
    'supplier_name': 'Nhà cung cấp Việt',
    'source_type': id == 'opening-b' ? 'stock_receipt' : 'opening',
    'source_number': id == 'opening-b' ? 'PN-000042' : 'Số dư đầu kỳ',
    'source_id': id == 'opening-b' ? 'stock-receipt' : null,
    'source_date': '2026-10-01',
    'expense_date': '2026-10-01',
    'amount': 1000000,
    'reason': 'Nghĩa vụ tháng 10 đã đối chiếu',
    'external_reference': 'HD-10',
    'payee': 'Chủ nhà',
  },
  paid,
  false,
);
FinanceWorkspace fixtureWorkspace() => FinanceWorkspace(
  at: DateTime(2026, 10, 7, 15),
  accounts: [
    fixtureAccount(FinanceBook.expense, 'expense'),
    fixtureAccount(FinanceBook.supplier, 'opening-a'),
    fixtureAccount(FinanceBook.supplier, 'opening-b', paid: 0),
  ],
  proofs: [
    FinanceProof(
      FinanceBook.expense,
      {
        'id': 'paid',
        'kind': 'payment',
        'amount': 400000,
        'method': 'transfer',
        'reference': 'VCB-ABC',
        'actor': 'Owner',
        'note': 'Đã chuyển khoản',
        'created_at': '2026-10-07T10:00:00',
      },
      {'expense': 400000},
    ),
  ],
  categories: [
    {'id': 'cat', 'name': 'Thuê mặt bằng', 'is_active': 1, 'revision': 1},
  ],
  suppliers: [
    {'id': 'ncc', 'name': 'Nhà cung cấp Việt', 'is_active': 0},
  ],
  pending: {},
  events: {FinanceBook.expense: [], FinanceBook.supplier: []},
);

class _Report extends FinanceWorkspaceRepository {
  _Report(super.database, super.security);
  @override
  Future<FinanceWorkspace> fetch() async => fixtureWorkspace();
}
class _SourceRepository extends StockDocumentRepository {
  _SourceRepository(super.database, super.security);
  @override
  Future<StockDocument> document(String id) async => StockDocument(id: id, number: 'PN-000042', kind: StockDocumentKind.receipt,
    date: DateTime(2026, 10, 1), preparedBy: 'Chủ salon', postedBy: 'Chủ salon', status: 'posted', revision: 2,
    supplierName: 'Nhà cung cấp Việt', externalReference: 'NCC-HD-42', note: 'Phiếu nguồn đã ghi kho', lines: const [StockDocumentLine(id: 'line', productId: 'p', productName: 'Dầu gội Việt', unitName: 'Chai', quantity: 10, unitCost: 100000)]);
}

class _DelayedReport extends FinanceWorkspaceRepository {
  _DelayedReport(super.database, super.security, this.result);
  final Future<FinanceWorkspace> result;
  @override
  Future<FinanceWorkspace> fetch() => result;
}

Future<void> fonts(WidgetTester tester) async {
  if (!Platform.isLinux) {
    return;
  }
  final font = await tester.runAsync(
    () => File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf').readAsBytes(),
  );
  final icon = await tester.runAsync(
    () => File(
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes(),
  );
  for (final name in ['Roboto', 'Inter', 'Manrope', 'Playfair Display']) {
    await tester.runAsync(
      (FontLoader(
        name,
      )..addFont(Future.value(ByteData.sublistView(font!)))).load,
    );
  }
  await tester.runAsync(
    (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icon!)))).load,
  );
}

void main() {
  for (final size in [const Size(800, 600), const Size(1366, 768)]) {
    testWidgets(
      'finance ledgers, allocation and receipt fit ${size.width}; expiration clears details',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await fonts(tester);
        final security = _Security(), boundary = GlobalKey();
        Future<void> capture(String name) async {
          expect(tester.takeException(), isNull);
          if (!Platform.isLinux) {
            return;
          }
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final dir = Directory('build/mobile-ui-review')
              ..createSync(recursive: true);
            await File(
              '${dir.path}/$name-${size.width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: ProviderScope(
              overrides: [
                financeWorkspaceRepositoryProvider.overrideWithValue(
                  _Report(SalonDatabase.instance, security),
                ),
                sensitiveActionServiceProvider.overrideWithValue(security),
                stockDocumentRepositoryProvider.overrideWithValue(_SourceRepository(SalonDatabase.instance, security)),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.build(SalonThemeTemplate.salonIvory),
                home: const FinancePage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Lập khoản chi'), findsOneWidget);
        await capture('40-finance-expenses');
        await tester.tap(find.text('Lập khoản chi'));
        await tester.pumpAndSettle();
        await capture('41-finance-create');
        await tester.tap(find.text('Hủy'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Ghi trả / phân bổ').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ghi trả / phân bổ').first);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('finance-payment-submit')), findsOneWidget);
        await capture('42-finance-payment');
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Công nợ NCC'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Công nợ NCC'));
        await tester.pumpAndSettle();
        await capture('43-finance-suppliers');
        await tester.ensureVisible(find.text('Ghi trả / phân bổ').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ghi trả / phân bổ').last);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('allocation-opening-a')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('allocation-opening-b')),
          findsOneWidget,
        );
        expect(tester.widget<TextFormField>(find.byKey(const ValueKey('allocation-opening-b'))).controller!.text, '1000000');
        expect(tester.widget<TextFormField>(find.byKey(const ValueKey('allocation-opening-a'))).controller!.text, isEmpty);
        await capture('44-finance-allocation');
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Chi tiết / lịch sử').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chi tiết / lịch sử').first);
        await tester.pumpAndSettle();
        await capture('45-finance-details');
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Chi tiết / lịch sử').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chi tiết / lịch sử').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Xem phiếu nhập nguồn'));
        await tester.pumpAndSettle();
        await capture('49-finance-stock-source');
        await tester.tap(find.text('Đóng').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Chi phí vận hành'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chi phí vận hành'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Chi tiết / lịch sử').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chi tiết / lịch sử').first);
        await tester.pumpAndSettle();
        await capture('47-finance-receipt');
        await tester.ensureVisible(find.text('Đảo / hoàn tiền'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Đảo / hoàn tiền'));
        await tester.pumpAndSettle();
        await capture('48-finance-reversal');
        security.active = false;
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(find.text('Sổ tiền cần quyền chủ salon'), findsOneWidget);
        expect(find.textContaining('Nhà cung cấp Việt'), findsNothing);
        await capture('46-finance-locked');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'money double tap executes once; lost result freezes exact request and requires reconcile before retry',
    (tester) async {
      final gate = Completer<void>();
      final ids = <String>[], payloads = <Map<String, Object?>>[];
      var calls = 0, resolutions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (_) => FinancePaymentDialog(
                    book: FinanceBook.expense,
                    accounts: [fixtureAccount(FinanceBook.expense, 'expense')],
                    submit: (id, op, p) async {
                      ids.add(id);
                      payloads.add(Map.from(p));
                      calls++;
                      if (calls == 1) {
                        await gate.future;
                        throw StateError('Result lost');
                      }
                    },
                    resolve: (id) async {
                      expect(id, ids.first);
                      resolutions++;
                      return false;
                    },
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.byKey(const Key('finance-payment-submit')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('finance-payment-submit')));
      await tester.pump();
      expect(calls, 1);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Đối chiếu đúng requestId'), findsOneWidget);
      expect(find.byKey(const ValueKey('allocation-expense')), findsNothing);
      await tester.tap(find.text('Đối chiếu đúng requestId'));
      await tester.pumpAndSettle();
      expect(resolutions, 1);
      await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Thử lại cùng yêu cầu'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(ids[0], ids[1]);
      expect(payloads[0], payloads[1]);
    },
  );
  testWidgets(
    'restart pending reversal keeps payload; committed reconcile never submits again',
    (tester) async {
      var submitted = false;
      final pending = {
        'requestId': 'restart-reversal',
        'operation': 'reversal',
        'payload': {
          'paymentId': 'old-proof',
          'reason': 'Hoàn đã nhận',
          'reference': 'BANK-R',
        },
      };
      await tester.pumpWidget(
        MaterialApp(
          home: FinancePaymentDialog(
            book: FinanceBook.supplier,
            accounts: const [],
            pending: pending,
            submit: (_, _, _) async {
              submitted = true;
            },
            resolve: (id) async {
              expect(id, 'restart-reversal');
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('restart-reversal'), findsOneWidget);
      await tester.tap(find.text('Đối chiếu đúng requestId'));
      await tester.pumpAndSettle();
      expect(submitted, isFalse);
    },
  );
  testWidgets('background closes sensitive editor', (tester) async {
    final security = _Security();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeWorkspaceRepositoryProvider.overrideWithValue(
            _Report(SalonDatabase.instance, security),
          ),
          sensitiveActionServiceProvider.overrideWithValue(security),
        ],
        child: const MaterialApp(home: FinancePage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lập khoản chi'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('finance-create-amount')), findsNothing);
    expect(find.text('Sổ tiền cần quyền chủ salon'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('late snapshot after background never restores sensitive data', (
    tester,
  ) async {
    final security = _Security(), result = Completer<FinanceWorkspace>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeWorkspaceRepositoryProvider.overrideWithValue(
            _DelayedReport(SalonDatabase.instance, security, result.future),
          ),
          sensitiveActionServiceProvider.overrideWithValue(security),
        ],
        child: const MaterialApp(home: FinancePage()),
      ),
    );
    await tester.pump();
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    result.complete(fixtureWorkspace());
    await tester.pumpAndSettle();
    expect(find.text('Sổ tiền cần quyền chủ salon'), findsOneWidget);
    expect(find.textContaining('Chủ nhà'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('PIN remains open during input, but background removes it', (tester) async {
    final security = _Security()..active = false;
    await tester.pumpWidget(ProviderScope(overrides: [
      financeWorkspaceRepositoryProvider.overrideWithValue(_Report(SalonDatabase.instance, security)),
      sensitiveActionServiceProvider.overrideWithValue(security),
    ], child: const MaterialApp(home: FinancePage())));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const Key('owner-authorization-dialog')), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('owner-authorization-dialog')), findsNothing);
    expect(find.text('Sổ tiền cần quyền chủ salon'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
