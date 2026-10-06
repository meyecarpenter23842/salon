import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/lan/lan_contract.dart';
import '../../core/lan/lan_changes.dart';
import '../../core/lan/lan_health_client.dart';
import '../../core/lan/lan_pairing.dart';
import '../../core/lan/lan_pairing_client.dart';
import 'companion_credential_store.dart';
import 'companion_workspace.dart';
import 'companion_command_controller.dart';
import '../../core/lan/lan_workflow_client.dart';
import '../../core/lan/lan_write_contract.dart';
import '../../core/lan/lan_read_client.dart';

class CompanionAccessPanel extends StatefulWidget {
  const CompanionAccessPanel({super.key, required this.connection,
    required this.client, required this.store, required this.onAccess,
    this.readClient = const PinnedSalonReadClient(),
    this.workflowClient = const PinnedLanWorkflowClient(), this.changeClient, this.onConnectionSettings});
  final VoidCallback? onConnectionSettings;
  final LanConnection connection;
  final LanPairingClient client;
  final SalonReadClient readClient;
  final LanWorkflowClient workflowClient;
  final LanChangeClient? changeClient;
  final CompanionCredentialStore store;
  final ValueChanged<bool> onAccess;
  @override
  State<CompanionAccessPanel> createState() => _CompanionAccessPanelState();
}

