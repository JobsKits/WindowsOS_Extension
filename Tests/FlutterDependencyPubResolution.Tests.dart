// Created by Jobs on 2026年10月28日，星期三。
// 用真实 Dart Pub 独立读取导入产物；仅临时工程、空缓存和 offline，不用导入器的 YAML 解析器验收。
import 'dart:convert';
import 'dart:io';

void expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

const sdkConstraint = "environment:\n  sdk: '>=3.0.0 <4.0.0'\n";
const flutterProject =
    '''name: pub_import_fixture
${sdkConstraint}dependencies:
  flutter:
    sdk: flutter
  alpha: ^1.0.0
''';

void write(String path, String text) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(text);
}

Future<ProcessResult> dart(
  List<String> arguments, {
  required String workingDirectory,
  required String cache,
}) {
  return Process.run(
    Platform.resolvedExecutable,
    arguments,
    workingDirectory: workingDirectory,
    environment: {
      'PUB_CACHE': cache,
      'PUB_ENVIRONMENT': 'jobs_dependency_import_test',
      'DART_SUPPRESS_ANALYTICS': 'true',
      'CI': 'true',
    },
  ).timeout(const Duration(minutes: 1));
}

Future<void> main() async {
  final root = Directory.systemTemp.createTempSync('jobs-import-pub-');
  var cases = 0;
  try {
    final configuredWorker = Platform.environment['JOBS_TEST_TOOLS_DIR'];
    final worker = configuredWorker == null
        ? File.fromUri(Platform.script).parent.parent.uri.resolve(
            'JobsFlutterTools/Scripts/Actions/import-dependencies/Scripts/',
          )
        : Directory(configuredWorker).absolute.uri;
    final cache = '${root.path}/isolated-pub-cache';
    final source = Directory('${root.path}/source')..createSync();
    write('${source.path}/pubspec.yaml', flutterProject);
    final roots = <String, Uri>{};
    for (final name in ['alpha', 'beta', 'flutter']) {
      final package = Directory('${root.path}/source-packages/$name')
        ..createSync(recursive: true);
      roots[name] = package.uri;
      write(
        '${package.path}/pubspec.yaml',
        'name: $name\nversion: 1.0.0\n$sdkConstraint'
            '${name == 'alpha' ? 'dependencies:\n  beta: ^1.0.0\n' : ''}',
      );
      write('${package.path}/lib/$name.dart', '// original $name\n');
      write('${package.path}/LICENSE', 'original $name license\n');
    }
    write(
      '${source.path}/pubspec.lock',
      'packages:\n${[for (final name in roots.keys) '  $name:\n    version: "1.0.0"\n    source: ${name == 'flutter' ? 'sdk' : 'hosted'}\n'].join()}',
    );
    write(
      '${source.path}/.dart_tool/package_config.json',
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'pub_import_fixture', 'rootUri': source.uri.toString()},
          for (final entry in roots.entries)
            {'name': entry.key, 'rootUri': entry.value.toString()},
        ],
      }),
    );
    final exported = await dart(
      [
        File.fromUri(worker.resolve('ExtractFlutterDependencies.dart')).path,
        '--project',
        source.path,
        '--destination',
        '${root.path}/exports',
      ],
      workingDirectory: root.path,
      cache: cache,
    );
    expect(
      exported.exitCode == 0,
      '真实导出失败：${exported.stdout}\n${exported.stderr}',
    );
    final snapshot = Directory('${root.path}/exports')
        .listSync()
        .whereType<Directory>()
        .single;
    final originalForms = <String, String?>{
      'new': null,
      'block': '# keep original\ndependency_overrides:\n  unrelated:\n    path: local-unrelated\n',
      'flow': 'dependency_overrides: {unrelated: {path: "local-unrelated"}} # keep flow\n',
      'crlf': '# keep CRLF\r\ndependency_overrides:\r\n  unrelated:\r\n    path: local-unrelated\r\n',
      'empty': 'dependency_overrides: {} # keep empty comment\n',
      'block4': 'dependency_overrides:\n    unrelated:\n        path: local-unrelated\n',
      'marked': '---\ndependency_overrides:\n  unrelated:\n    path: local-unrelated\n...\n',
      'spaced-empty': 'dependency_overrides: { } # keep spaced empty comment\n',
    };
    for (final entry in originalForms.entries) {
      final target = Directory('${root.path}/target-${entry.key}')
        ..createSync();
      write('${target.path}/pubspec.yaml', flutterProject);
      write(
        '${target.path}/local-unrelated/pubspec.yaml',
        'name: unrelated\nversion: 2.0.0\n$sdkConstraint',
      );
      write('${target.path}/local-unrelated/lib/unrelated.dart', '// local\n');
      if (entry.value != null) {
        write('${target.path}/pubspec_overrides.yaml', entry.value!);
      }
      final imported = await dart(
        [
          File.fromUri(worker.resolve('ImportFlutterDependencies.dart')).path,
          '--project',
          target.path,
          '--source',
          snapshot.path,
        ],
        workingDirectory: root.path,
        cache: cache,
      );
      expect(
        imported.exitCode == 0,
        '${entry.key} 导入失败：${imported.stdout}\n${imported.stderr}',
      );
      final run = Directory('${target.path}/vendor/flutter_dependencies')
          .listSync()
          .whereType<Directory>()
          .single;
      if (entry.value != null) {
        expect(
          File('${run.path}/pubspec_overrides.yaml.before-import')
                  .readAsStringSync() ==
              entry.value,
          '${entry.key} 原配置备份字节不一致',
        );
      }
      final overrides = File('${target.path}/pubspec_overrides.yaml');
      final produced = overrides.readAsBytesSync();
      // 只移除临时根项目的 Flutter SDK 声明；直接复用生成配置和完整 vendor，交给独立 Pub 解析。
      write(
        '${target.path}/pubspec.yaml',
        'name: pub_consumer\n${sdkConstraint}dependencies:\n  alpha: ^1.0.0\n',
      );
      final resolved = await dart(
        ['pub', 'get', '--offline', '--no-precompile'],
        workingDirectory: target.path,
        cache: cache,
      );
      expect(
        resolved.exitCode == 0,
        '${entry.key} Pub 拒绝导入配置：${resolved.stdout}\n${resolved.stderr}',
      );
      expect(
        base64Encode(overrides.readAsBytesSync()) == base64Encode(produced),
        '${entry.key} 验收期间生成配置发生变化',
      );
      final config = File('${target.path}/.dart_tool/package_config.json');
      final parsed = jsonDecode(config.readAsStringSync()) as Map;
      final packages = {
        for (final item in parsed['packages'] as List)
          (item as Map)['name'] as String: item,
      };
      for (final name in ['alpha', 'beta']) {
        final item = packages[name];
        expect(item != null, '${entry.key} Pub 未解析 $name');
        final actual = Directory.fromUri(
          config.uri.resolve(item!['rootUri'] as String),
        ).resolveSymbolicLinksSync();
        final expected = Directory('${run.path}/packages/$name')
            .resolveSymbolicLinksSync();
        expect(
          actual == expected,
          '${entry.key} $name 未生效：$actual ≠ $expected',
        );
      }
      if (['block', 'flow', 'crlf', 'block4', 'marked'].contains(entry.key)) {
        final item = packages['unrelated'];
        expect(item != null, '${entry.key} 原不冲突覆盖被丢失');
        expect(
          Directory.fromUri(config.uri.resolve(item!['rootUri'] as String))
                  .resolveSymbolicLinksSync() ==
              Directory('${target.path}/local-unrelated')
                  .resolveSymbolicLinksSync(),
          '${entry.key} 原覆盖路径未生效',
        );
      }
      cases++;
      stdout.writeln(
        'PASS: ${entry.key} · Dart Pub --offline 使用本地 alpha / beta',
      );
    }
    // 同源 Git 覆盖须被本地 path 实际取代；保留原 Git 声明交给独立 Pub 作判据。
    const gitOverride = '''dependency_overrides:
  alpha:
    git:
      url: https://example.invalid/team/packages.git
      ref: revision-a
      path: packages/alpha
''';
    final originalPubspec = '$flutterProject$gitOverride';
    write('${source.path}/pubspec.yaml', originalPubspec);
    final sourceLock = File('${source.path}/pubspec.lock');
    sourceLock.writeAsStringSync(
      sourceLock.readAsStringSync().replaceFirst(
        'source: hosted',
        'source: git',
      ),
    );
    File('${source.path}/.dart_tool/package_config.json')
        .setLastModifiedSync(DateTime.now().add(const Duration(seconds: 1)));
    final gitExport = await dart(
      [
        File.fromUri(worker.resolve('ExtractFlutterDependencies.dart')).path,
        '--project',
        source.path,
        '--destination',
        '${root.path}/exports-with-git-override',
      ],
      workingDirectory: root.path,
      cache: cache,
    );
    expect(
      gitExport.exitCode == 0,
      'Git 覆盖归档失败：${gitExport.stdout}\n${gitExport.stderr}',
    );
    final gitSnapshot = Directory('${root.path}/exports-with-git-override')
        .listSync()
        .whereType<Directory>()
        .single;
    final gitTarget = Directory('${root.path}/target-original-git-override')
      ..createSync();
    write('${gitTarget.path}/pubspec.yaml', originalPubspec);
    final pubspecBytes = File('${gitTarget.path}/pubspec.yaml')
        .readAsBytesSync();
    final gitImport = await dart(
      [
        File.fromUri(worker.resolve('ImportFlutterDependencies.dart')).path,
        '--project',
        gitTarget.path,
        '--source',
        gitSnapshot.path,
      ],
      workingDirectory: root.path,
      cache: cache,
    );
    expect(
      gitImport.exitCode == 0,
      '同源 Git 覆盖导入失败：${gitImport.stdout}\n${gitImport.stderr}',
    );
    expect(
      base64Encode(File('${gitTarget.path}/pubspec.yaml').readAsBytesSync()) ==
          base64Encode(pubspecBytes),
      '导入改写了原始 Git 覆盖声明',
    );
    final gitRun = Directory('${gitTarget.path}/vendor/flutter_dependencies')
        .listSync()
        .whereType<Directory>()
        .single;
    final producedOverrides = File('${gitTarget.path}/pubspec_overrides.yaml')
        .readAsBytesSync();
    write(
      '${gitTarget.path}/pubspec.yaml',
      'name: pub_consumer\n${sdkConstraint}dependencies:\n  alpha: ^1.0.0\n$gitOverride',
    );
    final gitResolved = await dart(
      ['pub', 'get', '--offline', '--no-precompile'],
      workingDirectory: gitTarget.path,
      cache: cache,
    );
    expect(
      gitResolved.exitCode == 0,
      'Pub 未使用 path 取代原 Git 覆盖：${gitResolved.stdout}\n${gitResolved.stderr}',
    );
    expect(
      base64Encode(
            File('${gitTarget.path}/pubspec_overrides.yaml').readAsBytesSync(),
          ) ==
          base64Encode(producedOverrides),
      'Pub 验收改写了生成覆盖配置',
    );
    final gitConfig = File('${gitTarget.path}/.dart_tool/package_config.json');
    final gitPackages = {
      for (final item
          in (jsonDecode(gitConfig.readAsStringSync()) as Map)['packages']
              as List)
        (item as Map)['name'] as String: item,
    };
    for (final name in ['alpha', 'beta']) {
      final item = gitPackages[name];
      expect(item != null, 'Pub 未解析原 Git 覆盖快照中的 $name');
      expect(
        Directory.fromUri(gitConfig.uri.resolve(item!['rootUri'] as String))
                .resolveSymbolicLinksSync() ==
            Directory('${gitRun.path}/packages/$name')
                .resolveSymbolicLinksSync(),
        '原 Git 覆盖未恢复为导入的本地 $name',
      );
    }
    cases++;
    stdout.writeln(
      'PASS: original-git-override · Dart Pub --offline 使用本地 alpha / beta',
    );
    stdout.writeln(
      'PASS: $cases independent Dart Pub resolution cases; isolated cache, no network',
    );
  } finally {
    root.deleteSync(recursive: true);
  }
}
