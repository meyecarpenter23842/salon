import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/services/windows_self_update_handoff.dart';

void main() {
  test('self-update helper delays briefly, closes gracefully, installs, then restarts', () {
    expect(
      windowsSelfUpdateHelperScript,
      contains('Start-Sleep -Milliseconds 900'),
    );
    expect(windowsSelfUpdateHelperScript, contains('CloseMainWindow()'));
    expect(
      windowsSelfUpdateHelperScript,
      contains(r'-FilePath $Installer'),
    );
    expect(windowsSelfUpdateHelperScript, contains('-Wait'));
    expect(
      windowsSelfUpdateHelperScript,
      contains(
        r'Start-Process -FilePath $Executable -WorkingDirectory $InstallDir',
      ),
    );
  });

  test('self-update helper never waits on a parent PID or force-kills Salon', () {
    expect(windowsSelfUpdateHelperScript, isNot(contains('ParentPid')));
    expect(windowsSelfUpdateHelperScript, isNot(contains('Wait-ProcessExit')));
    expect(windowsSelfUpdateHelperScript.toLowerCase(), isNot(contains('taskkill')));
    expect(windowsSelfUpdateHelperScript, isNot(contains('/F')));
    expect(
      windowsSelfUpdateHelperScript,
      contains('hủy cập nhật thay vì force-kill'),
    );
  });

  test('self-update helper receives an explicit diagnostic log path', () {
    expect(windowsSelfUpdateHelperScript, contains(r'[string]$LogPath'));
    expect(windowsSelfUpdateHelperScript, contains(r'$logPath = $LogPath'));
  });
}
