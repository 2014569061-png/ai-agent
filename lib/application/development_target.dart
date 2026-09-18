import 'project_kind.dart';

/// 用户真正想完成的开发目标。
///
/// 它与 [ProjectKind] 分开：ProjectKind 描述已经存在的工程，
/// DevelopmentTarget 描述用户现在想做什么。这样没有工作区时也能先选择
/// “静态网页”或“Windows .exe”，而不会把所有运行时工具都判为必需。
enum DevelopmentTarget {
  staticWeb,
  nodeWeb,
  python,
  go,
  flutterAndroid,
  androidNative,
  windowsExe,
}

class DevelopmentTargetTool {
  const DevelopmentTargetTool({
    required this.id,
    required this.label,
    required this.description,
    this.required = true,
    this.installHint,
    this.alpinePackages = const [],
    this.termuxPackages = const [],
  });

  final String id;
  final String label;
  final String description;
  final bool required;
  final String? installHint;
  final List<String> alpinePackages;
  final List<String> termuxPackages;

  bool get canInstallOnLinux =>
      alpinePackages.isNotEmpty || termuxPackages.isNotEmpty;
}

extension DevelopmentTargetX on DevelopmentTarget {
  static const storageKey = 'settings.development.target';

  String get id => name;

  String get label => switch (this) {
        DevelopmentTarget.staticWeb => '静态网页',
        DevelopmentTarget.nodeWeb => 'Node Web / Electron',
        DevelopmentTarget.python => 'Python 程序',
        DevelopmentTarget.go => 'Go 程序',
        DevelopmentTarget.flutterAndroid => 'Flutter Android',
        DevelopmentTarget.androidNative => '原生 Android',
        DevelopmentTarget.windowsExe => 'Windows .exe',
      };

  String get description => switch (this) {
        DevelopmentTarget.staticWeb => 'HTML、CSS、JavaScript，可直接创建和预览',
        DevelopmentTarget.nodeWeb => 'Vite、React、Vue、Next.js 或 Electron',
        DevelopmentTarget.python => 'Python 脚本、自动化或可打包程序',
        DevelopmentTarget.go => 'Go 命令行程序或服务',
        DevelopmentTarget.flutterAndroid => 'Flutter 项目并构建 Android APK',
        DevelopmentTarget.androidNative => 'Kotlin/Java Android 项目',
        DevelopmentTarget.windowsExe => 'Electron、Tauri、Python、Go 等 Windows 程序',
      };

  String get environmentNote => switch (this) {
        DevelopmentTarget.staticWeb =>
          '不需要 Node.js、Python、Flutter、JDK 或 Android SDK；文件工具即可创建网页。',
        DevelopmentTarget.nodeWeb => '需要 Node.js 和 npm；只写静态网页时可以不安装它们。',
        DevelopmentTarget.python => '需要 Python；pip 只在安装第三方依赖时需要。',
        DevelopmentTarget.go => '需要 Go 编译器；只编辑源码不需要立即安装。',
        DevelopmentTarget.flutterAndroid =>
          '需要 Flutter SDK、JDK 和 Android SDK；体积较大，不会被一键常用工具安装。',
        DevelopmentTarget.androidNative =>
          '需要 JDK 和 Android SDK；项目自带 Gradle Wrapper 时不需要单独安装 Gradle。',
        DevelopmentTarget.windowsExe =>
          '当前手机 Linux/Alpine 环境不能直接产出 Windows .exe；请在 Windows 宿主机配置对应工具链。',
      };

  ProjectKind? get projectKind => switch (this) {
        DevelopmentTarget.staticWeb => ProjectKind.staticWeb,
        DevelopmentTarget.nodeWeb => ProjectKind.node,
        DevelopmentTarget.python => ProjectKind.python,
        DevelopmentTarget.go => ProjectKind.go,
        DevelopmentTarget.flutterAndroid => ProjectKind.flutter,
        DevelopmentTarget.androidNative => ProjectKind.androidGradle,
        DevelopmentTarget.windowsExe => null,
      };

  bool get canBuildHere => switch (this) {
        DevelopmentTarget.staticWeb => true,
        DevelopmentTarget.nodeWeb => true,
        DevelopmentTarget.python => true,
        DevelopmentTarget.go => true,
        DevelopmentTarget.flutterAndroid => false,
        DevelopmentTarget.androidNative => false,
        DevelopmentTarget.windowsExe => false,
      };

