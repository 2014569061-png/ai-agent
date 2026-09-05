import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final chunks = _chunk(content.trim());
    final now = DateTime.now();
    final doc = KnowledgeDoc(
      id: 'kd-${now.microsecondsSinceEpoch}',
      name: name,
      sourceType: sourceType,
      chunkCount: chunks.length,
      createdAt: now,
      updatedAt: now,
    );
    await db.saveKnowledgeDoc(doc);
    for (var i = 0; i < chunks.length; i++) {
      await db.saveKnowledgeChunk(KnowledgeChunk(
        id: 'kc-${now.microsecondsSinceEpoch}-$i',
        docId: doc.id,
        content: chunks[i],
        embeddingJson: null,
        index: i,
      ));
    }
    return doc;
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
    final chunks = await db.allKnowledgeChunks();
    if (chunks.isEmpty) return '';
    final top = _bm25(chunks, query, topK: topK);
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

  List<KnowledgeChunk> _bm25(List<KnowledgeChunk> chunks, String query,
      {int topK = 5}) {
    const k1 = 1.5;
    const b = 0.75;
    final docTokens = chunks.map((c) => _tokenize(c.content)).toList();
    final docLen = docTokens.map((t) => t.length).toList();
    final avgLen =
        docLen.isEmpty ? 1 : docLen.reduce((a, x) => a + x) / docLen.length;
    final n = chunks.length;
    final df = <String, int>{};
    for (final tokens in docTokens) {
      for (final t in tokens.toSet()) {
        df[t] = (df[t] ?? 0) + 1;
      }
    }
    final queryTokens = _tokenize(query).toSet().toList();
    final scores = <double>[];
    for (var i = 0; i < chunks.length; i++) {
      var score = 0.0;
      final tokens = docTokens[i];
      final tf = <String, int>{};
      for (final t in tokens) {
        tf[t] = (tf[t] ?? 0) + 1;
      }
      for (final qt in queryTokens) {
        final f = tf[qt] ?? 0;
        if (f == 0) continue;
        final d = df[qt] ?? 0;
        final idf = math.log((n - d + 0.5) / (d + 0.5) + 1);
        final denom = f + k1 * (1 - b + b * (tokens.length / avgLen));
        score += idf * (f * (k1 + 1)) / denom;
      }
      scores.add(score);
    }
    final indexed = List<int>.generate(chunks.length, (i) => i);
    indexed.sort((a, x) => scores[x].compareTo(scores[a]));
    return [
      for (final i in indexed.take(topK))
        if (scores[i] > 0) chunks[i]
    ];
  }

  /// 分词：英文/数字按词，中文按单字，其余为分隔符。
  List<String> _tokenize(String text) {
    final lower = text.toLowerCase();
    final tokens = <String>[];
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      if (RegExp(r'[a-z0-9]').hasMatch(ch)) {
        buffer.write(ch);
      } else if (RegExp(r'[\u4e00-\u9fff]').hasMatch(ch)) {
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
