import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../../../core/models/payroll.dart';
import '../../../../core/models/audit_event.dart';
import '../../../../core/models/entity_id.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/repositories/sqlite_payroll_repository.dart';
import '../../../../shared/widgets/sensitive_action_authorization.dart';
import 'payroll_dialogs.dart';
import 'payroll_pdf.dart';

String _money(int value) => NumberFormat.currency(
  locale: 'vi_VN',
  symbol: 'đ',
  decimalDigits: 0,
).format(value);
String _hours(int seconds) => '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}p';

class PayrollPage extends ConsumerStatefulWidget {
  const PayrollPage({super.key});
  @override
  ConsumerState<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends ConsumerState<PayrollPage>
    with WidgetsBindingObserver {
  String period = SqlitePayrollRepository.month(DateTime.now());
  Future<PayrollWorkspace>? future;
  bool busy = false, locked = true, protected = false;
  Timer? timer;
  ModalRoute<dynamic>? pageRoute;
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _lock() {
    if (!mounted || locked) {
      return;
    }
    if (pageRoute != null) {
      Navigator.of(context).popUntil((route) => route == pageRoute);
    }
    setState(() {
      locked = true;
      future = null;
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
    if (!mounted) {
      return;
    }
    if (!await ensureSensitiveActionAuthorized(
          context,
          ref,
          SensitiveAction.payroll,
        ) ||
        !mounted) {
      return;
    }
    final configured = await ref
        .read(sensitiveActionServiceProvider)
        .isProtectionConfigured();
    if (mounted) {
      setState(() {
        protected = configured;
        locked = false;
        _reload();
      });
    }
  }

  void _reload() {
    future = ref.read(payrollRepositoryProvider)!.fetch(period);
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));
  Future<void> _perform(Future<void> Function() action) async {
    if (busy || locked) {
      return;
    }
    setState(() => busy = true);
    try {
      await action();
      if (mounted && !locked) {
        setState(_reload);
        _message('Đã lưu bảng lương.');
      }
    } catch (e) {
      if (mounted && !locked) {
        _message('Không lưu được: $e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> _policy(PayrollWorkspace data) async {
    final input = await showDialog<SalaryPolicyInput>(
      context: context,
      builder: (_) => SalaryPolicyDialog(
        employees: data.employees,
        policies: data.policies,
        period: period,
      ),
    );
    if (input == null || !mounted || locked) {
      return;
    }
    await _perform(
      () => ref
          .read(payrollRepositoryProvider)!
          .setPolicy(
            requestId: EntityId.create('payroll_request'),
            employeeId: input.employeeId,
            effectivePeriod: input.period,
            mode: input.mode,
            rate: input.rate,
            standardMinutes: input.minutes,
            reason: input.reason,
          ),
    );
  }

  Future<void> _create(PayrollWorkspace data) async {
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Lập bảng lương cho nhân viên'),
        children: [
          for (final e in data.employees)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e['id']),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(e['full_name'] as String),
              ),
            ),
        ],
      ),
    );
    if (id == null || !mounted || locked) {
      return;
    }
    await _perform(() async {
      await ref
          .read(payrollRepositoryProvider)!
          .createDraft(
            requestId: EntityId.create('payroll_request'),
            employeeId: id,
            period: period,
          );
    });
  }

  Future<void> _item(PayrollView run, {Map<String, Object?>? reversal}) async {
    try {
      final sources = await ref
          .read(payrollRepositoryProvider)!
          .closedFor(run.employeeId, run.period);
      if (!mounted || locked) {
        return;
      }
      final input = await showDialog<PayrollItemInput>(
        context: context,
        builder: (_) => PayrollItemDialog(sources: sources, reversal: reversal),
      );
      if (input == null || !mounted || locked) {
        return;
      }
      await _perform(
        () => ref
            .read(payrollRepositoryProvider)!
            .addItem(
              requestId: EntityId.create('payroll_request'),
              run: run,
              kind: input.kind,
              amount: input.amount,
              reason: input.reason,
              sourceRunId: input.source,
              reversedItemId: reversal?['id'] as String?,
            ),
      );
    } catch (e) {
      if (mounted && !locked) {
        _message('Không mở được khoản lương: $e');
      }
    }
  }

