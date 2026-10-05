import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/lan/lan_health_client.dart';

class SalonCompanionApp extends StatelessWidget {
  const SalonCompanionApp({
    super.key,
    this.checker = const PinnedLanHealthClient(),
  });
  final LanHealthChecker checker;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Salon — Điện thoại',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF805A45)),
    ),
    home: _ConnectionPage(checker: checker),
  );
}

class _ConnectionPage extends StatefulWidget {
  const _ConnectionPage({required this.checker});
  final LanHealthChecker checker;

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
    setState(() => _message = null);
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
      setState(() => _message = saved
        ? 'Máy salon đang phản hồi. Đã lưu cấu hình kết nối.'
        : 'Máy salon đang phản hồi. Chưa lưu được cấu hình.');
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _message =
          'Không kết nối được. Kiểm tra URL, mã chứng chỉ, mạng '
          'và app desktop đang mở.');
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
    appBar: AppBar(title: const Text('Kết nối máy salon')),
    body: SafeArea(
      child: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Mở app desktop và lấy API URL trong mục Kết nối điện thoại.',
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
                        labelText: 'API URL',
                        hintText: 'https://192.168.1.20:8743/api/staff/v1',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: _edited,
                      validator: (_) {
                        try {
                          LanConnection(_url.text, '0' * 64);
                          return null;
                        } catch (_) {
                          return 'Nhập URL HTTPS kết thúc bằng /api/staff/v1.';
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
                        labelText: 'SHA-256 chứng chỉ desktop',
                        helperText: 'Lấy mã từ desktop khi thiết lập HTTPS.',
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
                          return 'Nhập đủ 64 ký tự hex của mã chứng chỉ.';
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
              const SizedBox(height: 24),
              const Text(
                'Hiện chỉ kiểm tra kết nối; chưa ghép quyền thiết bị '
                'hoặc mở khách/bill. Điện thoại không lưu database salon.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Cùng mạng salon dùng URL LAN. Nếu dùng 4G/mạng khác, '
                'cần URL truy cập từ xa đã được thiết lập.',
              ),
            ],
          ),
    ),
  );
}
