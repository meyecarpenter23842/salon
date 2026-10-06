import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/lan/lan_connection_qr.dart';
import '../../core/lan/lan_health_client.dart';

typedef SalonScannerPreview = Widget Function(BuildContext context, ValueChanged<String> onValue);
class CompanionQrScanner extends StatefulWidget {
  const CompanionQrScanner({super.key, this.preview});
  final SalonScannerPreview? preview;
  @override State<CompanionQrScanner> createState() => _CompanionQrScannerState();
}
class _CompanionQrScannerState extends State<CompanionQrScanner> {
  bool completed = false;
  String? message;
  void _detected(String raw) {
    if (completed || !mounted) return;
    try {
      final connection = LanConnectionQr.decode(raw);
      completed = true; Navigator.of(context).pop<LanConnection>(connection);
    } catch (_) {
      setState(() => message = 'QR này không phải thông tin kết nối salon hợp lệ. Quét QR trong Cài đặt → Kết nối điện thoại.');
    }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quét QR máy salon')),
    body: SafeArea(child: Column(children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('Đưa QR trên máy salon vào khung. Sau khi quét, đối chiếu địa chỉ và mã xác minh trước khi dùng.')),
      Expanded(child: ClipRect(child: widget.preview?.call(context, _detected) ??
        (Platform.isAndroid ? MobileScanner(onDetect: (capture) {
          for (final barcode in capture.barcodes) {
            if (barcode.rawValue != null) { _detected(barcode.rawValue!); if (completed) break; }
          }
        }, errorBuilder: (context, error) => const Center(child: Padding(padding: EdgeInsets.all(24),
          child: Text('Chưa mở được camera. Cho phép camera trong Cài đặt Android, hoặc quay lại để dán thông tin QR / nhập thủ công.'))))
        : const Center(child: Text('Quét QR bằng camera trên app Android. Bạn vẫn có thể dán thông tin QR.'))))),
      if (message != null) Padding(padding: const EdgeInsets.all(16), child: Text(message!, key: const Key('qr-scan-error'))),
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Quay lại, nhập thủ công')),
    ])),
  );
}
