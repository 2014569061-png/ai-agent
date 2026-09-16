import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../infrastructure/database/app_database.dart';

class DraftAttachment {
  const DraftAttachment({
    required this.id,
    required this.name,
    required this.mime,
    required this.path,
    this.status = 'ready',
  });

  final String id;
  final String name;
  final String mime;
  final String path;
  final String status;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mime': mime,
        'path': path,
        'status': status,
      };

  factory DraftAttachment.fromJson(Map<String, dynamic> json) =>
      DraftAttachment(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        mime: json['mime']?.toString() ?? 'application/octet-stream',
        path: json['path']?.toString() ?? '',
        status: json['status']?.toString() ?? 'ready',
      );
}

class ConversationDraft {
  const ConversationDraft({
    required this.draftKey,
    this.conversationId,
    this.projectId,
    this.text = '',
    this.attachments = const [],
    this.references = const [],
    required this.updatedAt,
  });

  final String draftKey;
  final String? conversationId;
  final String? projectId;
  final String text;
  final List<DraftAttachment> attachments;
  final List<Map<String, dynamic>> references;
  final DateTime updatedAt;

  bool get isEmpty =>
      text.trim().isEmpty && attachments.isEmpty && references.isEmpty;
}

class DraftService {
  const DraftService();

  static String keyFor({String? conversationId, String? projectId}) {
    if (conversationId != null && conversationId.isNotEmpty) {
      return 'conversation:$conversationId';
    }
    if (projectId != null && projectId.isNotEmpty) {
      return 'project:$projectId';
    }
    return 'global';
  }

  Future<ConversationDraft?> load(AppDatabase db, String draftKey) async {
    final row = await db.findDraft(draftKey);
    if (row == null) return null;
    final attachments = await refreshAttachments(
      _decodeAttachments(row.attachmentsJson),
    );
    return ConversationDraft(
      draftKey: row.draftKey,
      conversationId: row.conversationId,
      projectId: row.projectId,
      text: row.body,
      attachments: attachments,
      references: _decodeMaps(row.referencesJson),
      updatedAt: row.updatedAt,
    );
  }

  Future<List<DraftAttachment>> refreshAttachments(
      List<DraftAttachment> attachments) async {
    if (kIsWeb) return attachments;
    return [
      for (final item in attachments)
        item.path.isEmpty || !File(item.path).existsSync()
            ? DraftAttachment(
                id: item.id,
                name: item.name,
                mime: item.mime,
                path: item.path,
                status: 'missing',
              )
            : item,
    ];
  }

  Future<void> save(
    AppDatabase db, {
    required String draftKey,
    String? conversationId,
    String? projectId,
    required String text,
    List<DraftAttachment> attachments = const [],
    List<Map<String, dynamic>> references = const [],
  }) async {
    await db.saveDraft(Draft(
      draftKey: draftKey,
      conversationId: conversationId,
      projectId: projectId,
      body: text,
      attachmentsJson: jsonEncode(
          attachments.map((item) => item.toJson()).toList(growable: false)),
      referencesJson: jsonEncode(references),
      updatedAt: DateTime.now(),
    ));
  }

  Future<void> clear(AppDatabase db, String draftKey) =>
      db.deleteDraft(draftKey);

  Future<DraftAttachment> stageFile({
    required String id,
    required String name,
    required String mime,
    required List<int> bytes,
  }) async {
    if (kIsWeb) {
      return DraftAttachment(
        id: id,
        name: name,
        mime: mime,
        path: '',
        status: 'unavailable',
      );
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'drafts', id));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return DraftAttachment(
      id: id,
      name: name,
      mime: mime,
      path: file.path,
    );
  }

  List<DraftAttachment> _decodeAttachments(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) =>
              DraftAttachment.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  List<Map<String, dynamic>> _decodeMaps(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
