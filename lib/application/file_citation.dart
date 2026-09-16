import 'dart:convert';

import 'package:crypto/crypto.dart';

class FileCitation {
  const FileCitation({
    required this.projectId,
    required this.relativePath,
    required this.contentHash,
    this.startLine,
    this.endLine,
    this.excerpt = '',
    this.stale = false,
  });

  final String projectId;
  final String relativePath;
  final String contentHash;
  final int? startLine;
  final int? endLine;
  final String excerpt;
  final bool stale;

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'relativePath': relativePath,
        'contentHash': contentHash,
        if (startLine != null) 'startLine': startLine,
        if (endLine != null) 'endLine': endLine,
        if (excerpt.isNotEmpty) 'excerpt': excerpt,
        'stale': stale,
      };

  factory FileCitation.fromJson(Map<String, dynamic> json) => FileCitation(
        projectId: json['projectId']?.toString() ?? '',
        relativePath: json['relativePath']?.toString() ?? '',
        contentHash: json['contentHash']?.toString() ?? '',
        startLine: (json['startLine'] as num?)?.toInt(),
        endLine: (json['endLine'] as num?)?.toInt(),
        excerpt: json['excerpt']?.toString() ?? '',
        stale: json['stale'] == true,
      );

  FileCitation copyWith({bool? stale, String? excerpt}) => FileCitation(
        projectId: projectId,
        relativePath: relativePath,
        contentHash: contentHash,
        startLine: startLine,
        endLine: endLine,
        excerpt: excerpt ?? this.excerpt,
        stale: stale ?? this.stale,
      );

  String get displayLabel {
    final range = startLine == null
        ? ''
        : endLine == null || endLine == startLine
            ? ':$startLine'
            : ':$startLine-$endLine';
    return '$relativePath$range';
  }

  static String hashOf(String content) =>
      sha256.convert(utf8.encode(content)).toString();
}
