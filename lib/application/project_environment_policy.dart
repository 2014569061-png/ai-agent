import '../infrastructure/terminal/linux_runtime.dart';
import 'project_kind.dart';
import 'project_settings.dart';
import 'project_template_service.dart';

class ProjectToolRequirement {
  const ProjectToolRequirement({
    required this.id,
    required this.label,
    required this.checkCommand,
    this.required = true,
    this.installHint,
    this.alpinePackages = const [],
    this.termuxPackages = const [],
  });

  final String id;
  final String label;
  final String checkCommand;
  final bool required;

  /// 给用户看的能力说明（不是命令）。真正的安装命令由
  /// [ProjectEnvironmentPolicy.installCommandFor] 按运行时生成。
  final String? installHint;

  /// Alpine（内置 PRoot）下 `apk add` 的包名；空表示该工具不能经包管理器安装。
  final List<String> alpinePackages;

  /// Termux 下 `pkg install` 的包名；空表示该工具不能经包管理器安装。
  final List<String> termuxPackages;
}

class ProjectEnvironmentPolicy {
  const ProjectEnvironmentPolicy();

  List<ProjectToolRequirement> requirementsFor(ProjectKind kind) {
    return switch (kind) {
      ProjectKind.staticWeb => const [
          ProjectToolRequirement(
            id: 'preview',
            label: '静态预览',
            checkCommand: 'python3 -m http.server --help',
            required: false,
            installHint: '安装 Python 后可启动本地预览',
            alpinePackages: ['python3'],
            termuxPackages: ['python'],
          ),
        ],
      ProjectKind.node => const [
          ProjectToolRequirement(
            id: 'node',
            label: 'Node.js',
            checkCommand: 'node --version',
            installHint: '从 Alpine 软件源安装 nodejs 与 npm',
            alpinePackages: ['nodejs', 'npm'],
            termuxPackages: ['nodejs'],
          ),
          ProjectToolRequirement(
            id: 'npm',
            label: 'npm',
            checkCommand: 'npm --version',
            installHint: '随 Node.js 一起安装 npm',
            alpinePackages: ['npm'],
            termuxPackages: ['nodejs'],
          ),
        ],
      ProjectKind.python => const [
          ProjectToolRequirement(
            id: 'python',
            label: 'Python',
            checkCommand: 'python3 --version',
            installHint: '从 Alpine 软件源安装 python3',
            alpinePackages: ['python3'],
            termuxPackages: ['python'],
          ),
        ],
      ProjectKind.javaApk => const [
          ProjectToolRequirement(
            id: 'sh',
            label: 'POSIX shell',
            checkCommand: 'sh -c echo',
          ),
          ProjectToolRequirement(
            id: 'javac',
            label: 'JDK / javac',
            checkCommand: 'javac -version',
            installHint: '从 Alpine 软件源安装 openjdk17',
            alpinePackages: ['openjdk17'],
            termuxPackages: ['openjdk-17'],
          ),
          ProjectToolRequirement(
            id: 'aapt2',
            label: 'aapt2',
            checkCommand: 'aapt2 version',
            required: false,
            installHint: '配置 ANDROID_HOME 后使用 SDK 中的 aapt2',
          ),
          ProjectToolRequirement(
            id: 'd8',
            label: 'd8',
            checkCommand: 'd8 --help',
            required: false,
            installHint: '配置 ANDROID_HOME 后使用 SDK 中的 d8',
          ),
        ],
      ProjectKind.flutter => const [
          ProjectToolRequirement(
            id: 'flutter',
            label: 'Flutter SDK',
            checkCommand: 'flutter --version',
            required: false,
            installHint: '当前环境未内置 Flutter，需自定义命令或外置 SDK',
          ),
        ],
      ProjectKind.androidGradle => const [
          ProjectToolRequirement(
            id: 'gradlew',
            label: 'Gradle Wrapper',
            checkCommand: './gradlew --version',
            required: false,
            installHint: '项目需自带 gradlew，应用不会默认走系统 Gradle',
          ),
        ],
      ProjectKind.go => const [
          ProjectToolRequirement(
            id: 'go',
            label: 'Go',
            checkCommand: 'go version',
            required: false,
            installHint: '从 Alpine 软件源安装 go',
            alpinePackages: ['go'],
            termuxPackages: ['golang'],
          ),
        ],
      ProjectKind.unknown => const [],
    };
  }

  /// 按当前运行时生成真实的安装命令。
  ///
  /// 以前安装作业直接把 `installHint` 当命令执行，而它是中文说明，例如
  /// 「apk add nodejs npm 或在 Termux 执行 pkg install nodejs」——apk 会把这整句
  /// 当成包名解析，必然失败。这里按运行时拼出可直接执行的命令。
  ///
  /// 返回 null 表示该工具在当前运行时没有包管理器可用（例如 Android Shell），
  /// 调用方必须据此如实告知用户，不能伪造一步「安装」。
  String? installCommandFor(
    ProjectToolRequirement requirement,
    LinuxRuntimeKind kind,
  ) {
    switch (kind) {
      case LinuxRuntimeKind.builtinProot:
        if (requirement.alpinePackages.isEmpty) return null;
        return 'apk add --no-cache ${requirement.alpinePackages.join(' ')}';
      case LinuxRuntimeKind.termux:
        if (requirement.termuxPackages.isEmpty) return null;
        return 'pkg install -y ${requirement.termuxPackages.join(' ')}';
      case LinuxRuntimeKind.hostProcess:
      case LinuxRuntimeKind.androidShell:
        return null;
    }
  }

  List<ProjectToolRequirement> requirementsForTemplate(ProjectTemplate template) {
    final extras = <ProjectToolRequirement>[];
    if (template.settings.previewCommand?.trim().isNotEmpty == true) {
      extras.add(ProjectToolRequirement(
        id: 'preview-command',
        label: '预览命令',
        checkCommand: template.settings.previewCommand!,
        required: false,
      ));
    }
    return [
      ...requirementsFor(template.kind),
      ...extras.where((item) =>
          !requirementsFor(template.kind).any((existing) => existing.id == item.id)),
    ];
  }

  String? blockedReason({
    required ProjectKind kind,
    required ProjectSettings settings,
    required Map<String, bool> toolAvailability,
  }) {
    for (final requirement in requirementsFor(kind)) {
      if (!requirement.required) continue;
      if (toolAvailability[requirement.id] != true) {
        return '缺少 ${requirement.label}';
      }
    }
    if (kind == ProjectKind.javaApk &&
        (settings.buildCommand ?? '').contains('flutter')) {
      return 'Java APK 模板不能使用 Flutter/Gradle 默认命令';
    }
    return null;
  }
}