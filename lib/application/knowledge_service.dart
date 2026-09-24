import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/unique_id.dart';
import '../infrastructure/database/app_database.dart';

/// 知识库 / RAG 服务（C4）。
///
/// - 入库：文本分块（~800 字符 + 100 重叠）后写入 KnowledgeChunks。
/// - 检索：默认 BM25 关键词（本地、零网络），保证无 embedding 端点时也可用；
///   分块时的 embeddingJson 预留，未来接入 provider `/embeddings` 后切余弦 topK。
/// - 注入：与记忆同处，在系统提示词前拼接相关片段（限制 1.5KB，仅首轮）。
class KnowledgeService {
  static const _chunkSize = 800;
  static const _overlap = 100;
  static const _prefsKeyEnabled = 'knowledge_enabled';
  static const _injectionBudget = 1500;
  static final Map<AppDatabase, Future<_KnowledgeSearchIndex>> _indexCache =
      <AppDatabase, Future<_KnowledgeSearchIndex>>{};

  /// Invalidates the in-memory BM25 index after an external database import
  /// or deletion.
  static void invalidate(AppDatabase db) {
    unawaited(_indexCache.remove(db));
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyEnabled) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyEnabled, enabled);
  }

  Future<KnowledgeDoc> ingest({
    required AppDatabase db,
    required String name,
    required String sourceType,
    required String content,
  }) async {
    final normalizedContent = content.trim();
    if (normalizedContent.isEmpty) {
      throw ArgumentError.value(content, 'content', 'must not be empty');
    }
    final chunks = _chunk(normalizedContent);
    final now = DateTime.now();
    final doc = KnowledgeDoc(
      id: UniqueId.generate('kd', now: now),
      name: name,
      sourceType: sourceType,
      chunkCount: chunks.length,
      createdAt: now,
      updatedAt: now,
    );
    await db.saveKnowledgeDocWithChunks(
      doc,
      [
        for (var i = 0; i < chunks.length; i++)
          KnowledgeChunk(
            id: '${doc.id}:chunk:$i',
            docId: doc.id,
            content: chunks[i],
            embeddingJson: null,
            index: i,
          ),
      ],
    );
    invalidate(db);
    return doc;
  }

  Future<void> delete(
      {required AppDatabase db, required String documentId}) async {
    await db.deleteKnowledgeDoc(documentId);
    invalidate(db);
  }

  List<String> _chunk(String text) {
    if (text.length <= _chunkSize) return [text];
    final result = <String>[];
    var start = 0;
    while (start < text.length) {
      final end = math.min(start + _chunkSize, text.length);
      result.add(text.substring(start, end));
      if (end >= text.length) break;
      start = end - _overlap;
    }
    return result;
  }

  /// 构建注入块：对 query 做 BM25 检索 topK 片段并格式化。
  Future<String> buildInjectionBlock(AppDatabase db, String query,
      {int topK = 5}) async {
    if (!await isEnabled()) return '';
    if (query.trim().isEmpty) return '';
    final index = await _indexFor(db);
    if (index.chunks.isEmpty) return '';
    final top = _bm25(index, query, topK: topK);
    if (top.isEmpty) return '';
    final buffer = StringBuffer('## 知识库相关片段\n');
    var used = 0;
    for (final chunk in top) {
      final snippet = chunk.content.length > 400
          ? '${chunk.content.substring(0, 400)}…'
          : chunk.content;
      final line = '- $snippet\n';
      if (used + line.length > _injectionBudget) break;
      buffer.write(line);
      used += line.length;
    }
    return buffer.toString();
  }

  Future<_KnowledgeSearchIndex> _indexFor(AppDatabase db) async {
    while (true) {
      final cached = _indexCache[db];
      if (cached != null) {
        try {
          final index = await cached;
          if (index.generation == db.knowledgeGeneration) return index;
          if (identical(_indexCache[db], cached)) {
            unawaited(_indexCache.remove(db));
          }
        } catch (_) {
          if (identical(_indexCache[db], cached)) {
            unawaited(_indexCache.remove(db));
          }
          rethrow;
        }
      }

      final generation = db.knowledgeGeneration;
      final future = _buildIndex(db, generation);
      _indexCache[db] = future;
      try {
        final index = await future;
        if (index.generation == db.knowledgeGeneration) return index;
        if (identical(_indexCache[db], future)) {
          unawaited(_indexCache.remove(db));
        }
      } catch (_) {
        if (identical(_indexCache[db], future)) {
          unawaited(_indexCache.remove(db));
        }
        rethrow;
      }
    }
  }

  Future<_KnowledgeSearchIndex> _buildIndex(
      AppDatabase db, int generation) async {
    final chunks = await db.allKnowledgeChunks();
    final lengths = <int>[];
    final termFrequencies = <Map<String, int>>[];
    final documentFrequency = <String, int>{};
    for (final chunk in chunks) {
      final frequencies = <String, int>{};
      var tokenCount = 0;
      for (final token in _tokenize(chunk.content)) {
        tokenCount++;
        frequencies[token] = (frequencies[token] ?? 0) + 1;
      }
      lengths.add(tokenCount);
      termFrequencies.add(frequencies);
      for (final token in frequencies.keys) {
        documentFrequency[token] = (documentFrequency[token] ?? 0) + 1;
      }
    }
    return _KnowledgeSearchIndex(
      generation: generation,
      chunks: chunks,
      termFrequencies: termFrequencies,
      lengths: lengths,
      averageLength: lengths.isEmpty
          ? 1
          : lengths.reduce((sum, length) => sum + length) / lengths.length,
      documentFrequency: documentFrequency,
    );
  }

  List<KnowledgeChunk> _bm25(_KnowledgeSearchIndex index, String query,
      {int topK = 5}) {
    if (topK <= 0 || index.chunks.isEmpty) return const [];
    const k1 = 1.5;
    const b = 0.75;
    final chunks = index.chunks;
    final termFrequencies = index.termFrequencies;
    final docLen = index.lengths;
    final queryTokens = _tokenize(query).toSet().toList();
    if (queryTokens.isEmpty) return const [];
    final best = <(int, double)>[];
    for (var i = 0; i < chunks.length; i++) {
      var score = 0.0;
      final tf = termFrequencies[i];
      for (final qt in queryTokens) {
        final f = tf[qt] ?? 0;
        if (f == 0) continue;
        final d = index.documentFrequency[qt] ?? 0;
        final idf = math.log((chunks.length - d + 0.5) / (d + 0.5) + 1);
        final denom = f + k1 * (1 - b + b * (docLen[i] / index.averageLength));
        score += idf * (f * (k1 + 1)) / denom;
      }
      if (score <= 0) continue;

      // 只维护得分最高的 K 项，避免对全部 N 个片段排序。
      var insertionIndex = best.length;
      while (insertionIndex > 0 && best[insertionIndex - 1].$2 < score) {
        insertionIndex--;
      }
      if (insertionIndex >= topK) continue;
      best.insert(insertionIndex, (i, score));
      if (best.length > topK) best.removeLast();
    }
    return [for (final result in best) chunks[result.$1]];
  }

  /// 分词：英文/数字按词，中文按单字，其余为分隔符。
  List<String> _tokenize(String text) {
    final lower = text.toLowerCase();
    final tokens = <String>[];
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      if ((rune >= 0x61 && rune <= 0x7a) || (rune >= 0x30 && rune <= 0x39)) {
        buffer.write(ch);
      } else if (rune >= 0x4e00 && rune <= 0x9fff) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        tokens.add(ch);
      } else {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
      }
    }
    if (buffer.isNotEmpty) tokens.add(buffer.toString());
    return tokens;
  }
}

final knowledgeServiceProvider =
    Provider<KnowledgeService>((ref) => KnowledgeService());

class _KnowledgeSearchIndex {
  const _KnowledgeSearchIndex({
    required this.generation,
    required this.chunks,
    required this.termFrequencies,
    required this.lengths,
    required this.averageLength,
    required this.documentFrequency,
  });

  final int generation;
  final List<KnowledgeChunk> chunks;
  final List<Map<String, int>> termFrequencies;
  final List<int> lengths;
  final double averageLength;
  final Map<String, int> documentFrequency;
}