  bool get canInstallHere => tools.any((tool) => tool.canInstallOnLinux);

  List<DevelopmentTargetTool> get tools => switch (this) {
        DevelopmentTarget.staticWeb => const [],
        DevelopmentTarget.nodeWeb => const [
            DevelopmentTargetTool(
              id: 'node',
              label: 'Node.js',
              description: '运行前端开发服务器、Electron 和 Node 脚本',
              alpinePackages: ['nodejs', 'npm'],
              termuxPackages: ['nodejs'],
            ),
            DevelopmentTargetTool(
              id: 'npm',
              label: 'npm',
              description: '安装 JavaScript 项目依赖',
              alpinePackages: ['npm'],
              termuxPackages: ['nodejs'],
            ),
          ],
        DevelopmentTarget.python => const [
            DevelopmentTargetTool(
              id: 'python',
              label: 'Python',
              description: '运行 Python 脚本和本地开发服务',
              alpinePackages: ['python3'],
              termuxPackages: ['python'],
            ),
          ],
        DevelopmentTarget.go => const [
            DevelopmentTargetTool(
              id: 'go',
              label: 'Go',
              description: '编译 Go 程序和运行 go test',
              alpinePackages: ['go'],
              termuxPackages: ['golang'],
            ),
          ],
        DevelopmentTarget.flutterAndroid => const [
            DevelopmentTargetTool(
              id: 'flutter',
              label: 'Flutter SDK',
              description: 'Flutter 项目工具链',
              installHint: '当前页面不自动下载 Flutter SDK，请按项目需要配置外部 SDK。',
            ),
            DevelopmentTargetTool(
              id: 'javac',
              label: 'JDK / javac',
              description: '编译 Android 端 Java/Kotlin 依赖',
              alpinePackages: ['openjdk17'],
              termuxPackages: ['openjdk-17'],
            ),
            DevelopmentTargetTool(
              id: 'aapt2',
              label: 'Android SDK Build Tools / aapt2',
              description: 'Android SDK 的资源打包工具',
              installHint: '由 Android SDK Build Tools 提供。',
            ),
            DevelopmentTargetTool(
              id: 'd8',
              label: 'd8',
              description: 'Android 字节码转换工具',
              required: false,
              installHint: '由 Android SDK Build Tools 提供。',
            ),
          ],
        DevelopmentTarget.androidNative => const [
            DevelopmentTargetTool(
              id: 'javac',
              label: 'JDK / javac',
              description: '编译 Kotlin/Java Android 源码',
              alpinePackages: ['openjdk17'],
              termuxPackages: ['openjdk-17'],
            ),
            DevelopmentTargetTool(
              id: 'gradlew',
              label: 'Gradle Wrapper',
              description: '优先使用项目内置的 gradlew/gradlew.bat',
              required: false,
              installHint: '项目自带 Wrapper 时无需安装系统 Gradle。',
            ),
            DevelopmentTargetTool(
              id: 'aapt2',
              label: 'Android SDK Build Tools / aapt2',
              description: 'Android SDK 的资源打包工具',
              installHint: '由 Android SDK Build Tools 提供。',
            ),
            DevelopmentTargetTool(
              id: 'd8',
              label: 'd8',
              description: 'Android 字节码转换工具',
              required: false,
              installHint: '由 Android SDK Build Tools 提供。',
            ),
          ],
        DevelopmentTarget.windowsExe => const [],
      };

  static DevelopmentTarget? parse(String? value) {
    final normalized = value?.trim();
    for (final target in DevelopmentTarget.values) {
      if (target.id == normalized) return target;
    }
    return null;
  }

  static DevelopmentTarget? fromProjectKind(ProjectKind kind) => switch (kind) {
        ProjectKind.staticWeb => DevelopmentTarget.staticWeb,
        ProjectKind.node => DevelopmentTarget.nodeWeb,
        ProjectKind.python => DevelopmentTarget.python,
        ProjectKind.go => DevelopmentTarget.go,
        ProjectKind.flutter => DevelopmentTarget.flutterAndroid,
        ProjectKind.androidGradle => DevelopmentTarget.androidNative,
        ProjectKind.javaApk => DevelopmentTarget.androidNative,
        ProjectKind.unknown => null,
      };
}
