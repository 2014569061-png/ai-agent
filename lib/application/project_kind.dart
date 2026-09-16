enum ProjectKind {
  flutter,
  androidGradle,
  node,
  python,
  staticWeb,
  go,
  javaApk,
  unknown,
}

extension ProjectKindX on ProjectKind {
  String get id => switch (this) {
        ProjectKind.flutter => 'flutter',
        ProjectKind.androidGradle => 'android-gradle',
        ProjectKind.node => 'node',
        ProjectKind.python => 'python',
        ProjectKind.staticWeb => 'static-web',
        ProjectKind.go => 'go',
        ProjectKind.javaApk => 'java-apk',
        ProjectKind.unknown => 'unknown',
      };

  String get label => switch (this) {
        ProjectKind.flutter => 'Flutter',
        ProjectKind.androidGradle => 'Android Gradle',
        ProjectKind.node => 'Node',
        ProjectKind.python => 'Python',
        ProjectKind.staticWeb => '静态网页',
        ProjectKind.go => 'Go',
        ProjectKind.javaApk => '小型 Java APK',
        ProjectKind.unknown => '未知项目',
      };

  static ProjectKind parse(String? value) => switch (value?.trim()) {
        'flutter' => ProjectKind.flutter,
        'android-gradle' => ProjectKind.androidGradle,
        'node' => ProjectKind.node,
        'python' => ProjectKind.python,
        'static-web' => ProjectKind.staticWeb,
        'go' => ProjectKind.go,
        'java-apk' => ProjectKind.javaApk,
        _ => ProjectKind.unknown,
      };
}

class ProjectKindSignal {
  const ProjectKindSignal({required this.path, required this.reason});

  final String path;
  final String reason;

  Map<String, dynamic> toJson() => {'path': path, 'reason': reason};

  factory ProjectKindSignal.fromJson(Map<String, dynamic> json) =>
      ProjectKindSignal(
        path: json['path']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
      );
}

class ProjectKindDetection {
  const ProjectKindDetection({
    required this.kind,
    required this.confidence,
    required this.signals,
    this.packageName,
    this.testCommand,
    this.buildCommand,
  });

  final ProjectKind kind;
  final double confidence;
  final List<ProjectKindSignal> signals;
  final String? packageName;
  final String? testCommand;
  final String? buildCommand;

  bool get isKnown => kind != ProjectKind.unknown;

  Map<String, dynamic> toJson() => {
        'kind': kind.id,
        'confidence': confidence,
        'signals': signals.map((signal) => signal.toJson()).toList(),
        if (packageName != null) 'packageName': packageName,
        if (testCommand != null) 'testCommand': testCommand,
        if (buildCommand != null) 'buildCommand': buildCommand,
      };

  factory ProjectKindDetection.fromJson(Map<String, dynamic> json) {
    final rawSignals = json['signals'] as List? ?? const [];
    return ProjectKindDetection(
      kind: ProjectKindX.parse(json['kind']?.toString()),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      signals: rawSignals
          .whereType<Map>()
          .map((item) =>
              ProjectKindSignal.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      packageName: json['packageName']?.toString(),
      testCommand: json['testCommand']?.toString(),
      buildCommand: json['buildCommand']?.toString(),
    );
  }
}
