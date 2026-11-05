// 只使用本机 Dart 与临时假 Flutter；不下载 SDK。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../JobsFlutterTools/Scripts/FlutterProjectTools.dart' as tools;

Future<void> main(List<String> args) async {
  // 导入型测试的主文件不在生产模块目录：私有stage提供无网络桥接假件。
  if (args.isEmpty && Platform.isMacOS && Platform.environment['JOBS_DART_TEST_STAGED'] != '1') {
    final stage = Directory.systemTemp.createTempSync('jobs-dart-route-adapter-');
    try {
      final source = File.fromUri(Platform.script);
      final library = source.parent.uri.resolve('../../JobsFlutterTools/Scripts/FlutterProjectTools.dart');
      final staged = File('${stage.path}/retry.dart');
      staged.writeAsStringSync(source.readAsStringSync().replaceFirst(
          "import '../../JobsFlutterTools/Scripts/FlutterProjectTools.dart' as tools;",
          "import '$library' as tools;"));
      final route = File('${stage.path}/【MacOS】FlutterSDK网络选路.zsh/【MacOS】FlutterSDK网络选路.zsh');
      route.parent.createSync(recursive: true);
      route.writeAsStringSync("""#!/bin/zsh
if [[ \$1 == --cache-dir ]]; then
  mkdir -p '${stage.path}/cache'
  print -r -- '${stage.path}/cache'
  exit 0
fi
[[ \$1 == --run ]] || exit 71
shift 5
exec \"\$@\"
""");
      final result = await Process.run(Platform.resolvedExecutable, [staged.path],
          environment: {'JOBS_DART_TEST_STAGED': '1'});
      stdout.write(result.stdout); stderr.write(result.stderr); exitCode = result.exitCode;
    } finally { stage.deleteSync(recursive: true); }
    return;
  }
  if (args.isNotEmpty) {
    final result = await tools.run(args[0], ['--version', '--machine'], args[1]);
    stdout.write(result.stdout);
    return;
  }
  if (Platform.isWindows) {
    stdout.writeln('SKIP: 假工具夹具使用 Unix shell；Windows 由 PowerShell 隔离回归覆盖。');
    return;
  }
  final temporary = Directory.systemTemp.createTempSync('jobs-dart-sdk-retry-');
  final fake = File('${temporary.path}/flutter');
  Process? worker;
  try {
    fake.writeAsStringSync('''#!/bin/sh
count=0
[ ! -f count ] || read count < count
count=\$((count+1))
printf '%s\\n' "\$count" > count
if [ "\$count" -eq 1 ]; then printf 'Failed to download SDK' >&2; exit 28; fi
printf '{"sdk":"ready"}'
''');
    await Process.run('/bin/chmod', ['u+x', fake.path]);
    final result = await tools.run(fake.path, ['--version', '--machine'], temporary.path);
    if (result.exitCode != 0 || result.stdout != '{"sdk":"ready"}' ||
        File('${temporary.path}/count').readAsStringSync().trim() != '2') {
      throw StateError('获取失败后没有继续，或成功响应混入重试信息');
    }
    File('${temporary.path}/count').deleteSync();
    final original = fake.readAsStringSync();
    fake.writeAsStringSync(original.replaceFirst('exit 28', 'exit 0'));
    final semantic = await tools.run(fake.path, ['--version'], temporary.path);
    if (semantic.exitCode != 0 || File('${temporary.path}/count').readAsStringSync().trim() != '2') throw StateError('退出0但下载失败被误判为成功');
    fake.writeAsStringSync(original);
    // 非 SDK 业务仅执行一次。
    File('${temporary.path}/count').deleteSync();
    final business = await tools.run(fake.path, ['build', 'apk'], temporary.path);
    if (business.exitCode != 28 || File('${temporary.path}/count').readAsStringSync().trim() != '1') {
      throw StateError('业务构建被反复执行');
    }
    File('${temporary.path}/count').deleteSync();
    worker = await Process.start(Platform.resolvedExecutable,
        [Platform.script.toFilePath(), fake.path, temporary.path]);
    final stdoutDrain = worker.stdout.drain<void>();
    final waiting = Completer<void>();
    final errors = StringBuffer();
    final stderrDrain = worker.stderr.transform(utf8.decoder).forEach((text) {
      errors.write(text);
      if (errors.toString().contains('秒后自动重试') && !waiting.isCompleted) waiting.complete();
    });
    await waiting.future.timeout(const Duration(seconds: 15));
    worker.kill(ProcessSignal.sigint);
    final code = await worker.exitCode.timeout(const Duration(seconds: 10));
    await Future.wait([stdoutDrain, stderrDrain]);
    if (code != 130 || File('${temporary.path}/count').readAsStringSync().trim() != '1') {
      throw StateError('退避期间主动取消后仍然重试');
    }
    final safe = tools.safeSdkLog('https://user:pass@example.invalid/sdk?token=secret\nauthorization: Bearer hidden');
    if (safe.contains('pass') || safe.contains('secret') || safe.contains('hidden')) throw StateError('SDK 日志未脱敏');
    stdout.writeln('PASS: SdkAcquisitionRetry.Tests.dart (6 assertions)');
  } finally {
    worker?.kill(ProcessSignal.sigkill);
    temporary.deleteSync(recursive: true);
  }
}
