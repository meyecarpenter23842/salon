import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/app/desktop_shell_page.dart';

void main() {
  test('Windows app launches Staff as a separate process outside tests', () {
    expect(
      shouldLaunchStaffWindowSeparately(
        isWindows: true,
        isFlutterTest: false,
      ),
      isTrue,
    );
  });

  test('widget tests keep the in-process fallback to avoid spawning runners', () {
    expect(
      shouldLaunchStaffWindowSeparately(
        isWindows: true,
        isFlutterTest: true,
      ),
      isFalse,
    );
    expect(
      shouldLaunchStaffWindowSeparately(
        isWindows: false,
        isFlutterTest: false,
      ),
      isFalse,
    );
  });
}
