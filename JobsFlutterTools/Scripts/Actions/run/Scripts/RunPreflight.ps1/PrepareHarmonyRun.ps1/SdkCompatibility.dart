// Created by Jobs on 2026年11月10日，星期二.
// 用当前 SDK 已缓存的标准 YAML / pub_semver 解释工程约束，不改 pubspec。
import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

void main(List<String> args) {
  try {
    if (args.length != 4) throw ArgumentError('Expected project, mode, Flutter and Dart version.');
    final document = loadYaml(File('${args[0]}/pubspec.yaml').readAsStringSync());
    if (document is! YamlMap || document['name'] is! String) throw StateError('Invalid project metadata.');
    final environment = document['environment'];
    VersionConstraint constraint(String key) {
      final value = environment is YamlMap ? environment[key] : null;
      if (value == null) return VersionConstraint.any;
      if (value is! String) throw StateError('Invalid SDK constraint.');
      return VersionConstraint.parse(value);
    }

    Version version(String value) => Version.parse(value.trim().split(' ').first.replaceFirst(RegExp(r'^v'), ''));
    final flutterOk = constraint('flutter').allows(version(args[2]));
    final dartOk = args[1] == 'flutter' || constraint('sdk').allows(version(args[3]));
    if (args[1] != 'flutter' && args[1] != 'sdk') throw ArgumentError('Invalid mode.');
    stdout.writeln(jsonEncode({
      'schemaVersion': 1,
      'compatible': flutterOk && dartOk,
      'projectName': document['name'],
      'reason': !flutterOk ? 'Flutter 版本不符合工程 environment.flutter 约束。' : !dartOk ? 'Dart 版本不符合工程 environment.sdk 约束。' : '',
    }));
    exit(flutterOk && dartOk ? 0 : 1);
  } catch (_) {
    stderr.writeln('无法完整解析工程 SDK 约束或候选版本；未修改工程。');
    exit(2);
  }
}
