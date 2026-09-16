import 'dart:convert';

import 'project_kind.dart';

class ProjectSettings {
  const ProjectSettings({
    this.goal,
    this.constraints = const [],
    this.testCommand,
    this.buildCommand,
    this.previewCommand,
    this.previewPort,
    this.allowLanPreview = false,
    this.providerProfileId,
    this.budgetTokens,
    this.packageName,
    this.appName,
  });

  final String? goal;
  final List<String> constraints;
  final String? testCommand;
  final String? buildCommand;
  final String? previewCommand;
  final int? previewPort;
  final bool allowLanPreview;
  final String? providerProfileId;
  final int? budgetTokens;
  final String? packageName;
  final String? appName;

  static const version = 1;

  Map<String, dynamic> toJson() => {
        'version': version,
        if (goal != null) 'goal': goal,
        if (constraints.isNotEmpty) 'constraints': constraints,
        if (testCommand != null) 'testCommand': testCommand,
        if (buildCommand != null) 'buildCommand': buildCommand,
        if (previewCommand != null) 'previewCommand': previewCommand,
        if (previewPort != null) 'previewPort': previewPort,
        'allowLanPreview': allowLanPreview,
        if (providerProfileId != null) 'providerProfileId': providerProfileId,
        if (budgetTokens != null) 'budgetTokens': budgetTokens,
        if (packageName != null) 'packageName': packageName,
        if (appName != null) 'appName': appName,
      };

  factory ProjectSettings.fromJson(Map<String, dynamic> json) {
    final constraints = json['constraints'];
    return ProjectSettings(
      goal: json['goal']?.toString(),
      constraints: constraints is List
          ? constraints.map((item) => item.toString()).toList(growable: false)
          : const [],
      testCommand: json['testCommand']?.toString(),
      buildCommand: json['buildCommand']?.toString(),
      previewCommand: json['previewCommand']?.toString(),
      previewPort: (json['previewPort'] as num?)?.toInt(),
      allowLanPreview: json['allowLanPreview'] == true,
      providerProfileId: json['providerProfileId']?.toString(),
      budgetTokens: (json['budgetTokens'] as num?)?.toInt(),
      packageName: json['packageName']?.toString(),
      appName: json['appName']?.toString(),
    );
  }

  factory ProjectSettings.decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return ProjectSettings.fromJson(decoded);
      if (decoded is Map) {
        return ProjectSettings.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return const ProjectSettings();
  }

  String encode() => jsonEncode(toJson());

  ProjectSettings copyWith({
    String? goal,
    List<String>? constraints,
    String? testCommand,
    String? buildCommand,
    String? previewCommand,
    int? previewPort,
    bool? allowLanPreview,
    String? providerProfileId,
    int? budgetTokens,
    String? packageName,
    String? appName,
  }) {
    return ProjectSettings(
      goal: goal ?? this.goal,
      constraints: constraints ?? this.constraints,
      testCommand: testCommand ?? this.testCommand,
      buildCommand: buildCommand ?? this.buildCommand,
      previewCommand: previewCommand ?? this.previewCommand,
      previewPort: previewPort ?? this.previewPort,
      allowLanPreview: allowLanPreview ?? this.allowLanPreview,
      providerProfileId: providerProfileId ?? this.providerProfileId,
      budgetTokens: budgetTokens ?? this.budgetTokens,
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
    );
  }

  ProjectSettings mergeDetection(ProjectKindDetection detection) {
    return ProjectSettings(
      goal: goal,
      constraints: constraints,
      testCommand: testCommand ?? detection.testCommand,
      buildCommand: buildCommand ?? detection.buildCommand,
      previewCommand: previewCommand,
      previewPort: previewPort,
      allowLanPreview: allowLanPreview,
      providerProfileId: providerProfileId,
      budgetTokens: budgetTokens,
      packageName: packageName ?? detection.packageName,
      appName: appName,
    );
  }
}
