import 'dart:io';

Future<void> main(List<String> args) async {
  final handle = await File(args.single).open(mode: FileMode.append);
  try {
    await handle.lock(FileLock.exclusive, 0, 1);
    stdout.writeln('acquired');
  } on FileSystemException {
    exitCode = 23;
    stdout.writeln('owned');
  } finally {
    await handle.close();
  }
}
