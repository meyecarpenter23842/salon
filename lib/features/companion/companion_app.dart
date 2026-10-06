import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/lan/lan_health_client.dart';
import '../../core/lan/lan_pairing_client.dart';
import '../../core/lan/lan_read_client.dart';
import '../../core/lan/lan_workflow_client.dart';
import 'companion_access_panel.dart';
import 'companion_credential_store.dart';

class SalonCompanionApp extends StatelessWidget {
  const SalonCompanionApp({
    super.key,
    this.checker = const PinnedLanHealthClient(),
    this.pairingClient = const PinnedLanPairingClient(),
    this.readClient = const PinnedSalonReadClient(),
    this.workflowClient = const PinnedLanWorkflowClient(),
    this.credentialStore = const AndroidCompanionCredentialStore(),
  });
  final LanHealthChecker checker;
  final LanPairingClient pairingClient;
  final SalonReadClient readClient;
  final LanWorkflowClient workflowClient;
  final CompanionCredentialStore credentialStore;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Salon — Điện thoại',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF805A45)),
      scaffoldBackgroundColor: const Color(0xFFFAF7F2),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
      cardTheme: CardThemeData(color: Colors.white, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(48, 48))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48))),
    ),
    home: _ConnectionPage(checker: checker, pairingClient: pairingClient, credentialStore: credentialStore, readClient: readClient, workflowClient: workflowClient),
  );
}

class _ConnectionPage extends StatefulWidget {
  const _ConnectionPage({required this.checker, required this.pairingClient, required this.credentialStore, required this.readClient, required this.workflowClient});
  final LanHealthChecker checker;
  final LanPairingClient pairingClient;
  final CompanionCredentialStore credentialStore;
  final SalonReadClient readClient;
  final LanWorkflowClient workflowClient;

  @override
  State<_ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<_ConnectionPage>
    with WidgetsBindingObserver {
  static const _urlKey = 'companion_api_url';
  static const _pinKey = 'companion_certificate_sha256';
  final _url = TextEditingController();
  final _pin = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _loading = true;
  bool _busy = false;
  String? _message;
  int _generation = 0;
  LanConnection? _connection;
  bool _authorized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      _url.text = preferences.getString(_urlKey) ?? '';
      _pin.text = preferences.getString(_pinKey) ?? '';
      try { _connection = LanConnection(_url.text, _pin.text); } catch (_) {}
    } catch (_) {
      // Connection can still be entered if preferences are unavailable.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _generation++;
      if (mounted) {
        setState(() {
          _busy = false;
          _message = null;
        });
      }
    }
  }

  void _edited(String _) {
    setState(() { _message = null; _connection = null; _authorized = false; });
  }

  Future<void> _check() async {
    if (_busy || !_form.currentState!.validate()) return;
    final connection = LanConnection(_url.text, _pin.text);
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _message = 'Đang kiểm tra máy salon…';
    });
    try {
      await widget.checker.check(connection);
      if (!mounted || generation != _generation) return;
      var saved = true;
      try {
        final preferences = await SharedPreferences.getInstance();
        saved = await preferences.setString(_urlKey, connection.apiUrl.toString());
        saved = await preferences.setString(_pinKey, connection.certificateSha256) && saved;
      } catch (_) {
        saved = false;
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _connection = connection;
        _message = saved
        ? 'Máy salon đang phản hồi. Đã lưu cấu hình kết nối.'
        : 'Máy salon đang phản hồi. Chưa lưu được cấu hình.';
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _message =
          'Không kết nối được. Kiểm tra địa chỉ, mã xác minh, mạng '
          'và giữ app trên máy salon mở.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _url.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: _authorized ? null : AppBar(title: const Text('Kết nối máy salon')),
    body: SafeArea(
      child: _loading
        ? const Center(child: CircularProgressIndicator())
        : LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
            physics: _authorized ? const NeverScrollableScrollPhysics() : null,
            padding: _authorized ? EdgeInsets.zero : const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!_authorized) ...[
              const Text(
                'Trên máy salon, mở Cài đặt → Kết nối điện thoại. '
                'Lấy địa chỉ và mã xác minh rồi nhập vào hai ô bên dưới.',
              ),
              const SizedBox(height: 20),
              Form(
                key: _form,
                child: Column(
                  children: [
                    TextFormField(
                      key: const Key('companion-url'),
                      controller: _url,
                      enabled: !_busy,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Địa chỉ máy salon',
                        hintText: 'https://192.168.1.20:8743/api/staff/v1',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: _edited,
                      validator: (_) {
                        try {
                          LanConnection(_url.text, '0' * 64);
                          return null;
                        } catch (_) {
                          return 'Sao chép đầy đủ địa chỉ từ máy salon, bắt đầu bằng https://.';
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('companion-pin'),
                      controller: _pin,
                      enabled: !_busy,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Mã xác minh máy salon',
                        helperText: 'Sao chép nguyên mã trong Cài đặt → Kết nối điện thoại.',
                        helperMaxLines: 2,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: _edited,
                      validator: (_) {
                        try {
                          LanConnection(
                            'https://salon.example/api/staff/v1', _pin.text,
                          );
                          return null;
                        } catch (_) {
                          return 'Sao chép đủ mã 64 ký tự từ máy salon.';
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const Key('companion-check'),
                onPressed: _busy ? null : _check,
                icon: const Icon(Icons.phonelink),
                label: Text(_busy ? 'Đang kiểm tra…' : 'Kiểm tra kết nối'),
              ),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(_message!, key: const Key('companion-result')),
              ],
              ],
              if (_connection != null)
                SizedBox(key: ValueKey('access-${_connection!.apiUrl}|${_connection!.certificateSha256}'),
                  height: _authorized ? constraints.maxHeight : null, child: CompanionAccessPanel(
                  key: ValueKey('${_connection!.apiUrl}|${_connection!.certificateSha256}'),
                  connection: _connection!, client: widget.pairingClient,
                  store: widget.credentialStore, readClient: widget.readClient, workflowClient: widget.workflowClient,
                  onAccess: (value) { if (mounted) setState(() => _authorized = value); },
                )),
              if (!_authorized) ...[
              const SizedBox(height: 24),
              const Text(
                'Sau khi chủ salon bật quyền xem, điện thoại có thể xem khách hàng, '
                'hóa đơn và lịch hẹn từ máy salon.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Lần đầu, dùng cùng Wi-Fi với máy salon và giữ app salon mở. '
                'Dùng 4G hoặc mạng khác cần thiết lập truy cập từ xa trước.',
              ),
              ],
            ]),
          )),
    ),
  );
}
