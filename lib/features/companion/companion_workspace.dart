import 'package:flutter/material.dart';
import '../../core/lan/lan_health_client.dart';
import '../../core/lan/lan_read_client.dart';
import '../../core/lan/lan_read_models.dart';
import '../../core/lan/lan_workflow_client.dart';
import '../../core/lan/lan_write_contract.dart';
import 'companion_bill_workspace.dart';
import 'companion_command_controller.dart';
import 'companion_mobile_list.dart';

export 'companion_bill_workspace.dart' show CompanionCatalogSubtitle;

class CompanionWorkspace extends StatefulWidget {
  const CompanionWorkspace({super.key, required this.connection, required this.readClient,
    required this.client, required this.commands, required this.role, required this.onDenied,
    this.connectionOptions});
  final LanConnection connection;
  final SalonReadClient readClient;
  final LanWorkflowClient client;
  final CompanionCommandController commands;
  final PhoneWriteRole role;
  final VoidCallback onDenied;
  final Widget Function(BuildContext)? connectionOptions;
  @override
  State<CompanionWorkspace> createState() => _CompanionWorkspaceState();
}

class _CompanionWorkspaceState extends State<CompanionWorkspace> {
  final navigator = GlobalKey<NavigatorState>();
  final redraw = ValueNotifier<int>(0);
  int tab = 0;
  int refresh = 0;
  bool get locked => widget.commands.blocked;
  @override
  void initState() { super.initState(); widget.commands.addListener(_changed); }
  void _changed() { if (mounted) { redraw.value++; } }
  @override
  void dispose() { widget.commands.removeListener(_changed); redraw.dispose(); super.dispose(); }

