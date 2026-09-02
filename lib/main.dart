import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/database/database_bootstrap.dart';
import 'core/database/salon_database.dart';
import 'core/settings/local_settings_store.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await DatabaseBootstrap.ensureInitialized();
    await LocalSettingsStore.instance.initialize();
    await SalonDatabase.instance.initialize();
    final launchStaffWindow = args.any((arg) => arg.trim() == '--staff-window');
    runApp(
      ProviderScope(
        child: launchStaffWindow
            ? const StaffWindowApp()
            : const SalonManagerApp(),
      ),
    );
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'salon_manager.bootstrap',
        context: ErrorDescription('during application startup'),
      ),
    );

    runApp(_StartupFailureApp(error: error, stackTrace: stackTrace));
  }
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error, required this.stackTrace});

  final Object error;
  final StackTrace stackTrace;

  @override
  Widget build(BuildContext context) {
    final technicalDetail = kReleaseMode
        ? error.toString()
        : '$error\n\n$stackTrace';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF6F1EA),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(
                            Icons.error_outline,
                            size: 28,
                            color: Color(0xFF9A5C2F),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Không thể khởi động Quản Lý Salon Tóc',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Ứng dụng gặp lỗi khi khởi tạo dữ liệu cục bộ hoặc thiết lập môi trường. Hãy kiểm tra quyền ghi thư mục chạy app, trạng thái file cơ sở dữ liệu và khởi động lại ứng dụng.',
                        style: TextStyle(height: 1.6),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1E3D2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFD7B089)),
                        ),
                        child: const Text(
                          'Đường dẫn dữ liệu mặc định (Windows): %APPDATA%/HairSpaManager/data/.salon_manager/salon_manager.db.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SelectableText(
                        technicalDetail,
                        style: const TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
