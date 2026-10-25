enum EvidenceSupportLevel {
  // Wire value retained for existing vaults; this is source freshness, not
  // semantic proof of the claim.
  supported('supported', '来源近期核对，结论待复核'),
  partial('partial', '待补充证据'),
  conflicting('conflicting', '存在证据冲突'),
  stale('stale', '证据待刷新');

  const EvidenceSupportLevel(this.wireName, this.label);
  final String wireName;
  final String label;
}

class EvidenceCitation {
  const EvidenceCitation({
    required this.id,
    required this.sourceTitle,
    required this.sourceUri,
    required this.excerpt,
    required this.capturedAt,
    required this.verifiedAt,
    this.contradictsClaim = false,
  });

  final String id;
  final String sourceTitle;
  final String sourceUri;
  final String excerpt;
  final DateTime capturedAt;
  final DateTime verifiedAt;
  final bool contradictsClaim;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'sourceTitle': sourceTitle,
        'sourceUri': sourceUri,
        'excerpt': excerpt,
        'capturedAt': capturedAt.toUtc().toIso8601String(),
        'verifiedAt': verifiedAt.toUtc().toIso8601String(),
        'contradictsClaim': contradictsClaim,
      };

  factory EvidenceCitation.fromJson(Map<String, dynamic> json) =>
      EvidenceCitation(
        id: json['id']?.toString() ?? 'cit',
        sourceTitle: json['sourceTitle']?.toString() ?? '',
        sourceUri: json['sourceUri']?.toString() ?? '',
        excerpt: json['excerpt']?.toString() ?? '',
        capturedAt:
            DateTime.tryParse(json['capturedAt']?.toString() ?? '')?.toUtc() ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        verifiedAt:
            DateTime.tryParse(json['verifiedAt']?.toString() ?? '')?.toUtc() ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        contradictsClaim: json['contradictsClaim'] == true,
      );
}

class ResearchClaim {
  const ResearchClaim({
    required this.id,
    required this.statement,
    required this.citations,
  });

  final String id;
  final String statement;
  final List<EvidenceCitation> citations;

  EvidenceSupportLevel evaluateSupport({
    DateTime? now,
    Duration freshnessWindow = const Duration(days: 14),
  }) {
    if (citations.isEmpty) return EvidenceSupportLevel.partial;
    if (citations.any((c) => c.contradictsClaim)) {
      return EvidenceSupportLevel.conflicting;
    }
    if (statement.trim().isEmpty ||
        citations.any((c) =>
            c.excerpt.trim().isEmpty ||
            Uri.tryParse(c.sourceUri)?.scheme != 'https' ||
            (Uri.tryParse(c.sourceUri)?.host.isEmpty ?? true))) {
      return EvidenceSupportLevel.partial;
    }
    final clock = (now ?? DateTime.now()).toUtc();
    if (citations.any((c) =>
        c.verifiedAt.isAfter(clock) ||
        clock.difference(c.verifiedAt) > freshnessWindow)) {
      return EvidenceSupportLevel.stale;
    }
    return EvidenceSupportLevel.supported;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'statement': statement,
        'citations': citations.map((c) => c.toJson()).toList(),
      };

  factory ResearchClaim.fromJson(Map<String, dynamic> json) => ResearchClaim(
        id: json['id']?.toString() ?? 'claim',
        statement: json['statement']?.toString() ?? '',
        citations: (json['citations'] as List? ?? const <dynamic>[])
            .whereType<Map>()
            .map((m) => EvidenceCitation.fromJson(Map<String, dynamic>.from(m)))
            .toList(growable: false),
      );
}

class ResearchArtifact {
  const ResearchArtifact({
    required this.id,
    required this.topic,
    required this.summary,
    required this.claims,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String topic;
  final String summary;
  final List<ResearchClaim> claims;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasConflicts => claims.any(
        (c) => c.evaluateSupport() == EvidenceSupportLevel.conflicting,
      );

  EvidenceSupportLevel get supportLevel {
    if (claims.isEmpty) return EvidenceSupportLevel.partial;
    final levels = claims.map((c) => c.evaluateSupport()).toSet();
    for (final level in [
      EvidenceSupportLevel.conflicting,
      EvidenceSupportLevel.stale,
      EvidenceSupportLevel.partial
    ]) {
      if (levels.contains(level)) return level;
    }
    return EvidenceSupportLevel.supported;
  }

  int get totalCitations =>
      claims.fold<int>(0, (acc, item) => acc + item.citations.length);
}
