import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../infrastructure/tools/workspace_tools.dart';
import 'project_kind.dart';

/// Identifies the primary project type from files inside a workspace sandbox.
class ProjectKindDetector {
  const ProjectKindDetector();

  Future<ProjectKindDetection> detect(String workspacePath) async {
    final sandbox = WorkspaceSandbox(workspacePath);
    final names = await _topLevelNames(workspacePath);
    final signals = <ProjectKindSignal>[];

    if (_hasAny(names, const {'pubspec.yaml', 'pubspec.yml'})) {
      final pubspec = await _readText(sandbox, 'pubspec.yaml') ??
          await _readText(sandbox, 'pubspec.yml') ??
          '';
      final flutterSdk = RegExp(r'^\s*flutter\s*:', multiLine: true)
          .hasMatch(pubspec);
      if (flutterSdk) {
        signals.add(const ProjectKindSignal(
          path: 'pubspec.yaml',
          reason: '声明了 Flutter SDK 依赖',
        ));
        return ProjectKindDetection(
          kind: ProjectKind.flutter,
          confidence: 0.98,
          signals: signals,
          packageName: _yamlField(pubspec, 'name'),
          testCommand: 'flutter test',
          buildCommand: 'flutter build apk --release',
        );
      }
    }

    if (_hasAny(names, const {
          'settings.gradle',
          'settings.gradle.kts',
          'build.gradle',
          'build.gradle.kts',
        }) ||
        names.contains('gradlew') ||
        names.contains('gradlew.bat')) {
      signals.add(ProjectKindSignal(
        path: names.contains('settings.gradle.kts')
            ? 'settings.gradle.kts'
            : names.contains('settings.gradle')
                ? 'settings.gradle'
                : 'build.gradle',
        reason: '检测到 Gradle 工程文件',
      ));
      final manifest = await _readText(
            sandbox,
            'app/src/main/AndroidManifest.xml',
          ) ??
          await _readText(sandbox, 'src/main/AndroidManifest.xml') ??
          '';
      return ProjectKindDetection(
        kind: ProjectKind.androidGradle,
        confidence: manifest.contains('<manifest') ? 0.95 : 0.8,
        signals: signals,
        packageName: _androidPackage(manifest),
        testCommand: _gradleCommand(names, 'test'),
        buildCommand: _gradleCommand(names, 'assembleRelease'),
      );
    }

    if (names.contains('package.json')) {
      final packageJson = await _readText(sandbox, 'package.json') ?? '{}';
      Map<String, dynamic> decoded = const {};
      try {
        final raw = jsonDecode(packageJson);
        if (raw is Map<String, dynamic>) decoded = raw;
      } catch (_) {}
      final scripts = decoded['scripts'] is Map
          ? Map<String, dynamic>.from(decoded['scripts'] as Map)
          : const <String, dynamic>{};
      signals.add(const ProjectKindSignal(
        path: 'package.json',
        reason: '检测到 Node 包清单',
      ));
      return ProjectKindDetection(
        kind: ProjectKind.node,
        confidence: 0.9,
        signals: signals,
        packageName: decoded['name']?.toString(),
        testCommand: _npmScript(scripts, const ['test', 'check']),
        buildCommand: _npmScript(scripts, const ['build', 'compile']),
      );
    }

    if (names.contains('go.mod')) {
      signals.add(const ProjectKindSignal(
        path: 'go.mod',
        reason: '检测到 Go 模块',
      ));
      return const ProjectKindDetection(
        kind: ProjectKind.go,
        confidence: 0.9,
        signals: [
          ProjectKindSignal(path: 'go.mod', reason: '检测到 Go 模块'),
        ],
        testCommand: 'go test ./...',
        buildCommand: 'go build -o dist/app ./...',
      );
    }

    if (_hasAny(names, const {
      'pyproject.toml',
      'requirements.txt',
      'setup.py',
      'Pipfile',
    })) {
      final marker = names.contains('pyproject.toml')
          ? 'pyproject.toml'
          : names.contains('requirements.txt')
              ? 'requirements.txt'
              : names.contains('Pipfile')
                  ? 'Pipfile'
                  : 'setup.py';
      signals.add(ProjectKindSignal(
        path: marker,
        reason: '检测到 Python 工程清单',
      ));
      return ProjectKindDetection(
        kind: ProjectKind.python,
        confidence: 0.82,
        signals: signals,
        testCommand: names.contains('pytest.ini') || names.contains('tests')
            ? 'python -m pytest'
            : 'python -m unittest',
      );
    }

    if (names.contains('AndroidManifest.xml') && names.contains('build.sh')) {
      signals.add(const ProjectKindSignal(
        path: 'AndroidManifest.xml',
        reason: '检测到无 Gradle 的小型 Java APK 模板',
      ));
      final manifest =
          await _readText(sandbox, 'AndroidManifest.xml') ?? '';
      return ProjectKindDetection(
        kind: ProjectKind.javaApk,
        confidence: 0.8,
        signals: signals,
        buildCommand: 'sh build.sh',
        packageName: _androidPackage(manifest) ?? 'com.nexus.starter',
      );
    }

    if (_hasAny(names, const {'index.html', 'index.htm'}) ||
        names.contains('web')) {
      signals.add(const ProjectKindSignal(
        path: 'index.html',
        reason: '检测到静态网页入口',
      ));
      return const ProjectKindDetection(
        kind: ProjectKind.staticWeb,
        confidence: 0.7,
        signals: [
          ProjectKindSignal(path: 'index.html', reason: '检测到静态网页入口'),
        ],
      );
    }

    return const ProjectKindDetection(
      kind: ProjectKind.unknown,
      confidence: 0.1,
      signals: [],
    );
  }

  Future<Set<String>> _topLevelNames(String workspacePath) async {
    final dir = Directory(workspacePath);
    if (!await dir.exists()) return const {};
    final names = <String>{};
    await for (final entity in dir.list(followLinks: false)) {
      names.add(p.basename(entity.path));
    }
    return names;
  }

  Future<String?> _readText(WorkspaceSandbox sandbox, String relative) async {
    try {
      final file = File(sandbox.resolvePath(relative));
      if (!await file.exists()) return null;
      return await file.readAsString();
    } on ArgumentError {
      return null;
    } catch (_) {
      return null;
    }
  }

  bool _hasAny(Set<String> names, Set<String> expected) =>
      expected.any(names.contains);

  String? _yamlField(String source, String key) {
    final match = RegExp('^$key:\\s*(.+)\$', multiLine: true).firstMatch(source);
    return match?.group(1)?.trim();
  }

  String? _androidPackage(String manifest) {
    final match = RegExp(r'package="([^"]+)"').firstMatch(manifest);
    return match?.group(1);
  }

  String _gradleCommand(Set<String> names, String task) {
    if (names.contains('gradlew.bat') || names.contains('gradlew')) {
      return 'gradlew $task';
    }
    return 'gradle $task';
  }

  String? _npmScript(Map<String, dynamic> scripts, List<String> preferred) {
    for (final name in preferred) {
      if (scripts.containsKey(name)) return 'npm run $name';
    }
    return null;
  }
}
