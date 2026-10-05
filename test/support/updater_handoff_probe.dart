import 'dart:io';

import 'package:salonmanager/core/services/windows_self_update_handoff.dart';

Future<void> main(List<String> args) async {
  final helper = await const WindowsSelfUpdateHandoff().launch(
    helper: File(args[0]),
    installer: File('${args[1]}/unused-installer.exe'),
    executable: '${args[1]}/unused-app.exe',
    installDir: args[1],
    logPath: '${args[1]}/survived.log',
  );
  stdout.writeln('ready-helper-pid=${helper.pid}');
  exit(0);
}
