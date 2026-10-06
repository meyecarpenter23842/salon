import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/lan/lan_contract.dart';
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
    this.workflowClient = const PinnedLanWorkflowClient()});
  final LanConnection connection;
  final LanPairingClient client;
  final SalonReadClient readClient;
  final LanWorkflowClient workflowClient;
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
  bool _foreground = true;
  bool _online = false;
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
      // A fresh request remains possible; never fall back to plaintext storage.
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
      _poll = Timer(const Duration(seconds: 5), _refresh);
    }
  }

  void _apply(PairedPhone phone) {
    if (_phone?.state != phone.state || _phone?.writeRole != phone.writeRole ||
        _phone?.canReadSalon != phone.canReadSalon) { _reviewedOnDesktop = false; }
    _phone = phone;
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

  Future<void> _refresh() async {
    if (_busy || !_foreground || _credential == null) return;
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      var phone = await widget.client.status(widget.connection, _credential!.token);
      if (phone.state == PhoneAccess.approved) {
        phone = await widget.client.bootstrap(widget.connection, _credential!.token);
      }
      if (!mounted || generation != _generation) return;
      setState(() => _apply(phone));
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _online = false;
        _message = 'Mất kết nối. Giữ máy salon mở và kiểm tra Wi-Fi.';
        if (error is PairingFailure &&
            (error.code == LanErrorCode.unauthenticated || error.code == LanErrorCode.forbidden)) {
          _phone = null;
          _message = 'Quyền truy cập không còn hiệu lực. Hãy xin mã ghép mới.';
          widget.onAccess(false);
          // Keep the encrypted identity while an uncertain command is unresolved.
        }
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
        _schedule();
      }
    }
  }

  Future<void> _request() async {
    if (_busy || _loading || !_foreground) return;
    if (_commands?.blocked == true) {
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
      final credential = previous != null && (_phone == null || _phone!.state == PhoneAccess.pending)
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
        _busy = false;
        _online = false;
        _message = 'Đang kiểm tra lại kết nối…';
      });
    }
    if (_foreground && !_loading) _refresh();
  }

  Future<void> _forget() async {
    if (_busy || _commands?.blocked == true) {
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
        _credential = null; _phone = null; _online = false; _message = null;
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
    if (ready) {
      return CompanionWorkspace(
        key: ValueKey('${_credential!.token}:${_phone!.writeRole.name}'),
        connection: widget.connection, readClient: widget.readClient, client: widget.workflowClient,
        commands: _commands!, role: _phone!.writeRole,
        connectionOptions: (_) => _content(),
        onDenied: () {
          if (!mounted) { return; }
          setState(() => _online = false);
          _refresh();
        });
    }
    if (_phone?.state == PhoneAccess.approved) {
      return Scaffold(appBar: AppBar(title: const Text('Salon — Trang chính')),
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
        Text(approved ? 'Salon của bạn' : 'Xin quyền truy cập',
          style: Theme.of(context).textTheme.titleLarge),
        if (approved) ...[
          const SizedBox(height: 12),
          const Text('Điện thoại đã được chủ salon duyệt.'),
          const SizedBox(height: 16),
          if (!_phone!.canReadSalon)
            const Text('Chủ salon cần bật “Cho xem dữ liệu salon” cho điện thoại này '
                'trong Cài đặt → Kết nối điện thoại.'),
        ],
        if (!approved && !pending && !_loading) ...[
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

        if (approved || pending || _credential != null)
          TextButton.icon(key: const Key('companion-access-refresh'),
            onPressed: _busy ? null : _refresh,
            icon: Icon(_online ? Icons.wifi : Icons.wifi_off),
            label: Text(_busy ? 'Đang kiểm tra…' : 'Kiểm tra lại trạng thái')),
        if (_credential != null)
          TextButton(key: const Key('companion-forget'),
            onPressed: _busy || _commands?.blocked == true ? null : _forget,
            child: const Text('Quên quyền trên điện thoại này')),
        if (_loading) const LinearProgressIndicator(),
      ],
    );
  }
}
