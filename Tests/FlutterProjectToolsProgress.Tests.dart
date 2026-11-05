// SDK 诊断输出隔离回归；只启动本机已有 Dart 与临时假工具。
import 'dart:convert';
import 'dart:io';
import '../JobsFlutterTools/Scripts/FlutterProjectTools.dart' as tools;

Future<void> main(List<String> args) async {
  final script = Platform.script.toFilePath();
  if (args.isNotEmpty && args.first == '--fake') {
    stderr.write('\r下载 25%');
    await stderr.flush();
    while (!File('${args[1]}/release').existsSync()) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    File('${args[1]}/finished').writeAsStringSync('yes');
    stderr.write('\r下载 100%');
    stdout.write('{"frameworkVersion":"fixture"}');
    exitCode = 37;
    return;
  }
  if (args.isNotEmpty && args.first == '--worker') {
    final result = await tools.run(
      Platform.resolvedExecutable, [script, '--fake', args[1]], args[1],
      liveProgress: true,
    );
    if (result.exitCode != 37 || result.stdout != '{"frameworkVersion":"fixture"}' ||
        result.stderr != '\r下载 25%\r下载 100%') {
      throw StateError('实时显示改变了机器响应、原始CR或退出码');
    }
    return;
  }
  final temporary = Directory.systemTemp.createTempSync('jobs-dart-sdk-progress-');
  try {
    final child = await Process.start(Platform.resolvedExecutable,
      [script, '--worker', temporary.path], workingDirectory: temporary.path);
    var observedBeforeFinish = false;
    final output = child.stdout.transform(utf8.decoder).join();
    final errors = StringBuffer();
    final drain = child.stderr.transform(utf8.decoder).forEach((chunk) {
      errors.write(chunk);
      if (errors.toString().contains('下载 25%') &&
          !File('${temporary.path}/finished').existsSync()) {
        observedBeforeFinish = true;
        File('${temporary.path}/release').writeAsStringSync('yes');
      }
    });
    final code = await child.exitCode.timeout(const Duration(seconds: 45));
    await drain;
    final raw = await output;
    if (code != 0 || !observedBeforeFinish ||
        raw != '{"frameworkVersion":"fixture"}') {
      throw StateError('任务结束前未显示CR/无换行进度，或JSON被混入额外文字');
    }
    final quiet = await tools.run(Platform.resolvedExecutable,
      [script, '--fake', temporary.path], temporary.path);
    if (quiet.exitCode != 37 || quiet.stdout != raw ||
        quiet.stderr != '\r下载 25%\r下载 100%') {
      throw StateError('普通查询的捕获语义改变');
    }
    stdout.writeln('PASS: FlutterProjectToolsProgress.Tests.dart (5 assertions; no SDK download)');
  } finally {
    temporary.deleteSync(recursive: true);
  }
}
