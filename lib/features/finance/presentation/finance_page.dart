import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../../../core/models/audit_event.dart';
import '../../../core/models/entity_id.dart';
import '../../../core/models/finance_workspace.dart';
import '../../../core/models/supplier_payable.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/repositories/finance_workspace_repository.dart';
import '../../../core/repositories/stock_document_repository.dart';
import '../../../core/providers/stock_document_providers.dart';
import '../../../shared/widgets/sensitive_action_authorization.dart';
import 'finance_dialogs.dart';
import 'finance_pdf.dart';

class FinancePage extends ConsumerStatefulWidget {
  const FinancePage({super.key});
  @override
  ConsumerState<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends ConsumerState<FinancePage>
    with WidgetsBindingObserver {
  FinanceWorkspace? data;
  FinanceBook book = FinanceBook.expense;
  String? entity, status, source;
  DateTime? from, to;
  final query = TextEditingController();
  int page = 0, generation = 0;
  bool locked = true, protected = false, busy = false;
  String error = '';
  Timer? timer;
  ModalRoute<dynamic>? pageRoute;
  FinanceFilter get filter => FinanceFilter(
    book: book,
    entityId: entity,
    state: status,
    sourceType: source,
    from: from,
    to: to,
    query: query.text,
  );
  bool get allowed =>
      mounted &&
      !locked &&
      (!protected ||
          ref.read(sensitiveActionServiceProvider).isOwnerSessionActive);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (protected &&
          !ref.read(sensitiveActionServiceProvider).isOwnerSessionActive) {
        _lock();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    pageRoute ??= ModalRoute.of(context);
  }

  @override
  void dispose() {
    timer?.cancel();
    query.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _lock() {
    if (!mounted) {
      return;
    }
    generation++;
    if (pageRoute != null) {
      Navigator.of(context).popUntil((r) => r == pageRoute);
    }
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() {
      locked = true;
      data = null;
      error = '';
      query.clear();
      entity = null;
      status = null;
      source = null;
      from = null;
      to = null;
      page = 0;
      busy = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && protected) {
      ref.read(sensitiveActionServiceProvider).lockOwnerSession();
      _lock();
    }
  }

  Future<void> _unlock() async {
    if (!mounted || busy) {
      return;
    }
    final token = generation;
    final configured = await ref
        .read(sensitiveActionServiceProvider)
        .isProtectionConfigured();
    if (!mounted || generation != token) {
      return;
    }
    setState(() => protected = configured);
    if (!await ensureSensitiveActionAuthorized(
          context,
          ref,
          SensitiveAction.finance,
        ) ||
        !mounted ||
        generation != token) {
      return;
    }
    setState(() {
      protected = configured;
      locked = false;
    });
    await _reload();
  }

  Future<void> _reload() async {
    if (!allowed) {
      _lock();
      return;
    }
    final token = ++generation;
    setState(() {
      busy = true;
      error = '';
      data = null;
    });
    try {
      final repo = ref.read(financeWorkspaceRepositoryProvider);
      if (repo == null) {
        throw StateError('Sổ tiền cần dữ liệu SQLite.');
      }
      final next = await repo.fetch();
      if (allowed && token == generation) {
        setState(() {
          data = next;
          busy = false;
        });
      }
    } catch (e) {
      if (allowed && token == generation) {
        setState(() {
          error = 'Không tải được sổ tiền: $e';
          busy = false;
        });
      }
    }
    if (mounted && !allowed) {
      _lock();
    }
  }

  void _message(String text) {
    if (allowed) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _write(Future<void> Function() action) async {
    if (busy || !allowed) {
      return;
    }
    setState(() => busy = true);
    try {
      await action();
      _message('Đã ghi. Tải lại để đối chiếu số dư.');
    } catch (e) {
      _message('Không ghi được: $e');
    } finally {
      if (allowed) {
        await _reload();
      }
    }
  }

  Future<void> _create() async {
    final snapshot = data;
    if (snapshot == null || busy || !allowed) {
      return;
    }
    final selectedBook = book;
    final input = await showDialog<FinanceCreateInput>(
      context: context,
      builder: (_) => FinanceCreateDialog(
        book: selectedBook,
        entities: selectedBook == FinanceBook.expense
            ? snapshot.categories
            : snapshot.suppliers,
      ),
    );
    if (input == null || !allowed) {
      return;
    }
    final id = EntityId.create('finance_create');
    await _write(() async {
      if (selectedBook == FinanceBook.expense) {
        await ref
            .read(expenseRepositoryProvider)!
            .createExpense(
              requestId: id,
              categoryId: input.entityId,
              date: input.date,
              payee: input.payee,
              amount: input.amount,
              reason: input.reason,
              externalReference: input.reference,
            );
      } else {
        await ref
            .read(supplierPayableRepositoryProvider)!
            .createOpeningBalance(
              requestId: id,
              supplierId: input.entityId,
              date: input.date,
              amount: input.amount,
              reason: input.reason,
              externalReference: input.reference,
            );
      }
    });
  }

  Future<void> _submit(
    FinanceBook selectedBook,
    String id,
    String operation,
    Map<String, Object?> p,
  ) async {
    if (!allowed) {
      throw StateError('Phiên Owner đã khóa.');
    }
    if (selectedBook == FinanceBook.expense) {
      final repo = ref.read(expenseRepositoryProvider)!;
      if (operation == 'reversal') {
        await repo.reversePayment(
          requestId: id,
          paymentId: p['paymentId'] as String,
          reason: p['reason'] as String,
          reference: p['reference'] as String,
        );
      } else {
        await repo.pay(
          requestId: id,
          expenseId: p['expenseId'] as String,
          amount: p['amount'] as int,
          method: p['method'] as String,
          reference: p['reference'] as String,
          note: p['note'] as String,
        );
      }
    } else {
      final repo = ref.read(supplierPayableRepositoryProvider)!;
      if (operation == 'reversal') {
        await repo.reversePayment(
          requestId: id,
          paymentId: p['paymentId'] as String,
          reason: p['reason'] as String,
          reference: p['reference'] as String,
        );
      } else {
        await repo.pay(
          requestId: id,
          supplierId: p['supplierId'] as String,
          allocations: (p['allocations'] as List)
              .map(
                (a) => SupplierPaymentAllocationInput(
                  obligationId: a['obligationId'] as String,
                  amount: a['amount'] as int,
                ),
              )
              .toList(),
          method: p['method'] as String,
          reference: p['reference'] as String,
          note: p['note'] as String,
        );
      }
    }
  }

  Future<void> _payment({
    FinanceAccount? account,
    FinanceProof? reversal,
    Map<String, Object?>? pending,
  }) async {
    if (busy || !allowed) {
      return;
    }
    final selectedBook = account?.book ?? reversal?.book ?? book;
    setState(() => busy = true);
    try {
      final latest = await ref
          .read(financeWorkspaceRepositoryProvider)!
          .fetch();
      if (!allowed) {
        return;
      }
      final savedPending = latest.pending[selectedBook];
      // Do not hide a pending request by opening another editor.
      final effectivePending = savedPending ?? pending;
      final selected = account == null
          ? <FinanceAccount>[]
          : latest.accounts
                .where(
                  (a) =>
                      a.book == selectedBook &&
                      !a.reversed &&
                      a.balance > 0 &&
                      (selectedBook == FinanceBook.expense
                          ? a.id == account.id
                          : a.entityId == account.entityId),
                )
                .toList();
      if (effectivePending == null && reversal == null && selected.isEmpty) {
        _message('Khoản này đã thay đổi hoặc hết nợ. Tải lại sổ.');
        return;
      }
      if (effectivePending == null &&
          reversal != null &&
          latest.proofs.any(
            (p) => p.book == selectedBook && p.originalId == reversal.id,
          )) {
        _message('Chứng từ đã được đảo.');
        return;
      }
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => FinancePaymentDialog(
          book: selectedBook,
          accounts: selected,
          pending: effectivePending,
          reversal: reversal,
          submit: (id, op, p) => _submit(selectedBook, id, op, p),
          resolve: (id) {
            if (!allowed) {
              throw StateError('Phiên Owner đã khóa.');
            }
            return selectedBook == FinanceBook.expense
                ? ref.read(expenseRepositoryProvider)!.resolvePendingPayment(id)
                : ref
                      .read(supplierPayableRepositoryProvider)!
                      .resolvePendingPayment(id);
          },
        ),
      );
    } catch (e) {
      _message('Không mở được chứng từ: $e');
    } finally {
      if (allowed) {
        await _reload();
      }
    }
  }

  Future<String?> _text(String title, {String initial = ''}) async {
    final c = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 200,
          decoration: const InputDecoration(labelText: 'Nội dung bắt buộc'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              if (c.text.trim().isNotEmpty) {
                Navigator.pop(ctx, c.text.trim());
              }
            },
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    // Dispose after the dialog exit animation has finished.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    c.dispose();
    return allowed ? value : null;
  }

  Future<void> _category({
    Map<String, Object?>? category,
    bool toggle = false,
  }) async {
    if (busy || !allowed) {
      return;
    }
    final name = toggle
        ? await _text(
            '${category!['is_active'] == 1 ? 'Ngừng dùng' : 'Bật lại'} ${category['name']} — nhập xác nhận',
          )
        : await _text(
            category == null ? 'Thêm loại chi phí' : 'Đổi tên loại chi phí',
            initial: category?['name'] as String? ?? '',
          );
    if (name == null || !allowed) {
      return;
    }
    await _write(() async {
      final repo = ref.read(expenseRepositoryProvider)!,
          id = EntityId.create('finance_category');
      if (category == null) {
        await repo.createCategory(requestId: id, name: name);
      } else if (toggle) {
        await repo.setCategoryActive(
          requestId: id,
          id: category['id'] as String,
          expectedRevision: category['revision'] as int,
          active: category['is_active'] != 1,
        );
      } else {
        await repo.renameCategory(
          requestId: id,
          id: category['id'] as String,
          expectedRevision: category['revision'] as int,
          name: name,
        );
      }
    });
  }

  Future<void> _reverse(FinanceAccount a) async {
    final reason = await _text('Đảo nghĩa vụ — nhập lý do');
    if (reason == null || !allowed) {
      return;
    }
    await _write(() async {
      final id = EntityId.create('finance_reverse');
      if (a.book == FinanceBook.expense) {
        await ref
            .read(expenseRepositoryProvider)!
            .reverseExpense(requestId: id, expenseId: a.id, reason: reason);
      } else {
        await ref
            .read(supplierPayableRepositoryProvider)!
            .reverseOpeningBalance(
              requestId: id,
              obligationId: a.id,
              reason: reason,
            );
      }
    });
  }

  Future<void> _source(FinanceAccount a) async {
    if (!allowed || a.sourceId == null) {
      return;
    }
    try {
      final StockDocumentRepository repo = ref.read(
        stockDocumentRepositoryProvider,
      );
      final doc = await repo.document(a.sourceId!);
      if (!allowed) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Phiếu nhập ${doc.number}'),
          content: SizedBox(
            width: 580,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${doc.supplierName} · ${financeDate(doc.date)} · ${doc.statusLabel}\nTổng phiếu ${financeMoney(doc.total)}',
                  ),
                  for (final l in doc.lines)
                    Text(
                      '${l.productName} · ${l.quantity} ${l.unitName} · ${financeMoney(l.amount)}',
                    ),
                  const Text(
                    'Hủy PN đã trả: đảo/hoàn chứng từ tiền trước, sau đó hủy ở Kho hàng → Chứng từ.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } catch (e) {
      _message('Không mở được phiếu nguồn: $e');
    }
  }

  Future<void> _details(FinanceAccount a) async {
    if (busy || !allowed) {
      return;
    }
    try {
      final snapshot = await ref
          .read(financeWorkspaceRepositoryProvider)!
          .fetch();
      if (!allowed) {
        return;
      }
      final current = snapshot.accounts.singleWhere(
        (v) => v.book == a.book && v.id == a.id,
      );
      final proofs = snapshot.proofs
          .where((p) => p.book == a.book && p.allocations.containsKey(a.id))
          .toList();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${a.name} · ${a.source}'),
          content: SizedBox(
            width: 700,
            height: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    '${a.id}\nNgày nghĩa vụ ${financeDate(a.date)} · ${a.payee}\n${a.reason}\nTham chiếu: ${a.reference}\n${financeState(current.state)} · nghĩa vụ ${financeMoney(a.amount)} · đã trả ròng ${financeMoney(current.paid)} · còn ${financeMoney(current.balance)}',
                  ),
                  if (a.sourceId != null)
                    TextButton(
                      onPressed: () => _source(a),
                      child: const Text('Xem phiếu nhập nguồn'),
                    ),
                  const Divider(),
                  const Text('Chứng từ tiền và phân bổ (mọi ngày)'),
                  for (final p in proofs)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(
                              '${p.kind == 'reversal' ? 'Đảo / hoàn' : 'Thanh toán'} · ${p.id}\n${financeDate(p.date)} · ${p.method == 'cash' ? 'Tiền mặt' : 'Chuyển khoản'} · ${p.reference}\nPhân bổ khoản này ${financeMoney(p.allocations[a.id]!)} / tổng chứng từ ${financeMoney(p.amount)}\nNgười ghi ${p.row['actor']} · ${p.row['note']}\nChứng từ gốc: ${p.originalId ?? '—'} · Biến động ca: ${p.row['cash_movement_id'] ?? '—'}',
                            ),
                            for (final alloc in p.allocations.entries)
                              Text(
                                '${snapshot.accounts.where((v) => v.id == alloc.key && v.book == p.book).first.source} · ${financeMoney(alloc.value)}',
                              ),
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton(
                                  onPressed: () => _print(
                                    snapshot,
                                    FinanceFilter(book: a.book),
                                    proof: p,
                                  ),
                                  child: const Text('PDF biên nhận'),
                                ),
                                if (p.kind == 'payment' &&
                                    !snapshot.proofs.any(
                                      (v) =>
                                          v.book == p.book &&
                                          v.originalId == p.id,
                                    ))
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _payment(reversal: p);
                                    },
                                    child: const Text('Đảo / hoàn tiền'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Divider(),
                  const Text('Lịch sử nghĩa vụ / yêu cầu'),
                  for (final e in snapshot.events[a.book]!.where(
                    (e) =>
                        e['target_id'] == a.id ||
                        proofs.any(
                          (p) =>
                              p.id == e['target_id'] || p.id == e['request_id'],
                        ),
                  ))
                    SelectableText(
                      '${e['created_at']} · ${e['operation']} · ${e['actor']}\n${e['detail']} · requestId ${e['request_id']}',
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } catch (e) {
      _message('Không mở được chi tiết: $e');
    }
  }

  Future<void> _print(
    FinanceWorkspace snapshot,
    FinanceFilter selectedFilter, {
    FinanceProof? proof,
  }) async {
    if (!allowed) {
      return;
    }
    try {
      final bytes = await buildFinancePdf(
        snapshot,
        selectedFilter,
        proof: proof,
      );
      if (!allowed) {
        return;
      }
      await Printing.layoutPdf(
        name: proof == null ? 'So-doi-chieu' : 'Bien-nhan-${proof.id}',
        onLayout: (_) async {
          if (!allowed) {
            throw StateError('Phiên Owner đã khóa.');
          }
          return bytes;
        },
      );
    } catch (e) {
      _message('Không tạo được PDF: $e');
    }
  }

  Future<void> _dates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: from == null
          ? null
          : DateTimeRange(start: from!, end: to!),
    );
    if (range != null && allowed) {
      setState(() {
        from = range.start;
        to = range.end;
        page = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Chi phí & công nợ'),
      actions: [
        IconButton(
          tooltip: 'Tải lại',
          onPressed: busy || locked ? null : _reload,
          icon: const Icon(Icons.refresh),
        ),
        if (protected && !locked)
          IconButton(
            tooltip: 'Khóa sổ tiền',
            onPressed: () {
              ref.read(sensitiveActionServiceProvider).lockOwnerSession();
              _lock();
            },
            icon: const Icon(Icons.lock_outline),
          ),
      ],
    ),
    body: locked
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 40),
                const Text('Sổ tiền cần quyền chủ salon'),
                TextButton(
                  onPressed: _unlock,
                  child: const Text('Mở bằng PIN Owner'),
                ),
              ],
            ),
          )
        : data == null
        ? Center(
            child: busy
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error),
                      TextButton(
                        onPressed: _reload,
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
          )
        : _workspace(data!),
  );
  Widget _workspace(FinanceWorkspace snapshot) {
    final rows = snapshot.select(filter), pages = (rows.length / 20).ceil();
    final safePage = pages == 0 ? 0 : page.clamp(0, pages - 1);
    final shown = rows.skip(safePage * 20).take(20).toList();
    final entities = book == FinanceBook.expense
        ? snapshot.categories
        : snapshot.suppliers;
    final amount = rows
            .where((a) => !a.reversed)
            .fold<int>(0, (s, a) => s + a.amount),
        paid = rows.fold<int>(0, (s, a) => s + a.paid),
        balance = rows.fold<int>(0, (s, a) => s + a.balance);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Chi phí vận hành'),
              selected: book == FinanceBook.expense,
              onSelected: busy
                  ? null
                  : (_) => setState(() {
                      book = FinanceBook.expense;
                      entity = null;
                      source = null;
                      page = 0;
                    }),
            ),
            ChoiceChip(
              label: const Text('Công nợ NCC'),
              selected: book == FinanceBook.supplier,
              onSelected: busy
                  ? null
                  : (_) => setState(() {
                      book = FinanceBook.supplier;
                      entity = null;
                      source = null;
                      page = 0;
                    }),
            ),
            FilledButton.icon(
              onPressed: busy ? null : _create,
              icon: const Icon(Icons.add),
              label: Text(
                book == FinanceBook.expense ? 'Lập khoản chi' : 'Số dư đầu kỳ',
              ),
            ),
            if (book == FinanceBook.expense)
              OutlinedButton(
                onPressed: busy ? null : () => _category(),
                child: const Text('Thêm loại chi'),
              ),
            OutlinedButton.icon(
              onPressed: busy ? null : () => _print(snapshot, filter),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('PDF sổ đối chiếu'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 250,
              child: TextField(
                controller: query,
                decoration: const InputDecoration(
                  labelText: 'Tìm nội dung / tham chiếu',
                ),
                onChanged: (_) => setState(() => page = 0),
              ),
            ),
            SizedBox(
              width: 250,
              child: DropdownButtonFormField<String>(
                key: ValueKey('entity-$book-$entity'),
                initialValue: entity,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: book == FinanceBook.expense
                      ? 'Loại chi phí'
                      : 'Nhà cung cấp',
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Tất cả')),
                  for (final e in entities)
                    DropdownMenuItem(
                      value: e['id'] as String,
                      child: Text(
                        '${e['name']}${e['is_active'] == 1 ? '' : ' · ngừng dùng'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() {
                  entity = v == '' ? null : v;
                  page = 0;
                }),
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                key: ValueKey('status-$status'),
                initialValue: status,
                decoration: const InputDecoration(
                  labelText: 'Trạng thái hiện tại',
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Tất cả')),
                  for (final s in ['unpaid', 'partial', 'paid', 'reversed'])
                    DropdownMenuItem(value: s, child: Text(financeState(s))),
                ],
                onChanged: (v) => setState(() {
                  status = v == '' ? null : v;
                  page = 0;
                }),
              ),
            ),
            if (book == FinanceBook.supplier)
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('source-$source'),
                  initialValue: source,
                  decoration: const InputDecoration(
                    labelText: 'Nguồn nghĩa vụ',
                  ),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Tất cả nguồn')),
                    DropdownMenuItem(
                      value: 'stock_receipt',
                      child: Text('Phiếu nhập'),
                    ),
                    DropdownMenuItem(
                      value: 'opening',
                      child: Text('Số dư đầu kỳ'),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    source = v == '' ? null : v;
                    page = 0;
                  }),
                ),
              ),
            OutlinedButton(
              onPressed: busy ? null : _dates,
              child: Text(
                from == null
                    ? 'Mọi ngày'
                    : '${financeDate(from!)} – ${financeDate(to!)}',
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                from = null;
                to = null;
                entity = null;
                status = null;
                source = null;
                query.clear();
                page = 0;
              }),
              child: const Text('Bỏ lọc'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nghĩa vụ theo ngày nguồn · ${rows.length} khoản (toàn bộ kết quả lọc)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'Nghĩa vụ hiệu lực ${financeMoney(amount)} · đã trả ròng mọi ngày ${financeMoney(paid)} · còn phải trả hiện tại ${financeMoney(balance)}',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Dòng tiền theo ngày chứng từ · không lọc trạng thái nghĩa vụ',
                ),
                Text(
                  'Tiền mặt ròng ${financeMoney(snapshot.flowTotal(filter, 'cash'))} · chuyển khoản ròng ${financeMoney(snapshot.flowTotal(filter, 'transfer'))}',
                ),
                Text(
                  'Snapshot ${financeDate(snapshot.at)} ${snapshot.at.hour}:${snapshot.at.minute.toString().padLeft(2, '0')}. Nghĩa vụ và chứng từ tiền là hai góc nhìn, không cộng lại; chưa có giá vốn/lợi nhuận.',
                ),
              ],
            ),
          ),
        ),
        if (snapshot.pending[book] != null)
          Card(
            child: ListTile(
              title: const Text('Có yêu cầu tiền cần đối chiếu'),
              subtitle: Text('${snapshot.pending[book]!['requestId']}'),
              trailing: TextButton(
                onPressed: busy
                    ? null
                    : () => _payment(pending: snapshot.pending[book]),
                child: const Text('Đối chiếu'),
              ),
            ),
          ),
        if (busy) const LinearProgressIndicator(),
        if (book == FinanceBook.expense && entity != null)
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: busy
                    ? null
                    : () => _category(
                        category: entities.singleWhere(
                          (e) => e['id'] == entity,
                        ),
                      ),
                child: const Text('Đổi tên loại chi'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => _category(
                        category: entities.singleWhere(
                          (e) => e['id'] == entity,
                        ),
                        toggle: true,
                      ),
                child: const Text('Ngừng dùng / bật lại'),
              ),
            ],
          ),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Chưa có khoản phù hợp. Nợ cũ nhập số dư đầu kỳ; PN mới có NCC sinh nợ khi ghi kho.',
            ),
          ),
        for (final a in shown)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${a.name} · ${a.source}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${financeDate(a.date)} · ${a.payee} · ${financeState(a.state)}\n${a.reason}',
                  ),
                  Text(
                    'Nghĩa vụ ${financeMoney(a.amount)} · đã trả ${financeMoney(a.paid)} · còn ${financeMoney(a.balance)}',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: busy ? null : () => _details(a),
                        child: const Text('Chi tiết / lịch sử'),
                      ),
                      if (a.balance > 0)
                        FilledButton.tonal(
                          onPressed: busy ? null : () => _payment(account: a),
                          child: const Text('Ghi trả / phân bổ'),
                        ),
                      if (!a.reversed &&
                          a.paid == 0 &&
                          a.sourceType != 'stock_receipt')
                        TextButton(
                          onPressed: busy ? null : () => _reverse(a),
                          child: const Text('Đảo nghĩa vụ'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text(
              'Trang ${safePage + 1}/${pages == 0 ? 1 : pages} · 20 khoản/trang',
            ),
            TextButton(
              onPressed: busy || safePage == 0
                  ? null
                  : () => setState(() => page = safePage - 1),
              child: const Text('Trang trước'),
            ),
            TextButton(
              onPressed: busy || safePage + 1 >= pages
                  ? null
                  : () => setState(() => page = safePage + 1),
              child: const Text('Trang sau'),
            ),
          ],
        ),
      ],
    );
  }
}
