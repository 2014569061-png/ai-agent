import '../infrastructure/observability/unified_diff.dart';
import 'development_verification.dart';

enum ChangeVerificationMark {
  unverified,
  passed,
  failed,
}

extension ChangeVerificationMarkX on ChangeVerificationMark {
  String get id => name;

  String get label => switch (this) {
        ChangeVerificationMark.unverified => '未验证',
        ChangeVerificationMark.passed => '验证通过',
        ChangeVerificationMark.failed => '验证失败',
      };

  static ChangeVerificationMark parse(String? value) =>
      ChangeVerificationMark.values.firstWhere(
        (item) => item.name == value,
        orElse: () => ChangeVerificationMark.unverified,
      );
}

class FileChangeSummary {
  const FileChangeSummary({
    required this.path,
    required this.operation,
    required this.linesAdded,
    required this.linesRemoved,
    this.diff = '',
    this.truncated = false,
    this.mark = ChangeVerificationMark.unverified,
  });

  final String path;
  final String operation;
  final int linesAdded;
  final int linesRemoved;
  final String diff;
  final bool truncated;
  final ChangeVerificationMark mark;

  Map<String, dynamic> toJson() => {
        'path': path,
        'operation': operation,
        'linesAdded': linesAdded,
        'linesRemoved': linesRemoved,
        if (diff.isNotEmpty) 'diff': diff,
        if (truncated) 'truncated': true,
        'mark': mark.id,
      };

  factory FileChangeSummary.fromJson(Map<String, dynamic> json) {
    return FileChangeSummary(
      path: json['path']?.toString() ?? '',
      operation: json['operation']?.toString() ?? 'edit',
      linesAdded: (json['linesAdded'] as num?)?.toInt() ?? 0,
      linesRemoved: (json['linesRemoved'] as num?)?.toInt() ?? 0,
      diff: json['diff']?.toString() ?? '',
      truncated: json['truncated'] as bool? ?? false,
      mark: ChangeVerificationMarkX.parse(json['mark']?.toString()),
    );
  }
}

class ChangeReview {
  const ChangeReview({
    required this.files,
    required this.mark,
    this.linesAdded = 0,
    this.linesRemoved = 0,
  });

  final List<FileChangeSummary> files;
  final ChangeVerificationMark mark;
  final int linesAdded;
  final int linesRemoved;

  Map<String, dynamic> toJson() => {
        'files': files.map((file) => file.toJson()).toList(),
        'mark': mark.id,
        'linesAdded': linesAdded,
        'linesRemoved': linesRemoved,
      };

  factory ChangeReview.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'] as List? ?? const [];
    return ChangeReview(
      files: rawFiles
          .whereType<Map>()
          .map((item) =>
              FileChangeSummary.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      mark: ChangeVerificationMarkX.parse(json['mark']?.toString()),
      linesAdded: (json['linesAdded'] as num?)?.toInt() ?? 0,
      linesRemoved: (json['linesRemoved'] as num?)?.toInt() ?? 0,
    );
  }
}

class ChangeReviewService {
  const ChangeReviewService();

  ChangeReview fromMetadata(
    Iterable<Map<String, dynamic>> metadataList, {
    ChangeVerificationMark mark = ChangeVerificationMark.unverified,
  }) {
    final files = <FileChangeSummary>[];
    for (final metadata in metadataList) {
      final path = metadata['path']?.toString();
      if (path == null || path.isEmpty) continue;
      final operation = metadata['operation']?.toString() ?? 'edit';
      if (operation == 'read' || operation == 'list' || operation == 'search') {
        continue;
      }
      files.add(FileChangeSummary(
        path: path,
        operation: operation,
        linesAdded: (metadata['linesAdded'] as num?)?.toInt() ?? 0,
        linesRemoved: (metadata['linesRemoved'] as num?)?.toInt() ?? 0,
        diff: metadata['diff']?.toString() ?? '',
        truncated: metadata['diffTruncated'] == true,
        mark: mark,
      ));
    }
    return ChangeReview(
      files: files,
      mark: mark,
      linesAdded: files.fold(0, (sum, file) => sum + file.linesAdded),
      linesRemoved: files.fold(0, (sum, file) => sum + file.linesRemoved),
    );
  }

  FileChangeSummary summarizeEdit({
    required String path,
    required String before,
    required String after,
    String operation = 'edit',
    ChangeVerificationMark mark = ChangeVerificationMark.unverified,
  }) {
    final diff = buildUnifiedDiff(
      before,
      after,
      oldPath: 'a/$path',
      newPath: 'b/$path',
    );
    return FileChangeSummary(
      path: path,
      operation: operation,
      linesAdded: diff.linesAdded,
      linesRemoved: diff.linesRemoved,
      diff: diff.diff,
      truncated: diff.truncated,
      mark: mark,
    );
  }

  ChangeReview withVerification(
    ChangeReview review,
    DevelopmentVerificationResult result,
  ) {
    final mark = result.success
        ? ChangeVerificationMark.passed
        : result.plan.steps.any(
                (step) => step.status == VerificationStepStatus.failed)
            ? ChangeVerificationMark.failed
            : ChangeVerificationMark.unverified;
    return ChangeReview(
      files: [
        for (final file in review.files)
          FileChangeSummary(
            path: file.path,
            operation: file.operation,
            linesAdded: file.linesAdded,
            linesRemoved: file.linesRemoved,
            diff: file.diff,
            truncated: file.truncated,
            mark: mark,
          ),
      ],
      mark: mark,
      linesAdded: review.linesAdded,
      linesRemoved: review.linesRemoved,
    );
  }
}
