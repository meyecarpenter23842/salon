import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/services/windows_self_update_handoff.dart';

void main() {
  test('self-update helper waits, closes gracefully, installs, then restarts', () {
    expect(
      windowsSelfUpdateHelperScript,
      contains(r'Wait-ProcessExit $ParentPid 20'),
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

  test('self-update helper never force-kills Salon', () {
    expect(windowsSelfUpdateHelperScript.toLowerCase(), isNot(contains('taskkill')));
    expect(windowsSelfUpdateHelperScript, isNot(contains('/F')));
    expect(
      windowsSelfUpdateHelperScript,
      contains('hủy cập nhật thay vì force-kill'),
    );
  });
}