  Future<void> _edit(String kind, String? id) async {
    if (locked || widget.role == PhoneWriteRole.none) { return; }
    await navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => Scaffold(
      appBar: AppBar(title: Text(kind == 'customer' ? 'Thông tin khách hàng' : 'Lịch hẹn')),
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16),
        child: CompanionBillWorkspace(connection: widget.connection, readClient: widget.readClient,
          client: widget.client, commands: widget.commands, role: widget.role, onDenied: widget.onDenied,
          initialKind: kind, initialId: id))))));
    if (mounted) { refresh++; _changed(); }
  }
  Future<void> _bills({String? appointmentId}) async {
    await navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('Bill đang làm')),
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16),
        child: CompanionBillWorkspace(connection: widget.connection, readClient: widget.readClient,
          client: widget.client, commands: widget.commands, role: widget.role, onDenied: widget.onDenied,
          initialKind: appointmentId == null ? 'bills' : 'appointmentBill', initialId: appointmentId))))));
    if (mounted) { refresh++; _changed(); }
  }

  @override
  Widget build(BuildContext context) => NavigatorPopHandler(
    onPopWithResult: (result) => navigator.currentState!.pop(result),
    child: Navigator(key: navigator, onGenerateRoute: (_) => MaterialPageRoute<void>(
      builder: (context) => AnimatedBuilder(animation: redraw, builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(['Hôm nay', 'Lịch hẹn', 'Khách hàng', 'Hóa đơn', 'Thêm'][tab]),
          actions: const [Padding(padding: EdgeInsets.only(right: 16),
            child: Tooltip(message: 'Đang kết nối với máy salon', child: Icon(Icons.wifi, size: 20)))]),
        body: SafeArea(child: Column(children: [
          if (widget.commands.pending != null || widget.commands.message != null)
            ConstrainedBox(constraints: BoxConstraints(maxHeight: (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom) * .23),
              child: SingleChildScrollView(child: CompanionPendingNotice(commands: widget.commands))),
          Expanded(child: IndexedStack(index: tab, children: [
            CompanionMobileList(key: const PageStorageKey('today'), kind: SalonReadKind.appointments,
              today: true, connection: widget.connection, token: widget.commands.token,
              client: widget.readClient, refresh: refresh, onDenied: widget.onDenied,
              onEdit: widget.role == PhoneWriteRole.none || locked ? null : (id) => _edit('appointment', id),
              onCreate: widget.role == PhoneWriteRole.none || locked ? null : () => _edit('appointment', null),
              onBill: widget.role == PhoneWriteRole.none || locked ? null : (id) => _bills(appointmentId: id)),
            CompanionMobileList(key: const PageStorageKey('appointments'), kind: SalonReadKind.appointments,
              connection: widget.connection, token: widget.commands.token, client: widget.readClient,
              refresh: refresh, onDenied: widget.onDenied,
              onEdit: widget.role == PhoneWriteRole.none || locked ? null : (id) => _edit('appointment', id),
              onCreate: widget.role == PhoneWriteRole.none || locked ? null : () => _edit('appointment', null),
              onBill: widget.role == PhoneWriteRole.none || locked ? null : (id) => _bills(appointmentId: id)),
            CompanionMobileList(key: const PageStorageKey('customers'), kind: SalonReadKind.customers,
              connection: widget.connection, token: widget.commands.token, client: widget.readClient,
              refresh: refresh, onDenied: widget.onDenied,
              onEdit: widget.role == PhoneWriteRole.none || locked ? null : (id) => _edit('customer', id),
              onCreate: widget.role == PhoneWriteRole.none || locked ? null : () => _edit('customer', null)),
            CompanionMobileList(key: const PageStorageKey('invoices'), kind: SalonReadKind.invoices,
              connection: widget.connection, token: widget.commands.token, client: widget.readClient,
              refresh: refresh, onDenied: widget.onDenied, onBills: _bills),
            ListView(padding: const EdgeInsets.all(16), children: [
              const Card(child: ListTile(leading: Icon(Icons.wifi),
                title: Text('Đang kết nối với máy salon'), subtitle: Text('Dữ liệu được lưu trên máy salon.'))),
              Card(child: ListTile(leading: const Icon(Icons.badge_outlined),
                title: const Text('Quyền của điện thoại'),
                subtitle: Text(switch(widget.role) { PhoneWriteRole.none => 'Chỉ xem',
                  PhoneWriteRole.staff => 'Nhân viên', PhoneWriteRole.cashier => 'Thu ngân', PhoneWriteRole.owner => 'Chủ salon' }))),
              if (widget.connectionOptions != null) widget.connectionOptions!(context),
              const Padding(padding: EdgeInsets.all(12), child: Text('Cần kết nối lại? Kiểm tra Wi-Fi và giữ máy salon mở.')),
            ]),
          ])),
        ])),
        bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0 ? null : NavigationBar(selectedIndex: tab, labelBehavior: MediaQuery.textScalerOf(context).scale(14) > 18 ? NavigationDestinationLabelBehavior.onlyShowSelected : NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (value) { FocusManager.instance.primaryFocus?.unfocus(); tab = value; _changed(); },
          destinations: const [
            NavigationDestination(key: Key('mobile-tab-today'), icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Hôm nay'),
            NavigationDestination(key: Key('mobile-tab-appointments'), icon: Icon(Icons.calendar_month_outlined), label: 'Lịch hẹn'),
            NavigationDestination(key: Key('mobile-tab-customers'), icon: Icon(Icons.people_outline), label: 'Khách hàng'),
            NavigationDestination(key: Key('mobile-tab-invoices'), icon: Icon(Icons.receipt_long_outlined), label: 'Hóa đơn'),
            NavigationDestination(key: Key('mobile-tab-more'), icon: Icon(Icons.more_horiz), label: 'Thêm'),
          ]),
      )))));
}

class CompanionPendingNotice extends StatelessWidget {
  const CompanionPendingNotice({super.key, required this.commands});
  final CompanionCommandController commands;
  @override
  Widget build(BuildContext context) => Material(color: Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(commands.message ?? 'Đang lưu trên máy salon…', key: const Key('write-message')),
      if (commands.pending != null) ...[
        const Text('Có thao tác chờ kiểm tra. Thao tác mới được khóa để tránh lưu trùng.'),
        Wrap(spacing: 8, children: [
          TextButton(key: const Key('write-check-result'), onPressed: commands.busy ? null : commands.check, child: const Text('Kiểm tra kết quả')),
          if (commands.canRetry) TextButton(key: const Key('write-retry-command'), onPressed: commands.busy ? null : commands.retry, child: const Text('Gửi lại thao tác đã lưu')),
          if (commands.oldEpoch) TextButton(onPressed: commands.busy ? null : commands.discardOldEpoch, child: const Text('Bỏ thao tác cũ chưa thực hiện')),
        ]),
      ],
    ])));
}