class _CompanionAccessPanelState extends State<CompanionAccessPanel>
    with WidgetsBindingObserver {
  final _code = TextEditingController();
  final _name = TextEditingController(text: 'Điện thoại của tôi');
  CompanionCredential? _credential;
  CompanionCommandController? _commands;
  PairedPhone? _phone;
  Timer? _poll;
  bool _busy = false;
  bool _checking = false;
  bool _needsPairing = false;
  bool _storageFailed = false;
  bool _foreground = true;
  bool _online = false;
  bool _wasReady = false;
  bool _syncing = false;
  bool _loading = true;
  int _generation = 0;
  String? _message;
  bool _reviewedOnDesktop = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.store.read();
      if (!mounted) return;
      if (value?.pin == widget.connection.certificateSha256) {
        _credential = value;
        _initCommands();
      } else if (value?.pendingCommand != null) {
        _message = 'Có thao tác chưa rõ kết quả trên kết nối cũ. Khôi phục địa chỉ và mã xác minh cũ để kiểm tra.';
      }
    } catch (_) {
      _storageFailed = true;
      _message = 'Chưa đọc được quyền đã lưu. Thử lại; không cần lấy mã ghép mới.';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_credential != null && _foreground) _refresh();
      }
    }
  }

  void _initCommands() {
    _commands?.removeListener(_commandChanged);
    _commands?.dispose();
    _commands = CompanionCommandController(connection: widget.connection, client: widget.workflowClient,
      store: widget.store, credential: _credential!, onCredential: (value) {
        if (mounted && _credential?.token == value.token) setState(() => _credential = value);
      })..addListener(_commandChanged);
  }
  void _commandChanged() { if (mounted) setState(() {}); }

  void _schedule() {
    _poll?.cancel();
    if (mounted && _foreground && _credential != null &&
        (_phone == null || _phone!.state == PhoneAccess.pending ||
         _phone!.state == PhoneAccess.approved)) {
      _poll = Timer(const Duration(seconds: 5), () => _refresh(silent: true));
    }
  }

  void _apply(PairedPhone phone) {
    if (_phone?.state != phone.state || _phone?.writeRole != phone.writeRole ||
        _phone?.canReadSalon != phone.canReadSalon) { _reviewedOnDesktop = false; }
    _phone = phone;
    _needsPairing = phone.state == PhoneAccess.denied || phone.state == PhoneAccess.revoked || phone.state == PhoneAccess.expired;
    if (phone.state != PhoneAccess.approved || !phone.canReadSalon) { _wasReady = false; }
    _online = true;
    _message = switch (phone.state) {
      PhoneAccess.pending => 'Đang chờ chủ salon duyệt trên máy salon.',
      PhoneAccess.approved => 'Đang kết nối với máy salon',
      PhoneAccess.denied => 'Chủ salon đã từ chối yêu cầu.',
      PhoneAccess.revoked => 'Quyền điện thoại đã bị thu hồi.',
      PhoneAccess.expired => 'Yêu cầu đã hết hạn. Hãy xin mã ghép mới.',
    };
    widget.onAccess(phone.state == PhoneAccess.approved);
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_busy || _checking || !_foreground || _credential == null || _needsPairing) return;
    final generation = ++_generation;
    _checking = true;
    if (!silent) setState(() { _busy = true; _syncing = !_online; });
    try {
      final reconnect = !_online;
      if (reconnect && !silent) { _commands?.connectionState(connected: false, checking: true); }
      var phone = await widget.client.status(widget.connection, _credential!.token);
      if (phone.state == PhoneAccess.approved) {
        phone = await widget.client.bootstrap(widget.connection, _credential!.token);
      }
      if (!mounted || generation != _generation) return;
      if (phone.state == PhoneAccess.approved && phone.canReadSalon && widget.changeClient != null) {
        final changes = await widget.changeClient!.read(widget.connection, _credential!.token,
          _commands!.desktopEpoch, _commands!.changeCursor);
        if (!mounted || generation != _generation) return;
        _commands!.applyChanges(changes, reconnect: reconnect);
      } else { _commands?.connectionState(connected: true); }
      setState(() { _syncing = false; _apply(phone); });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _online = false; _syncing = false;
        _commands?.connectionState(connected: false);
        _message = 'Mất kết nối. Giữ máy salon mở và kiểm tra Wi-Fi.';
        if (error is PairingFailure &&
            (error.code == LanErrorCode.unauthenticated || error.code == LanErrorCode.forbidden)) {
          _phone = null; _wasReady = false; _needsPairing = true;
          _message = 'Quyền truy cập không còn hiệu lực. Hãy xin mã ghép mới.';
          widget.onAccess(false);
          // Keep the encrypted identity while an uncertain command is unresolved.
        }
      });
    } finally {
      if (mounted && generation == _generation) {
        _checking = false;
        if (_busy) setState(() => _busy = false);
        _schedule();
      }
    }
  }

  Future<void> _request() async {
    if (_busy || _checking || _loading || _storageFailed || !_foreground || (_credential != null && !_needsPairing)) return;
    if ((_commands?.pending != null || _commands?.busy == true)) {
      setState(() => _message = 'Kiểm tra thao tác chưa rõ kết quả trước khi ghép lại điện thoại.'); return;
    }
    if (!RegExp(r'^\d{8}$').hasMatch(_code.text.trim()) ||
        _name.text.trim().isEmpty || _name.text.trim().length > 60) {
      setState(() => _message = 'Nhập tên điện thoại và mã ghép 8 chữ số từ máy salon.');
      return;
    }
    final generation = ++_generation;
    _poll?.cancel();
    setState(() => _busy = true);
    try {
      final savedCredential = await widget.store.read();
      if (savedCredential?.pendingCommand != null) {
        throw StateError('Resolve saved command first');
      }
      final previous = _credential;
      // Reuse an uncertain request token, but never resurrect a terminal identity.
      final credential = previous != null && !_needsPairing && (_phone == null || _phone!.state == PhoneAccess.pending)
          ? previous : CompanionCredential(
        widget.connection.certificateSha256, newDeviceSecret());
      await widget.store.write(credential);
      if (!mounted || generation != _generation) return;
      _credential = credential;
      _initCommands();
      var phone = await widget.client.request(widget.connection,
        _code.text.trim(), _name.text.trim(), credential.token);
      if (phone.state == PhoneAccess.approved) {
        phone = await widget.client.bootstrap(widget.connection, credential.token);
      }
      if (!mounted || generation != _generation) return;
      if (phone.state == PhoneAccess.approved && phone.canReadSalon && widget.changeClient != null) {
        final changes = await widget.changeClient!.read(widget.connection, credential.token, null, 0);
        if (!mounted || generation != _generation) return;
        _commands!.applyChanges(changes, reconnect: true);
      }
      _code.clear();
      setState(() => _apply(phone));
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _message = 'Chưa gửi được yêu cầu. Kiểm tra mã ghép, mạng '
            'và quyền lưu trên điện thoại, rồi thử lại.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
        _schedule();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _generation++;
    _poll?.cancel();
    if (mounted) {
      setState(() {
        _busy = false; _checking = false;
        _online = false; _wasReady = false; _syncing = true;
        _commands?.connectionState(connected: false, checking: true);
        _message = 'Đang kiểm tra lại kết nối…';
      });
    }
    if (_foreground && !_loading) _refresh();
  }

  Future<void> _forget() async {
    if (_busy || _checking || (_commands?.pending != null || _commands?.busy == true)) {
      setState(() => _message = 'Không thể quên quyền khi có thao tác chưa rõ kết quả. Hãy kiểm tra với máy salon.'); return;
    }
    _generation++;
    _poll?.cancel();
    setState(() => _busy = true);
    try {
      await widget.store.clear();
      if (!mounted) return;
      setState(() {
        _commands?.removeListener(_commandChanged); _commands?.dispose(); _commands = null;
        _credential = null; _phone = null; _online = false; _message = null; _needsPairing = false; _wasReady = false;
      });
      widget.onAccess(false);
    } catch (_) {
      if (mounted) setState(() => _message = 'Chưa xóa được quyền đã lưu. Hãy thử lại.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _commands?.removeListener(_commandChanged);
    _commands?.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _phone?.state == PhoneAccess.approved && _phone!.canReadSalon &&
      _online && _foreground && _credential != null;
    if (ready) { _wasReady = true; }
    final retainOffline = widget.changeClient != null && _wasReady && _foreground && _phone?.state == PhoneAccess.approved && _phone!.canReadSalon && _credential != null;
    if (ready || retainOffline) {
      return LayoutBuilder(builder: (context, constraints) => SizedBox(
        height: constraints.hasBoundedHeight ? constraints.maxHeight : MediaQuery.sizeOf(context).height * .8,
        child: Column(children: [
        if (!ready) Material(color: Theme.of(context).colorScheme.secondaryContainer, child: Padding(
          padding: const EdgeInsets.all(12), child: Row(children: [
            Icon(_syncing ? Icons.sync : Icons.wifi_off), const SizedBox(width: 8),
            Expanded(child: Text(_syncing ? 'Đang kết nối và tải lại dữ liệu…' : 'Mất kết nối. Dữ liệu đang xem có thể cũ; thao tác ghi đã khóa.')),
            TextButton(key: const Key('mobile-reconnect'), onPressed: _busy ? null : _refresh, child: const Text('Kết nối lại')),
          ]))),
        Expanded(key: const ValueKey('retained-workspace'), child: CompanionWorkspace(
        key: ValueKey('${_credential!.token}:${_phone!.writeRole.name}'),
        connection: widget.connection, readClient: widget.readClient, client: widget.workflowClient,
        commands: _commands!, role: _phone!.writeRole,
        connectionOptions: (_) => _content(),
        onDenied: () {
          if (!mounted) { return; }
          setState(() => _online = false);
          _wasReady = false; _commands?.connectionState(connected: false);
          _refresh();
        })),
      ])));
    }
    if (_phone?.state == PhoneAccess.approved || _credential != null && !_needsPairing || _storageFailed) {
      return Scaffold(appBar: AppBar(title: const Text('Salon — Trang chính'), actions: [
          if (widget.onConnectionSettings != null) IconButton(key: const Key('companion-connection-settings'),
            onPressed: widget.onConnectionSettings, icon: const Icon(Icons.settings_outlined), tooltip: 'Kết nối máy salon')]),
        body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: _content())));
    }
    return LayoutBuilder(builder: (context, constraints) => constraints.hasBoundedHeight
      ? SingleChildScrollView(padding: const EdgeInsets.all(16), child: _content()) : _content());
  }

  Widget _content() {
    final approved = _phone?.state == PhoneAccess.approved;
    final pending = _phone?.state == PhoneAccess.pending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Text(approved ? 'Salon của bạn' : _storageFailed || _credential != null && !_needsPairing ? 'Kết nối đã lưu' : 'Xin quyền truy cập',
          style: Theme.of(context).textTheme.titleLarge),
        if (approved) ...[
          const SizedBox(height: 12),
          const Text('Điện thoại đã được chủ salon duyệt.'),
          const SizedBox(height: 16),
          if (!_phone!.canReadSalon)
            const Text('Chủ salon cần bật “Cho xem dữ liệu salon” cho điện thoại này '
                'trong Cài đặt → Kết nối điện thoại.'),
        ],
        if (!approved && !pending && !_loading && !_storageFailed && (_credential == null || _needsPairing)) ...[
          const Text('Trên máy salon, mở Cài đặt → Kết nối điện thoại '
              '→ Tạo mã ghép điện thoại.'),
          const SizedBox(height: 12),
          TextField(key: const Key('companion-device-name'), controller: _name,
            enabled: !_busy, maxLength: 60,
            decoration: const InputDecoration(labelText: 'Tên điện thoại')),
          TextField(key: const Key('companion-pair-code'), controller: _code,
            enabled: !_busy, keyboardType: TextInputType.number, maxLength: 8,
            decoration: const InputDecoration(labelText: 'Mã ghép điện thoại')),
          FilledButton(key: const Key('companion-request'),
            onPressed: _busy ? null : _request,
            child: const Text('Yêu cầu truy cập')),
        ],
        if (_credential != null && _phone == null && !_needsPairing)
          const Text('Điện thoại đã lưu thông tin ghép. App tự kết nối lại khi máy salon sẵn sàng.'),
        if (_storageFailed)
          TextButton(key: const Key('companion-storage-retry'), onPressed: _loading ? null : () {
            setState(() { _loading = true; _storageFailed = false; });
            _load();
          }, child: const Text('Thử lại')),
        if (widget.onConnectionSettings != null)
          TextButton.icon(key: const Key('companion-edit-connection'), onPressed: widget.onConnectionSettings,
            icon: const Icon(Icons.settings_outlined), label: const Text('Cài đặt kết nối máy salon')),
        if (_phone != null) Text('Mã thiết bị: ${_phone!.id.substring(0, 8)}'),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, key: const Key('companion-access-status')),
        ],
        if (_commands?.pending != null && _phone != null && _online && _foreground &&
            (_phone!.state == PhoneAccess.revoked || _phone!.state == PhoneAccess.approved &&
              (!_phone!.canReadSalon || !_commands!.pending!.operation.allows(_phone!.writeRole)))) ...[
          const Text('Quyền thực hiện thao tác đã bị thu hồi. Chủ salon cần mở '
            'Cài đặt → Kết nối điện thoại → Đối chiếu thao tác điện thoại. '
            'Kiểm tra mã yêu cầu và dữ liệu đã lưu trước khi kết thúc yêu cầu này.'),
          SelectableText('Mã yêu cầu: ${_commands!.pending!.commandId}'),
          CheckboxListTile(key: const Key('write-review-confirmed'), contentPadding: EdgeInsets.zero,
            title: const Text('Chủ salon đã đối chiếu kết quả trên máy salon'),
            value: _reviewedOnDesktop, onChanged: _commands!.busy ? null :
              (value) => setState(() => _reviewedOnDesktop = value ?? false)),
          TextButton(key: const Key('write-reviewed-discard'),
            onPressed: !_reviewedOnDesktop || _commands!.busy ? null : () async {
              await _commands!.discardAfterDesktopReview();
              if (mounted) setState(() { _reviewedOnDesktop = false; _message = _commands!.message; });
            }, child: const Text('Kết thúc yêu cầu đã đối chiếu')),
          if (_commands!.message != null) Text(_commands!.message!),
        ],

        if (!_needsPairing && (approved || pending || _credential != null))
          TextButton.icon(key: const Key('companion-access-refresh'),
            onPressed: _busy ? null : _refresh,
            icon: Icon(_online ? Icons.wifi : Icons.wifi_off),
            label: Text(_busy ? 'Đang kiểm tra…' : 'Kiểm tra lại trạng thái')),
        if (_credential != null)
          TextButton(key: const Key('companion-forget'),
            onPressed: _busy || (_commands?.pending != null || _commands?.busy == true) ? null : _forget,
            child: const Text('Quên quyền trên điện thoại này')),
        if (_loading) const LinearProgressIndicator(),
      ],
    );
  }
}

