import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../domain/network_access_policy.dart';
import '../infrastructure/tools/pinned_host_connector.dart';

import '../domain/research_artifact.dart';
import '../domain/unique_id.dart';
import '../infrastructure/database/app_database.dart';

class ResearchArtifactService {
  ResearchArtifactService(this._db);

  final AppDatabase _db;
  bool _ready = false;

  Future<void> ensureReady() async {
    if (_ready) return;
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS nexus_research_artifacts (
        id TEXT PRIMARY KEY NOT NULL,
        topic TEXT NOT NULL,
        summary TEXT NOT NULL,
        claims_json TEXT NOT NULL DEFAULT '[]',
        version INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    _ready = true;
  }

  Future<ResearchArtifact> create({
    String? id,
    required String topic,
    required String summary,
    List<ResearchClaim> claims = const <ResearchClaim>[],
    DateTime? now,
  }) async {
    final trimmedTopic = topic.trim();
    if (trimmedTopic.isEmpty) {
      throw const FormatException('研究主题不能为空');
    }
    await ensureReady();
    final clock = (now ?? DateTime.now()).toUtc();
    final artifact = ResearchArtifact(
      id: id ?? UniqueId.generate('rsa', now: clock),
      topic: trimmedTopic,
      summary: summary.trim(),
      claims: claims,
      version: 1,
      createdAt: clock,
      updatedAt: clock,
    );
    await _save(artifact);
    return artifact;
  }

  Future<ResearchArtifact> addCitation({
    required String artifactId,
    required String claimId,
    required EvidenceCitation citation,
    DateTime? now,
  }) async {
    final existing = await findById(artifactId);
    if (existing == null) {
      throw StateError('研究成果不存在：$artifactId');
    }
    if (citation.sourceUri.trim().isEmpty || citation.excerpt.trim().isEmpty) {
      throw const FormatException('引用来源地址与摘录不能为空');
    }
    final clock = (now ?? DateTime.now()).toUtc();
    var foundClaim = false;
    final updatedClaims = existing.claims.map((claim) {
      if (claim.id != claimId) return claim;
      foundClaim = true;
      return ResearchClaim(
        id: claim.id,
        statement: claim.statement,
        citations: <EvidenceCitation>[...claim.citations, citation],
      );
    }).toList(growable: false);
    if (!foundClaim) {
      throw StateError('研究结论不存在：$claimId');
    }
    final updated = ResearchArtifact(
      id: existing.id,
      topic: existing.topic,
      summary: existing.summary,
      claims: updatedClaims,
      version: existing.version + 1,
      createdAt: existing.createdAt,
      updatedAt: clock,
    );
    await _save(updated);
    return updated;
  }

  Future<ResearchArtifact> refreshVerification({
    required String artifactId,
    Future<bool> Function(EvidenceCitation)? verifyCitation,
    DateTime? now,
  }) async {
    final existing = await findById(artifactId);
    if (existing == null) {
      throw StateError('研究成果不存在：$artifactId');
    }
    final clock = (now ?? DateTime.now()).toUtc();
    final verifiedCitations = <EvidenceCitation>{};
    for (final claim in existing.claims) {
      for (final citation in claim.citations) {
        // A refresh timestamp is evidence of a successful source check, never
        // a substitute for one. Failed/changed sources retain their old age.
        try {
          final verified =
              await (verifyCitation ?? verifyHttpCitation)(citation);
          if (verified) verifiedCitations.add(citation);
        } catch (_) {
          // A failed source cannot refresh the evidence's age.
        }
      }
    }
    if (verifiedCitations.isEmpty) return existing;
    final updatedClaims = existing.claims
        .map(
          (claim) => ResearchClaim(
            id: claim.id,
            statement: claim.statement,
            citations: claim.citations
                .map(
                  (c) => EvidenceCitation(
                    id: c.id,
                    sourceTitle: c.sourceTitle,
                    sourceUri: c.sourceUri,
                    excerpt: c.excerpt,
                    capturedAt: c.capturedAt,
                    verifiedAt:
                        verifiedCitations.contains(c) ? clock : c.verifiedAt,
                    contradictsClaim: c.contradictsClaim,
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
    final updated = ResearchArtifact(
      id: existing.id,
      topic: existing.topic,
      summary: existing.summary,
      claims: updatedClaims,
      version: existing.version + 1,
      createdAt: existing.createdAt,
      updatedAt: clock,
    );
    await _save(updated);
    return updated;
  }

  static Future<bool> verifyHttpCitation(EvidenceCitation citation) async {
    final uri = Uri.tryParse(citation.sourceUri);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        citation.excerpt.trim().isEmpty) {
      return false;
    }
    final connector = PinnedHostConnector(requirePin: true);
    final client = IOClient(connector.createClient());
    try {
      // User-supplied citation URLs are untrusted: block LAN/metadata and pin
      // the checked DNS result so a second lookup cannot rebind internally.
      final endpoint = await const NetworkAccessPolicy()
          .resolveForConnect(uri.toString())
          .timeout(const Duration(seconds: 5));
      if (!endpoint.decision.allowed || endpoint.address == null) return false;
      connector.pin(uri.host, endpoint.address!);
      final request = http.Request('GET', uri)..followRedirects = false;
      final response =
          await client.send(request).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200 ||
          (response.contentLength ?? 0) > 2 * 1024 * 1024) {
        return false;
      }
      Future<List<int>> readBounded() async {
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          bytes.addAll(chunk);
          if (bytes.length > 2 * 1024 * 1024) {
            throw const FormatException('来源超过核验大小上限');
          }
        }
        return bytes;
      }

      final bytes = await readBounded().timeout(const Duration(seconds: 12));
      String normalize(String text) => text
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return normalize(utf8.decode(bytes, allowMalformed: true))
          .contains(normalize(citation.excerpt));
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  Future<List<ResearchArtifact>> list() async {
    await ensureReady();
    final rows = await _db
        .customSelect(
            'SELECT * FROM nexus_research_artifacts ORDER BY updated_at DESC')
        .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<ResearchArtifact?> findById(String id) async {
    await ensureReady();
    final rows = await _db.customSelect(
      'SELECT * FROM nexus_research_artifacts WHERE id = ? LIMIT 1',
      variables: <Variable<Object>>[Variable<String>(id)],
    ).get();
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<void> _save(ResearchArtifact artifact) async {
    await _db.customStatement(
      '''
      INSERT OR REPLACE INTO nexus_research_artifacts (
        id, topic, summary, claims_json, version, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        artifact.id,
        artifact.topic,
        artifact.summary,
        jsonEncode(artifact.claims.map((c) => c.toJson()).toList()),
        artifact.version,
        artifact.createdAt.millisecondsSinceEpoch,
        artifact.updatedAt.millisecondsSinceEpoch,
      ],
    );
  }

  ResearchArtifact _fromRow(QueryRow row) {
    final rawClaims = jsonDecode(row.read<String>('claims_json'));
    return ResearchArtifact(
      id: row.read<String>('id'),
      topic: row.read<String>('topic'),
      summary: row.read<String>('summary'),
      claims: rawClaims is List
          ? rawClaims
              .whereType<Map>()
              .map((m) => ResearchClaim.fromJson(Map<String, dynamic>.from(m)))
              .toList(growable: false)
          : const <ResearchClaim>[],
      version: row.read<int>('version'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('created_at'),
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('updated_at'),
        isUtc: true,
      ),
    );
  }
}