  Future<void> _close(PayrollView run) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Chốt lương ${run.name} · ${run.period}?'),
        content: Text(
          'Lương phải trả: ${_money(run.net)}\nĐã ứng/trả: ${_money(run.paid)}\nHoa hồng trả riêng. Công và chính sách được giữ tại thời điểm chốt; thao tác này chưa chi tiền.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Chốt kỳ'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || locked) {
      return;
    }
    await _perform(
      () => ref
          .read(payrollRepositoryProvider)!
          .close(requestId: EntityId.create('payroll_request'), run: run),
    );
  }

  Future<void> _payment(PayrollView? run, Map<String, Object?>? pending) async {
    if (busy || locked) {
      return;
    }
    setState(() => busy = true);
    try {
      final repo = ref.read(payrollRepositoryProvider)!;
      final latest = await repo.document(
        pending?['runId'] as String? ?? run!.id,
      );
      if (!mounted || locked) {
        return;
      }
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PayrollPaymentDialog(
          repository: repo,
          run: latest,
          pending: pending,
        ),
      );
      if (mounted && !locked) {
        setState(_reload);
      }
    } catch (e) {
      if (mounted && !locked) {
        _message('Không mở được chi lương: $e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> _details(PayrollView run) async {
    try {
      final history = await ref
          .read(payrollRepositoryProvider)!
          .history(run.id);
      if (!mounted || locked) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Đối soát · ${run.name} · ${run.period}'),
          content: SizedBox(
            width: 700,
            height: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chính sách đã dùng: ${payrollModeLabel(run.policy['mode'] as String)} · ${_money(run.policy['rate'] as int)}',
                  ),
                  Text(
                    'Phiên bản ${run.policy['revision']} · hiệu lực ${run.policy['effective_period']}',
                  ),
                  const SizedBox(height: 12),
                  const Text('Công dùng trong bảng lương'),
                  for (final a in (run.snapshot['attendance'] as List))
                    Text(
                      '${a['work_day']} · ${a['label']} · ${a['state']} · phiên bản ${a['revision']}',
                    ),
                  const Divider(),
                  const Text('Khoản phụ cấp / khấu trừ / điều chỉnh'),
                  if (run.items.isEmpty) const Text('Không có'),
                  for (final i in run.items)
                    Text(
                      '${_money(i['amount'] as int)} · ${i['reason']} · ${i['actor']}'
                      '${i['source_run_id'] == null ? '' : ' · kỳ gốc: ${i['source_run_id']}'}',
                    ),
                  const Divider(),
                  const Text('Chứng từ đã ứng / trả'),
                  if (run.payouts.isEmpty) const Text('Chưa ghi trả'),
                  for (final p in run.payouts)
                    Text(
                      '${p['kind'] == 'advance' ? 'Tạm ứng' : 'Chi lương'} · ${_money(p['amount'] as int)}'
                      ' · ${p['method'] == 'cash' ? 'Tiền mặt' : 'Chuyển khoản'} · ${p['reference']} · ${p['actor']}\n${p['created_at']} · ${p['note']}',
                    ),
                  const Divider(),
                  const Text('Lịch sử thao tác'),
                  for (final e in history)
                    Text(
                      '${e['operation']} · ${e['actor']} · ${e['created_at']}\n${e['reason']}',
                    ),
                  const Divider(),
                  const Text('Lịch sử chính sách lương'),
                  for (final p in run.policyHistory)
                    Text(
                      'Phiên bản ${p['revision']} · ${p['effective_period']}'
                      ' · ${payrollModeLabel(p['mode'] as String)} · ${_money(p['rate'] as int)}\n${p['actor']} · ${p['reason']}',
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
      if (mounted && !locked) {
        _message('Không mở được đối soát: $e');
      }
    }
  }

  Future<void> _print(PayrollView run) async {
    try {
      final fresh = await ref.read(payrollRepositoryProvider)!.document(run.id);
      final bytes = await buildPayrollPdf(fresh);
      if (!mounted || locked) {
        return;
      }
      if (!await ensureSensitiveActionAuthorized(
            context,
            ref,
            SensitiveAction.payroll,
          ) ||
          !mounted ||
          locked) {
        return;
      }
      await Printing.layoutPdf(
        onLayout: (_) => Future.value(bytes),
        name: 'Phieu-luong-${run.period}-${run.id}',
      );
    } catch (e) {
      if (mounted && !locked) {
        _message('Không tạo được phiếu lương: $e');
      }
    }
  }

  Future<void> _period() async {
    final current = DateTime.parse('$period-01');
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date != null && mounted && !locked) {
      setState(() {
        period = SqlitePayrollRepository.month(date);
        _reload();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Bảng lương'),
      actions: [
        IconButton(
          tooltip: 'Tải lại',
          onPressed: busy || locked ? null : () => setState(_reload),
          icon: const Icon(Icons.refresh),
        ),
        if (protected && !locked)
          IconButton(
            tooltip: 'Khóa bảng lương',
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
                const SizedBox(height: 12),
                const Text('Bảng lương cần quyền chủ salon'),
                TextButton(
                  onPressed: _unlock,
                  child: const Text('Mở bằng PIN Owner'),
                ),
              ],
            ),
          )
        : FutureBuilder<PayrollWorkspace>(
            future: future,
            builder: (context, state) {
              if (state.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Không tải được bảng lương: ${state.error}'),
                      TextButton(
                        onPressed: _unlock,
                        child: const Text('Xác thực / thử lại'),
                      ),
                    ],
                  ),
                );
              }
              if (!state.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = state.data!, runs = data.runs;
              final total = runs.fold<int>(0, (sum, r) => sum + r.net),
                  paid = runs.fold<int>(0, (sum, r) => sum + r.paid);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        OutlinedButton.icon(
                          onPressed: busy ? null : _period,
                          icon: const Icon(Icons.calendar_month),
                          label: Text('Kỳ $period'),
                        ),
                        OutlinedButton.icon(
                          onPressed: busy ? null : () => _policy(data),
                          icon: const Icon(Icons.tune),
                          label: const Text('Thiết lập lương'),
                        ),
                        FilledButton.icon(
                          onPressed: busy ? null : () => _create(data),
                          icon: const Icon(Icons.add),
                          label: const Text('Lập bảng lương'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Lương dự kiến/đã chốt: ${_money(total)} · Đã ứng/trả: ${_money(paid)}\nHoa hồng trả riêng, không cộng vào tổng lương.',
                      ),
                    ),
                  ),
                  if (data.pending != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Card(
                        child: ListTile(
                          title: const Text('Có khoản trả lương cần đối chiếu'),
                          subtitle: Text(
                            'Số tiền: ${_money(data.pending!['amount'] as int)}',
                          ),
                          trailing: TextButton(
                            onPressed: busy
                                ? null
                                : () => _payment(null, data.pending),
                            child: const Text('Mở khoản chờ'),
                          ),
                        ),
                      ),
                    ),
                  if (busy) const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: runs.isEmpty
                        ? const Center(
                            child: Text(
                              'Chưa có bảng lương. Thiết lập lương rồi lập kỳ cho nhân viên.',
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: runs.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) =>
                                _card(runs[index], data.pending),
                          ),
                  ),
                ],
              );
            },
          ),
  );
  Widget _card(PayrollView run, Map<String, Object?>? pending) {
    final reversed = run.items
        .map((i) => i['reversed_item_id'])
        .whereType<String>()
        .toSet();
    final standard = run.policy['standard_minutes'] as int;
    final excess =
        run.policy['mode'] == 'monthly_work' && run.seconds > standard * 60
        ? run.seconds - standard * 60
        : 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(run.name, style: Theme.of(context).textTheme.titleMedium),
                Chip(label: Text(run.closed ? 'Đã chốt' : 'Nháp')),
                Text(payrollModeLabel(run.policy['mode'] as String)),
              ],
            ),
            Text(
              'Công: ${_hours(run.seconds)} · Lương cơ bản: ${_money(run.base)}',
            ),
            if (excess > 0)
              Text('Giờ vượt chuẩn: ${_hours(excess)} · chưa tính tăng ca'),
            if (run.unresolved > 0 && !run.closed)
              Text('Còn ${run.unresolved} ca cần hoàn tất/nghỉ/hủy'),
            Text('Phụ cấp/khấu trừ/điều chỉnh: ${_money(run.extras)}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                Text('Phải trả: ${_money(run.net)}'),
                Text('Đã ứng/trả: ${_money(run.paid)}'),
                Text(
                  run.balance < 0
                      ? 'Đã trả vượt: ${_money(-run.balance)}'
                      : 'Còn phải trả: ${_money(run.balance)}',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Hoa hồng đã chốt còn phải trả/bù trừ (trả riêng): ${_money(run.commissionBalance)}',
            ),
            if (run.sourceChanged)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Công/chính sách đã thay đổi sau chốt. Tiền kỳ này giữ nguyên; dùng khoản điều chỉnh ở kỳ sau.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!run.closed) ...[
                  OutlinedButton(
                    onPressed: busy ? null : () => _item(run),
                    child: const Text('Thêm khoản'),
                  ),
                  FilledButton(
                    onPressed: busy ? null : () => _close(run),
                    child: const Text('Chốt kỳ'),
                  ),
                ],
                OutlinedButton(
                  onPressed:
                      busy ||
                          pending != null ||
                          (run.closed && run.balance <= 0)
                      ? null
                      : () => _payment(run, null),
                  child: Text(run.closed ? 'Ghi trả lương' : 'Ghi tạm ứng'),
                ),
                TextButton.icon(
                  onPressed: busy ? null : () => _details(run),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Đối soát / lịch sử'),
                ),
                TextButton.icon(
                  onPressed: busy ? null : () => _print(run),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Phiếu lương'),
                ),
              ],
            ),
            if (!run.closed && run.items.isNotEmpty) ...[
              const Divider(),
              for (final item in run.items)
                if (item['kind'] != 'reversal' &&
                    !reversed.contains(item['id']))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${item['reason']} · ${_money(item['amount'] as int)}',
                    ),
                    trailing: TextButton(
                      onPressed: busy ? null : () => _item(run, reversal: item),
                      child: const Text('Bỏ khoản'),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

