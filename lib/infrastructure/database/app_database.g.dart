// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ConversationsTable extends Conversations
    with TableInfo<$ConversationsTable, Conversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('新会话'));
  static const VerificationMeta _agentIdMeta =
      const VerificationMeta('agentId');
  @override
  late final GeneratedColumn<String> agentId = GeneratedColumn<String>(
      'agent_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isPinnedMeta =
      const VerificationMeta('isPinned');
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
      'is_pinned', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_pinned" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isFavoriteMeta =
      const VerificationMeta('isFavorite');
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
      'is_favorite', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_favorite" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _tagsJsonMeta =
      const VerificationMeta('tagsJson');
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
      'tags_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        title,
        agentId,
        isPinned,
        isFavorite,
        tagsJson,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(Insertable<Conversation> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    }
    if (data.containsKey('agent_id')) {
      context.handle(_agentIdMeta,
          agentId.isAcceptableOrUnknown(data['agent_id']!, _agentIdMeta));
    }
    if (data.containsKey('is_pinned')) {
      context.handle(_isPinnedMeta,
          isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta));
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
          _isFavoriteMeta,
          isFavorite.isAcceptableOrUnknown(
              data['is_favorite']!, _isFavoriteMeta));
    }
    if (data.containsKey('tags_json')) {
      context.handle(_tagsJsonMeta,
          tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Conversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Conversation(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      agentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}agent_id']),
      isPinned: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_pinned'])!,
      isFavorite: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_favorite'])!,
      tagsJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tags_json'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ConversationsTable createAlias(String alias) {
    return $ConversationsTable(attachedDatabase, alias);
  }
}

class Conversation extends DataClass implements Insertable<Conversation> {
  final String id;
  final String title;
  final String? agentId;
  final bool isPinned;
  final bool isFavorite;
  final String tagsJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Conversation(
      {required this.id,
      required this.title,
      this.agentId,
      required this.isPinned,
      required this.isFavorite,
      required this.tagsJson,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || agentId != null) {
      map['agent_id'] = Variable<String>(agentId);
    }
    map['is_pinned'] = Variable<bool>(isPinned);
    map['is_favorite'] = Variable<bool>(isFavorite);
    map['tags_json'] = Variable<String>(tagsJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ConversationsCompanion toCompanion(bool nullToAbsent) {
    return ConversationsCompanion(
      id: Value(id),
      title: Value(title),
      agentId: agentId == null && nullToAbsent
          ? const Value.absent()
          : Value(agentId),
      isPinned: Value(isPinned),
      isFavorite: Value(isFavorite),
      tagsJson: Value(tagsJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Conversation.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Conversation(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      agentId: serializer.fromJson<String?>(json['agentId']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      tagsJson: serializer.fromJson<String>(json['tagsJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'agentId': serializer.toJson<String?>(agentId),
      'isPinned': serializer.toJson<bool>(isPinned),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'tagsJson': serializer.toJson<String>(tagsJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Conversation copyWith(
          {String? id,
          String? title,
          Value<String?> agentId = const Value.absent(),
          bool? isPinned,
          bool? isFavorite,
          String? tagsJson,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Conversation(
        id: id ?? this.id,
        title: title ?? this.title,
        agentId: agentId.present ? agentId.value : this.agentId,
        isPinned: isPinned ?? this.isPinned,
        isFavorite: isFavorite ?? this.isFavorite,
        tagsJson: tagsJson ?? this.tagsJson,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Conversation copyWithCompanion(ConversationsCompanion data) {
    return Conversation(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      agentId: data.agentId.present ? data.agentId.value : this.agentId,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      isFavorite:
          data.isFavorite.present ? data.isFavorite.value : this.isFavorite,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Conversation(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('agentId: $agentId, ')
          ..write('isPinned: $isPinned, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, title, agentId, isPinned, isFavorite, tagsJson, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Conversation &&
          other.id == this.id &&
          other.title == this.title &&
          other.agentId == this.agentId &&
          other.isPinned == this.isPinned &&
          other.isFavorite == this.isFavorite &&
          other.tagsJson == this.tagsJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ConversationsCompanion extends UpdateCompanion<Conversation> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> agentId;
  final Value<bool> isPinned;
  final Value<bool> isFavorite;
  final Value<String> tagsJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ConversationsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.agentId = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationsCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    this.agentId = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.tagsJson = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<Conversation> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? agentId,
    Expression<bool>? isPinned,
    Expression<bool>? isFavorite,
    Expression<String>? tagsJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (agentId != null) 'agent_id': agentId,
      if (isPinned != null) 'is_pinned': isPinned,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationsCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<String?>? agentId,
      Value<bool>? isPinned,
      Value<bool>? isFavorite,
      Value<String>? tagsJson,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return ConversationsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      agentId: agentId ?? this.agentId,
      isPinned: isPinned ?? this.isPinned,
      isFavorite: isFavorite ?? this.isFavorite,
      tagsJson: tagsJson ?? this.tagsJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (agentId.present) {
      map['agent_id'] = Variable<String>(agentId.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('agentId: $agentId, ')
          ..write('isPinned: $isPinned, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _conversationIdMeta =
      const VerificationMeta('conversationId');
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
      'conversation_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
      'role', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _toolCallIdMeta =
      const VerificationMeta('toolCallId');
  @override
  late final GeneratedColumn<String> toolCallId = GeneratedColumn<String>(
      'tool_call_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _toolCallsJsonMeta =
      const VerificationMeta('toolCallsJson');
  @override
  late final GeneratedColumn<String> toolCallsJson = GeneratedColumn<String>(
      'tool_calls_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _reasoningContentMeta =
      const VerificationMeta('reasoningContent');
  @override
  late final GeneratedColumn<String> reasoningContent = GeneratedColumn<String>(
      'reasoning_content', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        conversationId,
        role,
        content,
        toolCallId,
        toolCallsJson,
        reasoningContent,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(Insertable<Message> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
          _conversationIdMeta,
          conversationId.isAcceptableOrUnknown(
              data['conversation_id']!, _conversationIdMeta));
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
          _roleMeta, role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('tool_call_id')) {
      context.handle(
          _toolCallIdMeta,
          toolCallId.isAcceptableOrUnknown(
              data['tool_call_id']!, _toolCallIdMeta));
    }
    if (data.containsKey('tool_calls_json')) {
      context.handle(
          _toolCallsJsonMeta,
          toolCallsJson.isAcceptableOrUnknown(
              data['tool_calls_json']!, _toolCallsJsonMeta));
    }
    if (data.containsKey('reasoning_content')) {
      context.handle(
          _reasoningContentMeta,
          reasoningContent.isAcceptableOrUnknown(
              data['reasoning_content']!, _reasoningContentMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      conversationId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}conversation_id'])!,
      role: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}role'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      toolCallId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tool_call_id']),
      toolCallsJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tool_calls_json']),
      reasoningContent: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}reasoning_content']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  final String id;
  final String conversationId;
  final String role;
  final String content;
  final String? toolCallId;
  final String? toolCallsJson;
  final String? reasoningContent;
  final DateTime createdAt;
  const Message(
      {required this.id,
      required this.conversationId,
      required this.role,
      required this.content,
      this.toolCallId,
      this.toolCallsJson,
      this.reasoningContent,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    map['role'] = Variable<String>(role);
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || toolCallId != null) {
      map['tool_call_id'] = Variable<String>(toolCallId);
    }
    if (!nullToAbsent || toolCallsJson != null) {
      map['tool_calls_json'] = Variable<String>(toolCallsJson);
    }
    if (!nullToAbsent || reasoningContent != null) {
      map['reasoning_content'] = Variable<String>(reasoningContent);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      role: Value(role),
      content: Value(content),
      toolCallId: toolCallId == null && nullToAbsent
          ? const Value.absent()
          : Value(toolCallId),
      toolCallsJson: toolCallsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(toolCallsJson),
      reasoningContent: reasoningContent == null && nullToAbsent
          ? const Value.absent()
          : Value(reasoningContent),
      createdAt: Value(createdAt),
    );
  }

  factory Message.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<String>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      role: serializer.fromJson<String>(json['role']),
      content: serializer.fromJson<String>(json['content']),
      toolCallId: serializer.fromJson<String?>(json['toolCallId']),
      toolCallsJson: serializer.fromJson<String?>(json['toolCallsJson']),
      reasoningContent: serializer.fromJson<String?>(json['reasoningContent']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'role': serializer.toJson<String>(role),
      'content': serializer.toJson<String>(content),
      'toolCallId': serializer.toJson<String?>(toolCallId),
      'toolCallsJson': serializer.toJson<String?>(toolCallsJson),
      'reasoningContent': serializer.toJson<String?>(reasoningContent),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Message copyWith(
          {String? id,
          String? conversationId,
          String? role,
          String? content,
          Value<String?> toolCallId = const Value.absent(),
          Value<String?> toolCallsJson = const Value.absent(),
          Value<String?> reasoningContent = const Value.absent(),
          DateTime? createdAt}) =>
      Message(
        id: id ?? this.id,
        conversationId: conversationId ?? this.conversationId,
        role: role ?? this.role,
        content: content ?? this.content,
        toolCallId: toolCallId.present ? toolCallId.value : this.toolCallId,
        toolCallsJson:
            toolCallsJson.present ? toolCallsJson.value : this.toolCallsJson,
        reasoningContent: reasoningContent.present
            ? reasoningContent.value
            : this.reasoningContent,
        createdAt: createdAt ?? this.createdAt,
      );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      toolCallId:
          data.toolCallId.present ? data.toolCallId.value : this.toolCallId,
      toolCallsJson: data.toolCallsJson.present
          ? data.toolCallsJson.value
          : this.toolCallsJson,
      reasoningContent: data.reasoningContent.present
          ? data.reasoningContent.value
          : this.reasoningContent,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('toolCallId: $toolCallId, ')
          ..write('toolCallsJson: $toolCallsJson, ')
          ..write('reasoningContent: $reasoningContent, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, conversationId, role, content, toolCallId,
      toolCallsJson, reasoningContent, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.role == this.role &&
          other.content == this.content &&
          other.toolCallId == this.toolCallId &&
          other.toolCallsJson == this.toolCallsJson &&
          other.reasoningContent == this.reasoningContent &&
          other.createdAt == this.createdAt);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<String> id;
  final Value<String> conversationId;
  final Value<String> role;
  final Value<String> content;
  final Value<String?> toolCallId;
  final Value<String?> toolCallsJson;
  final Value<String?> reasoningContent;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.toolCallId = const Value.absent(),
    this.toolCallsJson = const Value.absent(),
    this.reasoningContent = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String id,
    required String conversationId,
    required String role,
    required String content,
    this.toolCallId = const Value.absent(),
    this.toolCallsJson = const Value.absent(),
    this.reasoningContent = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        conversationId = Value(conversationId),
        role = Value(role),
        content = Value(content),
        createdAt = Value(createdAt);
  static Insertable<Message> custom({
    Expression<String>? id,
    Expression<String>? conversationId,
    Expression<String>? role,
    Expression<String>? content,
    Expression<String>? toolCallId,
    Expression<String>? toolCallsJson,
    Expression<String>? reasoningContent,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (toolCallId != null) 'tool_call_id': toolCallId,
      if (toolCallsJson != null) 'tool_calls_json': toolCallsJson,
      if (reasoningContent != null) 'reasoning_content': reasoningContent,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith(
      {Value<String>? id,
      Value<String>? conversationId,
      Value<String>? role,
      Value<String>? content,
      Value<String?>? toolCallId,
      Value<String?>? toolCallsJson,
      Value<String?>? reasoningContent,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return MessagesCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      content: content ?? this.content,
      toolCallId: toolCallId ?? this.toolCallId,
      toolCallsJson: toolCallsJson ?? this.toolCallsJson,
      reasoningContent: reasoningContent ?? this.reasoningContent,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (toolCallId.present) {
      map['tool_call_id'] = Variable<String>(toolCallId.value);
    }
    if (toolCallsJson.present) {
      map['tool_calls_json'] = Variable<String>(toolCallsJson.value);
    }
    if (reasoningContent.present) {
      map['reasoning_content'] = Variable<String>(reasoningContent.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('toolCallId: $toolCallId, ')
          ..write('toolCallsJson: $toolCallsJson, ')
          ..write('reasoningContent: $reasoningContent, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AgentsTable extends Agents with TableInfo<$AgentsTable, Agent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AgentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _systemPromptMeta =
      const VerificationMeta('systemPrompt');
  @override
  late final GeneratedColumn<String> systemPrompt = GeneratedColumn<String>(
      'system_prompt', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('你是一个有帮助的 AI Agent。'));
  static const VerificationMeta _modelProfileIdMeta =
      const VerificationMeta('modelProfileId');
  @override
  late final GeneratedColumn<String> modelProfileId = GeneratedColumn<String>(
      'model_profile_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _enabledToolsJsonMeta =
      const VerificationMeta('enabledToolsJson');
  @override
  late final GeneratedColumn<String> enabledToolsJson = GeneratedColumn<String>(
      'enabled_tools_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _temperatureMeta =
      const VerificationMeta('temperature');
  @override
  late final GeneratedColumn<double> temperature = GeneratedColumn<double>(
      'temperature', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.7));
  static const VerificationMeta _maxTokensMeta =
      const VerificationMeta('maxTokens');
  @override
  late final GeneratedColumn<int> maxTokens = GeneratedColumn<int>(
      'max_tokens', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(2048));
  static const VerificationMeta _maxStepsMeta =
      const VerificationMeta('maxSteps');
  @override
  late final GeneratedColumn<int> maxSteps = GeneratedColumn<int>(
      'max_steps', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(8));
  static const VerificationMeta _topPMeta = const VerificationMeta('topP');
  @override
  late final GeneratedColumn<double> topP = GeneratedColumn<double>(
      'top_p', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(1.0));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        systemPrompt,
        modelProfileId,
        enabledToolsJson,
        temperature,
        maxTokens,
        maxSteps,
        topP,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'agents';
  @override
  VerificationContext validateIntegrity(Insertable<Agent> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('system_prompt')) {
      context.handle(
          _systemPromptMeta,
          systemPrompt.isAcceptableOrUnknown(
              data['system_prompt']!, _systemPromptMeta));
    }
    if (data.containsKey('model_profile_id')) {
      context.handle(
          _modelProfileIdMeta,
          modelProfileId.isAcceptableOrUnknown(
              data['model_profile_id']!, _modelProfileIdMeta));
    } else if (isInserting) {
      context.missing(_modelProfileIdMeta);
    }
    if (data.containsKey('enabled_tools_json')) {
      context.handle(
          _enabledToolsJsonMeta,
          enabledToolsJson.isAcceptableOrUnknown(
              data['enabled_tools_json']!, _enabledToolsJsonMeta));
    }
    if (data.containsKey('temperature')) {
      context.handle(
          _temperatureMeta,
          temperature.isAcceptableOrUnknown(
              data['temperature']!, _temperatureMeta));
    }
    if (data.containsKey('max_tokens')) {
      context.handle(_maxTokensMeta,
          maxTokens.isAcceptableOrUnknown(data['max_tokens']!, _maxTokensMeta));
    }
    if (data.containsKey('max_steps')) {
      context.handle(_maxStepsMeta,
          maxSteps.isAcceptableOrUnknown(data['max_steps']!, _maxStepsMeta));
    }
    if (data.containsKey('top_p')) {
      context.handle(
          _topPMeta, topP.isAcceptableOrUnknown(data['top_p']!, _topPMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Agent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Agent(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      systemPrompt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}system_prompt'])!,
      modelProfileId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}model_profile_id'])!,
      enabledToolsJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}enabled_tools_json'])!,
      temperature: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}temperature'])!,
      maxTokens: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}max_tokens'])!,
      maxSteps: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}max_steps'])!,
      topP: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}top_p'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $AgentsTable createAlias(String alias) {
    return $AgentsTable(attachedDatabase, alias);
  }
}

class Agent extends DataClass implements Insertable<Agent> {
  final String id;
  final String name;
  final String systemPrompt;
  final String modelProfileId;
  final String enabledToolsJson;
  final double temperature;
  final int maxTokens;
  final int maxSteps;
  final double topP;
  final DateTime updatedAt;
  const Agent(
      {required this.id,
      required this.name,
      required this.systemPrompt,
      required this.modelProfileId,
      required this.enabledToolsJson,
      required this.temperature,
      required this.maxTokens,
      required this.maxSteps,
      required this.topP,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['system_prompt'] = Variable<String>(systemPrompt);
    map['model_profile_id'] = Variable<String>(modelProfileId);
    map['enabled_tools_json'] = Variable<String>(enabledToolsJson);
    map['temperature'] = Variable<double>(temperature);
    map['max_tokens'] = Variable<int>(maxTokens);
    map['max_steps'] = Variable<int>(maxSteps);
    map['top_p'] = Variable<double>(topP);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AgentsCompanion toCompanion(bool nullToAbsent) {
    return AgentsCompanion(
      id: Value(id),
      name: Value(name),
      systemPrompt: Value(systemPrompt),
      modelProfileId: Value(modelProfileId),
      enabledToolsJson: Value(enabledToolsJson),
      temperature: Value(temperature),
      maxTokens: Value(maxTokens),
      maxSteps: Value(maxSteps),
      topP: Value(topP),
      updatedAt: Value(updatedAt),
    );
  }

  factory Agent.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Agent(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      systemPrompt: serializer.fromJson<String>(json['systemPrompt']),
      modelProfileId: serializer.fromJson<String>(json['modelProfileId']),
      enabledToolsJson: serializer.fromJson<String>(json['enabledToolsJson']),
      temperature: serializer.fromJson<double>(json['temperature']),
      maxTokens: serializer.fromJson<int>(json['maxTokens']),
      maxSteps: serializer.fromJson<int>(json['maxSteps']),
      topP: serializer.fromJson<double>(json['topP']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'systemPrompt': serializer.toJson<String>(systemPrompt),
      'modelProfileId': serializer.toJson<String>(modelProfileId),
      'enabledToolsJson': serializer.toJson<String>(enabledToolsJson),
      'temperature': serializer.toJson<double>(temperature),
      'maxTokens': serializer.toJson<int>(maxTokens),
      'maxSteps': serializer.toJson<int>(maxSteps),
      'topP': serializer.toJson<double>(topP),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Agent copyWith(
          {String? id,
          String? name,
          String? systemPrompt,
          String? modelProfileId,
          String? enabledToolsJson,
          double? temperature,
          int? maxTokens,
          int? maxSteps,
          double? topP,
          DateTime? updatedAt}) =>
      Agent(
        id: id ?? this.id,
        name: name ?? this.name,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        modelProfileId: modelProfileId ?? this.modelProfileId,
        enabledToolsJson: enabledToolsJson ?? this.enabledToolsJson,
        temperature: temperature ?? this.temperature,
        maxTokens: maxTokens ?? this.maxTokens,
        maxSteps: maxSteps ?? this.maxSteps,
        topP: topP ?? this.topP,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Agent copyWithCompanion(AgentsCompanion data) {
    return Agent(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      systemPrompt: data.systemPrompt.present
          ? data.systemPrompt.value
          : this.systemPrompt,
      modelProfileId: data.modelProfileId.present
          ? data.modelProfileId.value
          : this.modelProfileId,
      enabledToolsJson: data.enabledToolsJson.present
          ? data.enabledToolsJson.value
          : this.enabledToolsJson,
      temperature:
          data.temperature.present ? data.temperature.value : this.temperature,
      maxTokens: data.maxTokens.present ? data.maxTokens.value : this.maxTokens,
      maxSteps: data.maxSteps.present ? data.maxSteps.value : this.maxSteps,
      topP: data.topP.present ? data.topP.value : this.topP,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Agent(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('systemPrompt: $systemPrompt, ')
          ..write('modelProfileId: $modelProfileId, ')
          ..write('enabledToolsJson: $enabledToolsJson, ')
          ..write('temperature: $temperature, ')
          ..write('maxTokens: $maxTokens, ')
          ..write('maxSteps: $maxSteps, ')
          ..write('topP: $topP, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, systemPrompt, modelProfileId,
      enabledToolsJson, temperature, maxTokens, maxSteps, topP, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Agent &&
          other.id == this.id &&
          other.name == this.name &&
          other.systemPrompt == this.systemPrompt &&
          other.modelProfileId == this.modelProfileId &&
          other.enabledToolsJson == this.enabledToolsJson &&
          other.temperature == this.temperature &&
          other.maxTokens == this.maxTokens &&
          other.maxSteps == this.maxSteps &&
          other.topP == this.topP &&
          other.updatedAt == this.updatedAt);
}

class AgentsCompanion extends UpdateCompanion<Agent> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> systemPrompt;
  final Value<String> modelProfileId;
  final Value<String> enabledToolsJson;
  final Value<double> temperature;
  final Value<int> maxTokens;
  final Value<int> maxSteps;
  final Value<double> topP;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AgentsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.systemPrompt = const Value.absent(),
    this.modelProfileId = const Value.absent(),
    this.enabledToolsJson = const Value.absent(),
    this.temperature = const Value.absent(),
    this.maxTokens = const Value.absent(),
    this.maxSteps = const Value.absent(),
    this.topP = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AgentsCompanion.insert({
    required String id,
    required String name,
    this.systemPrompt = const Value.absent(),
    required String modelProfileId,
    this.enabledToolsJson = const Value.absent(),
    this.temperature = const Value.absent(),
    this.maxTokens = const Value.absent(),
    this.maxSteps = const Value.absent(),
    this.topP = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        modelProfileId = Value(modelProfileId),
        updatedAt = Value(updatedAt);
  static Insertable<Agent> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? systemPrompt,
    Expression<String>? modelProfileId,
    Expression<String>? enabledToolsJson,
    Expression<double>? temperature,
    Expression<int>? maxTokens,
    Expression<int>? maxSteps,
    Expression<double>? topP,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (systemPrompt != null) 'system_prompt': systemPrompt,
      if (modelProfileId != null) 'model_profile_id': modelProfileId,
      if (enabledToolsJson != null) 'enabled_tools_json': enabledToolsJson,
      if (temperature != null) 'temperature': temperature,
      if (maxTokens != null) 'max_tokens': maxTokens,
      if (maxSteps != null) 'max_steps': maxSteps,
      if (topP != null) 'top_p': topP,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AgentsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? systemPrompt,
      Value<String>? modelProfileId,
      Value<String>? enabledToolsJson,
      Value<double>? temperature,
      Value<int>? maxTokens,
      Value<int>? maxSteps,
      Value<double>? topP,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return AgentsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      modelProfileId: modelProfileId ?? this.modelProfileId,
      enabledToolsJson: enabledToolsJson ?? this.enabledToolsJson,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      maxSteps: maxSteps ?? this.maxSteps,
      topP: topP ?? this.topP,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (systemPrompt.present) {
      map['system_prompt'] = Variable<String>(systemPrompt.value);
    }
    if (modelProfileId.present) {
      map['model_profile_id'] = Variable<String>(modelProfileId.value);
    }
    if (enabledToolsJson.present) {
      map['enabled_tools_json'] = Variable<String>(enabledToolsJson.value);
    }
    if (temperature.present) {
      map['temperature'] = Variable<double>(temperature.value);
    }
    if (maxTokens.present) {
      map['max_tokens'] = Variable<int>(maxTokens.value);
    }
    if (maxSteps.present) {
      map['max_steps'] = Variable<int>(maxSteps.value);
    }
    if (topP.present) {
      map['top_p'] = Variable<double>(topP.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AgentsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('systemPrompt: $systemPrompt, ')
          ..write('modelProfileId: $modelProfileId, ')
          ..write('enabledToolsJson: $enabledToolsJson, ')
          ..write('temperature: $temperature, ')
          ..write('maxTokens: $maxTokens, ')
          ..write('maxSteps: $maxSteps, ')
          ..write('topP: $topP, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PromptTemplatesTable extends PromptTemplates
    with TableInfo<$PromptTemplatesTable, PromptTemplate> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PromptTemplatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('通用'));
  static const VerificationMeta _tagsJsonMeta =
      const VerificationMeta('tagsJson');
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
      'tags_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _isFavoriteMeta =
      const VerificationMeta('isFavorite');
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
      'is_favorite', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_favorite" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, content, category, tagsJson, isFavorite, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'prompt_templates';
  @override
  VerificationContext validateIntegrity(Insertable<PromptTemplate> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    }
    if (data.containsKey('tags_json')) {
      context.handle(_tagsJsonMeta,
          tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta));
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
          _isFavoriteMeta,
          isFavorite.isAcceptableOrUnknown(
              data['is_favorite']!, _isFavoriteMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PromptTemplate map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PromptTemplate(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
      tagsJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tags_json'])!,
      isFavorite: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_favorite'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $PromptTemplatesTable createAlias(String alias) {
    return $PromptTemplatesTable(attachedDatabase, alias);
  }
}

class PromptTemplate extends DataClass implements Insertable<PromptTemplate> {
  final String id;
  final String name;
  final String content;
  final String category;
  final String tagsJson;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;
  const PromptTemplate(
      {required this.id,
      required this.name,
      required this.content,
      required this.category,
      required this.tagsJson,
      required this.isFavorite,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['content'] = Variable<String>(content);
    map['category'] = Variable<String>(category);
    map['tags_json'] = Variable<String>(tagsJson);
    map['is_favorite'] = Variable<bool>(isFavorite);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PromptTemplatesCompanion toCompanion(bool nullToAbsent) {
    return PromptTemplatesCompanion(
      id: Value(id),
      name: Value(name),
      content: Value(content),
      category: Value(category),
      tagsJson: Value(tagsJson),
      isFavorite: Value(isFavorite),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory PromptTemplate.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PromptTemplate(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      content: serializer.fromJson<String>(json['content']),
      category: serializer.fromJson<String>(json['category']),
      tagsJson: serializer.fromJson<String>(json['tagsJson']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'content': serializer.toJson<String>(content),
      'category': serializer.toJson<String>(category),
      'tagsJson': serializer.toJson<String>(tagsJson),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PromptTemplate copyWith(
          {String? id,
          String? name,
          String? content,
          String? category,
          String? tagsJson,
          bool? isFavorite,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      PromptTemplate(
        id: id ?? this.id,
        name: name ?? this.name,
        content: content ?? this.content,
        category: category ?? this.category,
        tagsJson: tagsJson ?? this.tagsJson,
        isFavorite: isFavorite ?? this.isFavorite,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  PromptTemplate copyWithCompanion(PromptTemplatesCompanion data) {
    return PromptTemplate(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      content: data.content.present ? data.content.value : this.content,
      category: data.category.present ? data.category.value : this.category,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      isFavorite:
          data.isFavorite.present ? data.isFavorite.value : this.isFavorite,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PromptTemplate(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('content: $content, ')
          ..write('category: $category, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, name, content, category, tagsJson, isFavorite, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PromptTemplate &&
          other.id == this.id &&
          other.name == this.name &&
          other.content == this.content &&
          other.category == this.category &&
          other.tagsJson == this.tagsJson &&
          other.isFavorite == this.isFavorite &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PromptTemplatesCompanion extends UpdateCompanion<PromptTemplate> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> content;
  final Value<String> category;
  final Value<String> tagsJson;
  final Value<bool> isFavorite;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const PromptTemplatesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.content = const Value.absent(),
    this.category = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PromptTemplatesCompanion.insert({
    required String id,
    required String name,
    required String content,
    this.category = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.isFavorite = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        content = Value(content),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<PromptTemplate> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? content,
    Expression<String>? category,
    Expression<String>? tagsJson,
    Expression<bool>? isFavorite,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (content != null) 'content': content,
      if (category != null) 'category': category,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PromptTemplatesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? content,
      Value<String>? category,
      Value<String>? tagsJson,
      Value<bool>? isFavorite,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return PromptTemplatesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      content: content ?? this.content,
      category: category ?? this.category,
      tagsJson: tagsJson ?? this.tagsJson,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PromptTemplatesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('content: $content, ')
          ..write('category: $category, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ModelProfilesTable extends ModelProfiles
    with TableInfo<$ModelProfilesTable, ModelProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ModelProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _baseUrlMeta =
      const VerificationMeta('baseUrl');
  @override
  late final GeneratedColumn<String> baseUrl = GeneratedColumn<String>(
      'base_url', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _modelNameMeta =
      const VerificationMeta('modelName');
  @override
  late final GeneratedColumn<String> modelName = GeneratedColumn<String>(
      'model_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _apiKeyRefMeta =
      const VerificationMeta('apiKeyRef');
  @override
  late final GeneratedColumn<String> apiKeyRef = GeneratedColumn<String>(
      'api_key_ref', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, baseUrl, modelName, apiKeyRef, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'model_profiles';
  @override
  VerificationContext validateIntegrity(Insertable<ModelProfile> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('base_url')) {
      context.handle(_baseUrlMeta,
          baseUrl.isAcceptableOrUnknown(data['base_url']!, _baseUrlMeta));
    } else if (isInserting) {
      context.missing(_baseUrlMeta);
    }
    if (data.containsKey('model_name')) {
      context.handle(_modelNameMeta,
          modelName.isAcceptableOrUnknown(data['model_name']!, _modelNameMeta));
    } else if (isInserting) {
      context.missing(_modelNameMeta);
    }
    if (data.containsKey('api_key_ref')) {
      context.handle(
          _apiKeyRefMeta,
          apiKeyRef.isAcceptableOrUnknown(
              data['api_key_ref']!, _apiKeyRefMeta));
    } else if (isInserting) {
      context.missing(_apiKeyRefMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ModelProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ModelProfile(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      baseUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}base_url'])!,
      modelName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}model_name'])!,
      apiKeyRef: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}api_key_ref'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ModelProfilesTable createAlias(String alias) {
    return $ModelProfilesTable(attachedDatabase, alias);
  }
}

class ModelProfile extends DataClass implements Insertable<ModelProfile> {
  final String id;
  final String name;
  final String baseUrl;
  final String modelName;
  final String apiKeyRef;
  final DateTime updatedAt;
  const ModelProfile(
      {required this.id,
      required this.name,
      required this.baseUrl,
      required this.modelName,
      required this.apiKeyRef,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['base_url'] = Variable<String>(baseUrl);
    map['model_name'] = Variable<String>(modelName);
    map['api_key_ref'] = Variable<String>(apiKeyRef);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ModelProfilesCompanion toCompanion(bool nullToAbsent) {
    return ModelProfilesCompanion(
      id: Value(id),
      name: Value(name),
      baseUrl: Value(baseUrl),
      modelName: Value(modelName),
      apiKeyRef: Value(apiKeyRef),
      updatedAt: Value(updatedAt),
    );
  }

  factory ModelProfile.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ModelProfile(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      baseUrl: serializer.fromJson<String>(json['baseUrl']),
      modelName: serializer.fromJson<String>(json['modelName']),
      apiKeyRef: serializer.fromJson<String>(json['apiKeyRef']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'baseUrl': serializer.toJson<String>(baseUrl),
      'modelName': serializer.toJson<String>(modelName),
      'apiKeyRef': serializer.toJson<String>(apiKeyRef),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ModelProfile copyWith(
          {String? id,
          String? name,
          String? baseUrl,
          String? modelName,
          String? apiKeyRef,
          DateTime? updatedAt}) =>
      ModelProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        modelName: modelName ?? this.modelName,
        apiKeyRef: apiKeyRef ?? this.apiKeyRef,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  ModelProfile copyWithCompanion(ModelProfilesCompanion data) {
    return ModelProfile(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      baseUrl: data.baseUrl.present ? data.baseUrl.value : this.baseUrl,
      modelName: data.modelName.present ? data.modelName.value : this.modelName,
      apiKeyRef: data.apiKeyRef.present ? data.apiKeyRef.value : this.apiKeyRef,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ModelProfile(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('modelName: $modelName, ')
          ..write('apiKeyRef: $apiKeyRef, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, baseUrl, modelName, apiKeyRef, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ModelProfile &&
          other.id == this.id &&
          other.name == this.name &&
          other.baseUrl == this.baseUrl &&
          other.modelName == this.modelName &&
          other.apiKeyRef == this.apiKeyRef &&
          other.updatedAt == this.updatedAt);
}

class ModelProfilesCompanion extends UpdateCompanion<ModelProfile> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> baseUrl;
  final Value<String> modelName;
  final Value<String> apiKeyRef;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ModelProfilesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.modelName = const Value.absent(),
    this.apiKeyRef = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ModelProfilesCompanion.insert({
    required String id,
    required String name,
    required String baseUrl,
    required String modelName,
    required String apiKeyRef,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        baseUrl = Value(baseUrl),
        modelName = Value(modelName),
        apiKeyRef = Value(apiKeyRef),
        updatedAt = Value(updatedAt);
  static Insertable<ModelProfile> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? baseUrl,
    Expression<String>? modelName,
    Expression<String>? apiKeyRef,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (baseUrl != null) 'base_url': baseUrl,
      if (modelName != null) 'model_name': modelName,
      if (apiKeyRef != null) 'api_key_ref': apiKeyRef,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ModelProfilesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? baseUrl,
      Value<String>? modelName,
      Value<String>? apiKeyRef,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return ModelProfilesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      modelName: modelName ?? this.modelName,
      apiKeyRef: apiKeyRef ?? this.apiKeyRef,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (baseUrl.present) {
      map['base_url'] = Variable<String>(baseUrl.value);
    }
    if (modelName.present) {
      map['model_name'] = Variable<String>(modelName.value);
    }
    if (apiKeyRef.present) {
      map['api_key_ref'] = Variable<String>(apiKeyRef.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ModelProfilesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('modelName: $modelName, ')
          ..write('apiKeyRef: $apiKeyRef, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MemoriesTable extends Memories with TableInfo<$MemoriesTable, Memory> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MemoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('general'));
  static const VerificationMeta _sourceConversationIdMeta =
      const VerificationMeta('sourceConversationId');
  @override
  late final GeneratedColumn<String> sourceConversationId =
      GeneratedColumn<String>('source_conversation_id', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sourceTypeMeta =
      const VerificationMeta('sourceType');
  @override
  late final GeneratedColumn<String> sourceType = GeneratedColumn<String>(
      'source_type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('manual'));
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _importanceMeta =
      const VerificationMeta('importance');
  @override
  late final GeneratedColumn<int> importance = GeneratedColumn<int>(
      'importance', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        content,
        category,
        sourceConversationId,
        sourceType,
        enabled,
        importance,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'memories';
  @override
  VerificationContext validateIntegrity(Insertable<Memory> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    }
    if (data.containsKey('source_conversation_id')) {
      context.handle(
          _sourceConversationIdMeta,
          sourceConversationId.isAcceptableOrUnknown(
              data['source_conversation_id']!, _sourceConversationIdMeta));
    }
    if (data.containsKey('source_type')) {
      context.handle(
          _sourceTypeMeta,
          sourceType.isAcceptableOrUnknown(
              data['source_type']!, _sourceTypeMeta));
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    }
    if (data.containsKey('importance')) {
      context.handle(
          _importanceMeta,
          importance.isAcceptableOrUnknown(
              data['importance']!, _importanceMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Memory map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Memory(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
      sourceConversationId: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}source_conversation_id']),
      sourceType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_type'])!,
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
      importance: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}importance'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $MemoriesTable createAlias(String alias) {
    return $MemoriesTable(attachedDatabase, alias);
  }
}

class Memory extends DataClass implements Insertable<Memory> {
  final String id;
  final String content;
  final String category;
  final String? sourceConversationId;
  final String sourceType;
  final bool enabled;
  final int importance;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Memory(
      {required this.id,
      required this.content,
      required this.category,
      this.sourceConversationId,
      required this.sourceType,
      required this.enabled,
      required this.importance,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['content'] = Variable<String>(content);
    map['category'] = Variable<String>(category);
    if (!nullToAbsent || sourceConversationId != null) {
      map['source_conversation_id'] = Variable<String>(sourceConversationId);
    }
    map['source_type'] = Variable<String>(sourceType);
    map['enabled'] = Variable<bool>(enabled);
    map['importance'] = Variable<int>(importance);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  MemoriesCompanion toCompanion(bool nullToAbsent) {
    return MemoriesCompanion(
      id: Value(id),
      content: Value(content),
      category: Value(category),
      sourceConversationId: sourceConversationId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceConversationId),
      sourceType: Value(sourceType),
      enabled: Value(enabled),
      importance: Value(importance),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Memory.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Memory(
      id: serializer.fromJson<String>(json['id']),
      content: serializer.fromJson<String>(json['content']),
      category: serializer.fromJson<String>(json['category']),
      sourceConversationId:
          serializer.fromJson<String?>(json['sourceConversationId']),
      sourceType: serializer.fromJson<String>(json['sourceType']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      importance: serializer.fromJson<int>(json['importance']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'content': serializer.toJson<String>(content),
      'category': serializer.toJson<String>(category),
      'sourceConversationId': serializer.toJson<String?>(sourceConversationId),
      'sourceType': serializer.toJson<String>(sourceType),
      'enabled': serializer.toJson<bool>(enabled),
      'importance': serializer.toJson<int>(importance),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Memory copyWith(
          {String? id,
          String? content,
          String? category,
          Value<String?> sourceConversationId = const Value.absent(),
          String? sourceType,
          bool? enabled,
          int? importance,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Memory(
        id: id ?? this.id,
        content: content ?? this.content,
        category: category ?? this.category,
        sourceConversationId: sourceConversationId.present
            ? sourceConversationId.value
            : this.sourceConversationId,
        sourceType: sourceType ?? this.sourceType,
        enabled: enabled ?? this.enabled,
        importance: importance ?? this.importance,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Memory copyWithCompanion(MemoriesCompanion data) {
    return Memory(
      id: data.id.present ? data.id.value : this.id,
      content: data.content.present ? data.content.value : this.content,
      category: data.category.present ? data.category.value : this.category,
      sourceConversationId: data.sourceConversationId.present
          ? data.sourceConversationId.value
          : this.sourceConversationId,
      sourceType:
          data.sourceType.present ? data.sourceType.value : this.sourceType,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      importance:
          data.importance.present ? data.importance.value : this.importance,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Memory(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('category: $category, ')
          ..write('sourceConversationId: $sourceConversationId, ')
          ..write('sourceType: $sourceType, ')
          ..write('enabled: $enabled, ')
          ..write('importance: $importance, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, content, category, sourceConversationId,
      sourceType, enabled, importance, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Memory &&
          other.id == this.id &&
          other.content == this.content &&
          other.category == this.category &&
          other.sourceConversationId == this.sourceConversationId &&
          other.sourceType == this.sourceType &&
          other.enabled == this.enabled &&
          other.importance == this.importance &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class MemoriesCompanion extends UpdateCompanion<Memory> {
  final Value<String> id;
  final Value<String> content;
  final Value<String> category;
  final Value<String?> sourceConversationId;
  final Value<String> sourceType;
  final Value<bool> enabled;
  final Value<int> importance;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const MemoriesCompanion({
    this.id = const Value.absent(),
    this.content = const Value.absent(),
    this.category = const Value.absent(),
    this.sourceConversationId = const Value.absent(),
    this.sourceType = const Value.absent(),
    this.enabled = const Value.absent(),
    this.importance = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MemoriesCompanion.insert({
    required String id,
    required String content,
    this.category = const Value.absent(),
    this.sourceConversationId = const Value.absent(),
    this.sourceType = const Value.absent(),
    this.enabled = const Value.absent(),
    this.importance = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        content = Value(content),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<Memory> custom({
    Expression<String>? id,
    Expression<String>? content,
    Expression<String>? category,
    Expression<String>? sourceConversationId,
    Expression<String>? sourceType,
    Expression<bool>? enabled,
    Expression<int>? importance,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (content != null) 'content': content,
      if (category != null) 'category': category,
      if (sourceConversationId != null)
        'source_conversation_id': sourceConversationId,
      if (sourceType != null) 'source_type': sourceType,
      if (enabled != null) 'enabled': enabled,
      if (importance != null) 'importance': importance,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MemoriesCompanion copyWith(
      {Value<String>? id,
      Value<String>? content,
      Value<String>? category,
      Value<String?>? sourceConversationId,
      Value<String>? sourceType,
      Value<bool>? enabled,
      Value<int>? importance,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return MemoriesCompanion(
      id: id ?? this.id,
      content: content ?? this.content,
      category: category ?? this.category,
      sourceConversationId: sourceConversationId ?? this.sourceConversationId,
      sourceType: sourceType ?? this.sourceType,
      enabled: enabled ?? this.enabled,
      importance: importance ?? this.importance,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (sourceConversationId.present) {
      map['source_conversation_id'] =
          Variable<String>(sourceConversationId.value);
    }
    if (sourceType.present) {
      map['source_type'] = Variable<String>(sourceType.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (importance.present) {
      map['importance'] = Variable<int>(importance.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MemoriesCompanion(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('category: $category, ')
          ..write('sourceConversationId: $sourceConversationId, ')
          ..write('sourceType: $sourceType, ')
          ..write('enabled: $enabled, ')
          ..write('importance: $importance, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TasksTable extends Tasks with TableInfo<$TasksTable, Task> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _conversationIdMeta =
      const VerificationMeta('conversationId');
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
      'conversation_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('agent'));
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('running'));
  static const VerificationMeta _requestJsonMeta =
      const VerificationMeta('requestJson');
  @override
  late final GeneratedColumn<String> requestJson = GeneratedColumn<String>(
      'request_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _progressJsonMeta =
      const VerificationMeta('progressJson');
  @override
  late final GeneratedColumn<String> progressJson = GeneratedColumn<String>(
      'progress_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('{}'));
  static const VerificationMeta _resumeCountMeta =
      const VerificationMeta('resumeCount');
  @override
  late final GeneratedColumn<int> resumeCount = GeneratedColumn<int>(
      'resume_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        conversationId,
        type,
        status,
        requestJson,
        progressJson,
        resumeCount,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(Insertable<Task> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
          _conversationIdMeta,
          conversationId.isAcceptableOrUnknown(
              data['conversation_id']!, _conversationIdMeta));
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('request_json')) {
      context.handle(
          _requestJsonMeta,
          requestJson.isAcceptableOrUnknown(
              data['request_json']!, _requestJsonMeta));
    } else if (isInserting) {
      context.missing(_requestJsonMeta);
    }
    if (data.containsKey('progress_json')) {
      context.handle(
          _progressJsonMeta,
          progressJson.isAcceptableOrUnknown(
              data['progress_json']!, _progressJsonMeta));
    }
    if (data.containsKey('resume_count')) {
      context.handle(
          _resumeCountMeta,
          resumeCount.isAcceptableOrUnknown(
              data['resume_count']!, _resumeCountMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Task map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Task(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      conversationId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}conversation_id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      requestJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}request_json'])!,
      progressJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}progress_json'])!,
      resumeCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}resume_count'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }
}

class Task extends DataClass implements Insertable<Task> {
  final String id;
  final String conversationId;
  final String type;
  final String status;
  final String requestJson;
  final String progressJson;
  final int resumeCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Task(
      {required this.id,
      required this.conversationId,
      required this.type,
      required this.status,
      required this.requestJson,
      required this.progressJson,
      required this.resumeCount,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    map['type'] = Variable<String>(type);
    map['status'] = Variable<String>(status);
    map['request_json'] = Variable<String>(requestJson);
    map['progress_json'] = Variable<String>(progressJson);
    map['resume_count'] = Variable<int>(resumeCount);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      type: Value(type),
      status: Value(status),
      requestJson: Value(requestJson),
      progressJson: Value(progressJson),
      resumeCount: Value(resumeCount),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Task.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Task(
      id: serializer.fromJson<String>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      type: serializer.fromJson<String>(json['type']),
      status: serializer.fromJson<String>(json['status']),
      requestJson: serializer.fromJson<String>(json['requestJson']),
      progressJson: serializer.fromJson<String>(json['progressJson']),
      resumeCount: serializer.fromJson<int>(json['resumeCount']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'type': serializer.toJson<String>(type),
      'status': serializer.toJson<String>(status),
      'requestJson': serializer.toJson<String>(requestJson),
      'progressJson': serializer.toJson<String>(progressJson),
      'resumeCount': serializer.toJson<int>(resumeCount),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Task copyWith(
          {String? id,
          String? conversationId,
          String? type,
          String? status,
          String? requestJson,
          String? progressJson,
          int? resumeCount,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Task(
        id: id ?? this.id,
        conversationId: conversationId ?? this.conversationId,
        type: type ?? this.type,
        status: status ?? this.status,
        requestJson: requestJson ?? this.requestJson,
        progressJson: progressJson ?? this.progressJson,
        resumeCount: resumeCount ?? this.resumeCount,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Task copyWithCompanion(TasksCompanion data) {
    return Task(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      type: data.type.present ? data.type.value : this.type,
      status: data.status.present ? data.status.value : this.status,
      requestJson:
          data.requestJson.present ? data.requestJson.value : this.requestJson,
      progressJson: data.progressJson.present
          ? data.progressJson.value
          : this.progressJson,
      resumeCount:
          data.resumeCount.present ? data.resumeCount.value : this.resumeCount,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Task(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('type: $type, ')
          ..write('status: $status, ')
          ..write('requestJson: $requestJson, ')
          ..write('progressJson: $progressJson, ')
          ..write('resumeCount: $resumeCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, conversationId, type, status, requestJson,
      progressJson, resumeCount, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Task &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.type == this.type &&
          other.status == this.status &&
          other.requestJson == this.requestJson &&
          other.progressJson == this.progressJson &&
          other.resumeCount == this.resumeCount &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TasksCompanion extends UpdateCompanion<Task> {
  final Value<String> id;
  final Value<String> conversationId;
  final Value<String> type;
  final Value<String> status;
  final Value<String> requestJson;
  final Value<String> progressJson;
  final Value<int> resumeCount;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.type = const Value.absent(),
    this.status = const Value.absent(),
    this.requestJson = const Value.absent(),
    this.progressJson = const Value.absent(),
    this.resumeCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TasksCompanion.insert({
    required String id,
    required String conversationId,
    this.type = const Value.absent(),
    this.status = const Value.absent(),
    required String requestJson,
    this.progressJson = const Value.absent(),
    this.resumeCount = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        conversationId = Value(conversationId),
        requestJson = Value(requestJson),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<Task> custom({
    Expression<String>? id,
    Expression<String>? conversationId,
    Expression<String>? type,
    Expression<String>? status,
    Expression<String>? requestJson,
    Expression<String>? progressJson,
    Expression<int>? resumeCount,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (type != null) 'type': type,
      if (status != null) 'status': status,
      if (requestJson != null) 'request_json': requestJson,
      if (progressJson != null) 'progress_json': progressJson,
      if (resumeCount != null) 'resume_count': resumeCount,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TasksCompanion copyWith(
      {Value<String>? id,
      Value<String>? conversationId,
      Value<String>? type,
      Value<String>? status,
      Value<String>? requestJson,
      Value<String>? progressJson,
      Value<int>? resumeCount,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return TasksCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      type: type ?? this.type,
      status: status ?? this.status,
      requestJson: requestJson ?? this.requestJson,
      progressJson: progressJson ?? this.progressJson,
      resumeCount: resumeCount ?? this.resumeCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (requestJson.present) {
      map['request_json'] = Variable<String>(requestJson.value);
    }
    if (progressJson.present) {
      map['progress_json'] = Variable<String>(progressJson.value);
    }
    if (resumeCount.present) {
      map['resume_count'] = Variable<int>(resumeCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('type: $type, ')
          ..write('status: $status, ')
          ..write('requestJson: $requestJson, ')
          ..write('progressJson: $progressJson, ')
          ..write('resumeCount: $resumeCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncMetaTable extends SyncMeta
    with TableInfo<$SyncMetaTable, SyncMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _objectIdMeta =
      const VerificationMeta('objectId');
  @override
  late final GeneratedColumn<String> objectId = GeneratedColumn<String>(
      'object_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _tableMeta = const VerificationMeta('table');
  @override
  late final GeneratedColumn<String> table = GeneratedColumn<String>(
      'table', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _rowJsonMeta =
      const VerificationMeta('rowJson');
  @override
  late final GeneratedColumn<String> rowJson = GeneratedColumn<String>(
      'row_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
      'dirty', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("dirty" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [objectId, table, rowJson, version, dirty, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_meta';
  @override
  VerificationContext validateIntegrity(Insertable<SyncMetaData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('object_id')) {
      context.handle(_objectIdMeta,
          objectId.isAcceptableOrUnknown(data['object_id']!, _objectIdMeta));
    } else if (isInserting) {
      context.missing(_objectIdMeta);
    }
    if (data.containsKey('table')) {
      context.handle(
          _tableMeta, table.isAcceptableOrUnknown(data['table']!, _tableMeta));
    } else if (isInserting) {
      context.missing(_tableMeta);
    }
    if (data.containsKey('row_json')) {
      context.handle(_rowJsonMeta,
          rowJson.isAcceptableOrUnknown(data['row_json']!, _rowJsonMeta));
    } else if (isInserting) {
      context.missing(_rowJsonMeta);
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    }
    if (data.containsKey('dirty')) {
      context.handle(
          _dirtyMeta, dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {objectId};
  @override
  SyncMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetaData(
      objectId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}object_id'])!,
      table: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}table'])!,
      rowJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}row_json'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      dirty: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}dirty'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $SyncMetaTable createAlias(String alias) {
    return $SyncMetaTable(attachedDatabase, alias);
  }
}

class SyncMetaData extends DataClass implements Insertable<SyncMetaData> {
  final String objectId;
  final String table;
  final String rowJson;
  final int version;
  final bool dirty;
  final DateTime updatedAt;
  const SyncMetaData(
      {required this.objectId,
      required this.table,
      required this.rowJson,
      required this.version,
      required this.dirty,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['object_id'] = Variable<String>(objectId);
    map['table'] = Variable<String>(table);
    map['row_json'] = Variable<String>(rowJson);
    map['version'] = Variable<int>(version);
    map['dirty'] = Variable<bool>(dirty);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SyncMetaCompanion toCompanion(bool nullToAbsent) {
    return SyncMetaCompanion(
      objectId: Value(objectId),
      table: Value(table),
      rowJson: Value(rowJson),
      version: Value(version),
      dirty: Value(dirty),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncMetaData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetaData(
      objectId: serializer.fromJson<String>(json['objectId']),
      table: serializer.fromJson<String>(json['table']),
      rowJson: serializer.fromJson<String>(json['rowJson']),
      version: serializer.fromJson<int>(json['version']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'objectId': serializer.toJson<String>(objectId),
      'table': serializer.toJson<String>(table),
      'rowJson': serializer.toJson<String>(rowJson),
      'version': serializer.toJson<int>(version),
      'dirty': serializer.toJson<bool>(dirty),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SyncMetaData copyWith(
          {String? objectId,
          String? table,
          String? rowJson,
          int? version,
          bool? dirty,
          DateTime? updatedAt}) =>
      SyncMetaData(
        objectId: objectId ?? this.objectId,
        table: table ?? this.table,
        rowJson: rowJson ?? this.rowJson,
        version: version ?? this.version,
        dirty: dirty ?? this.dirty,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  SyncMetaData copyWithCompanion(SyncMetaCompanion data) {
    return SyncMetaData(
      objectId: data.objectId.present ? data.objectId.value : this.objectId,
      table: data.table.present ? data.table.value : this.table,
      rowJson: data.rowJson.present ? data.rowJson.value : this.rowJson,
      version: data.version.present ? data.version.value : this.version,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaData(')
          ..write('objectId: $objectId, ')
          ..write('table: $table, ')
          ..write('rowJson: $rowJson, ')
          ..write('version: $version, ')
          ..write('dirty: $dirty, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(objectId, table, rowJson, version, dirty, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetaData &&
          other.objectId == this.objectId &&
          other.table == this.table &&
          other.rowJson == this.rowJson &&
          other.version == this.version &&
          other.dirty == this.dirty &&
          other.updatedAt == this.updatedAt);
}

class SyncMetaCompanion extends UpdateCompanion<SyncMetaData> {
  final Value<String> objectId;
  final Value<String> table;
  final Value<String> rowJson;
  final Value<int> version;
  final Value<bool> dirty;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SyncMetaCompanion({
    this.objectId = const Value.absent(),
    this.table = const Value.absent(),
    this.rowJson = const Value.absent(),
    this.version = const Value.absent(),
    this.dirty = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMetaCompanion.insert({
    required String objectId,
    required String table,
    required String rowJson,
    this.version = const Value.absent(),
    this.dirty = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : objectId = Value(objectId),
        table = Value(table),
        rowJson = Value(rowJson),
        updatedAt = Value(updatedAt);
  static Insertable<SyncMetaData> custom({
    Expression<String>? objectId,
    Expression<String>? table,
    Expression<String>? rowJson,
    Expression<int>? version,
    Expression<bool>? dirty,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (objectId != null) 'object_id': objectId,
      if (table != null) 'table': table,
      if (rowJson != null) 'row_json': rowJson,
      if (version != null) 'version': version,
      if (dirty != null) 'dirty': dirty,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMetaCompanion copyWith(
      {Value<String>? objectId,
      Value<String>? table,
      Value<String>? rowJson,
      Value<int>? version,
      Value<bool>? dirty,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return SyncMetaCompanion(
      objectId: objectId ?? this.objectId,
      table: table ?? this.table,
      rowJson: rowJson ?? this.rowJson,
      version: version ?? this.version,
      dirty: dirty ?? this.dirty,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (objectId.present) {
      map['object_id'] = Variable<String>(objectId.value);
    }
    if (table.present) {
      map['table'] = Variable<String>(table.value);
    }
    if (rowJson.present) {
      map['row_json'] = Variable<String>(rowJson.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaCompanion(')
          ..write('objectId: $objectId, ')
          ..write('table: $table, ')
          ..write('rowJson: $rowJson, ')
          ..write('version: $version, ')
          ..write('dirty: $dirty, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KnowledgeDocsTable extends KnowledgeDocs
    with TableInfo<$KnowledgeDocsTable, KnowledgeDoc> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KnowledgeDocsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sourceTypeMeta =
      const VerificationMeta('sourceType');
  @override
  late final GeneratedColumn<String> sourceType = GeneratedColumn<String>(
      'source_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _chunkCountMeta =
      const VerificationMeta('chunkCount');
  @override
  late final GeneratedColumn<int> chunkCount = GeneratedColumn<int>(
      'chunk_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, sourceType, chunkCount, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'knowledge_docs';
  @override
  VerificationContext validateIntegrity(Insertable<KnowledgeDoc> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('source_type')) {
      context.handle(
          _sourceTypeMeta,
          sourceType.isAcceptableOrUnknown(
              data['source_type']!, _sourceTypeMeta));
    } else if (isInserting) {
      context.missing(_sourceTypeMeta);
    }
    if (data.containsKey('chunk_count')) {
      context.handle(
          _chunkCountMeta,
          chunkCount.isAcceptableOrUnknown(
              data['chunk_count']!, _chunkCountMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  KnowledgeDoc map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KnowledgeDoc(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      sourceType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_type'])!,
      chunkCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}chunk_count'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $KnowledgeDocsTable createAlias(String alias) {
    return $KnowledgeDocsTable(attachedDatabase, alias);
  }
}

class KnowledgeDoc extends DataClass implements Insertable<KnowledgeDoc> {
  final String id;
  final String name;
  final String sourceType;
  final int chunkCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  const KnowledgeDoc(
      {required this.id,
      required this.name,
      required this.sourceType,
      required this.chunkCount,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['source_type'] = Variable<String>(sourceType);
    map['chunk_count'] = Variable<int>(chunkCount);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  KnowledgeDocsCompanion toCompanion(bool nullToAbsent) {
    return KnowledgeDocsCompanion(
      id: Value(id),
      name: Value(name),
      sourceType: Value(sourceType),
      chunkCount: Value(chunkCount),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory KnowledgeDoc.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KnowledgeDoc(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      sourceType: serializer.fromJson<String>(json['sourceType']),
      chunkCount: serializer.fromJson<int>(json['chunkCount']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'sourceType': serializer.toJson<String>(sourceType),
      'chunkCount': serializer.toJson<int>(chunkCount),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  KnowledgeDoc copyWith(
          {String? id,
          String? name,
          String? sourceType,
          int? chunkCount,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      KnowledgeDoc(
        id: id ?? this.id,
        name: name ?? this.name,
        sourceType: sourceType ?? this.sourceType,
        chunkCount: chunkCount ?? this.chunkCount,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  KnowledgeDoc copyWithCompanion(KnowledgeDocsCompanion data) {
    return KnowledgeDoc(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      sourceType:
          data.sourceType.present ? data.sourceType.value : this.sourceType,
      chunkCount:
          data.chunkCount.present ? data.chunkCount.value : this.chunkCount,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KnowledgeDoc(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sourceType: $sourceType, ')
          ..write('chunkCount: $chunkCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, sourceType, chunkCount, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KnowledgeDoc &&
          other.id == this.id &&
          other.name == this.name &&
          other.sourceType == this.sourceType &&
          other.chunkCount == this.chunkCount &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class KnowledgeDocsCompanion extends UpdateCompanion<KnowledgeDoc> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> sourceType;
  final Value<int> chunkCount;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const KnowledgeDocsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.sourceType = const Value.absent(),
    this.chunkCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KnowledgeDocsCompanion.insert({
    required String id,
    required String name,
    required String sourceType,
    this.chunkCount = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        sourceType = Value(sourceType),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<KnowledgeDoc> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? sourceType,
    Expression<int>? chunkCount,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (sourceType != null) 'source_type': sourceType,
      if (chunkCount != null) 'chunk_count': chunkCount,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KnowledgeDocsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? sourceType,
      Value<int>? chunkCount,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return KnowledgeDocsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      sourceType: sourceType ?? this.sourceType,
      chunkCount: chunkCount ?? this.chunkCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sourceType.present) {
      map['source_type'] = Variable<String>(sourceType.value);
    }
    if (chunkCount.present) {
      map['chunk_count'] = Variable<int>(chunkCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KnowledgeDocsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sourceType: $sourceType, ')
          ..write('chunkCount: $chunkCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KnowledgeChunksTable extends KnowledgeChunks
    with TableInfo<$KnowledgeChunksTable, KnowledgeChunk> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KnowledgeChunksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _docIdMeta = const VerificationMeta('docId');
  @override
  late final GeneratedColumn<String> docId = GeneratedColumn<String>(
      'doc_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _embeddingJsonMeta =
      const VerificationMeta('embeddingJson');
  @override
  late final GeneratedColumn<String> embeddingJson = GeneratedColumn<String>(
      'embedding_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _indexMeta = const VerificationMeta('index');
  @override
  late final GeneratedColumn<int> index = GeneratedColumn<int>(
      'index', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, docId, content, embeddingJson, index];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'knowledge_chunks';
  @override
  VerificationContext validateIntegrity(Insertable<KnowledgeChunk> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('doc_id')) {
      context.handle(
          _docIdMeta, docId.isAcceptableOrUnknown(data['doc_id']!, _docIdMeta));
    } else if (isInserting) {
      context.missing(_docIdMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('embedding_json')) {
      context.handle(
          _embeddingJsonMeta,
          embeddingJson.isAcceptableOrUnknown(
              data['embedding_json']!, _embeddingJsonMeta));
    }
    if (data.containsKey('index')) {
      context.handle(
          _indexMeta, index.isAcceptableOrUnknown(data['index']!, _indexMeta));
    } else if (isInserting) {
      context.missing(_indexMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  KnowledgeChunk map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KnowledgeChunk(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      docId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}doc_id'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      embeddingJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}embedding_json']),
      index: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}index'])!,
    );
  }

  @override
  $KnowledgeChunksTable createAlias(String alias) {
    return $KnowledgeChunksTable(attachedDatabase, alias);
  }
}

class KnowledgeChunk extends DataClass implements Insertable<KnowledgeChunk> {
  final String id;
  final String docId;
  final String content;
  final String? embeddingJson;
  final int index;
  const KnowledgeChunk(
      {required this.id,
      required this.docId,
      required this.content,
      this.embeddingJson,
      required this.index});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['doc_id'] = Variable<String>(docId);
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || embeddingJson != null) {
      map['embedding_json'] = Variable<String>(embeddingJson);
    }
    map['index'] = Variable<int>(index);
    return map;
  }

  KnowledgeChunksCompanion toCompanion(bool nullToAbsent) {
    return KnowledgeChunksCompanion(
      id: Value(id),
      docId: Value(docId),
      content: Value(content),
      embeddingJson: embeddingJson == null && nullToAbsent
          ? const Value.absent()
          : Value(embeddingJson),
      index: Value(index),
    );
  }

  factory KnowledgeChunk.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KnowledgeChunk(
      id: serializer.fromJson<String>(json['id']),
      docId: serializer.fromJson<String>(json['docId']),
      content: serializer.fromJson<String>(json['content']),
      embeddingJson: serializer.fromJson<String?>(json['embeddingJson']),
      index: serializer.fromJson<int>(json['index']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'docId': serializer.toJson<String>(docId),
      'content': serializer.toJson<String>(content),
      'embeddingJson': serializer.toJson<String?>(embeddingJson),
      'index': serializer.toJson<int>(index),
    };
  }

  KnowledgeChunk copyWith(
          {String? id,
          String? docId,
          String? content,
          Value<String?> embeddingJson = const Value.absent(),
          int? index}) =>
      KnowledgeChunk(
        id: id ?? this.id,
        docId: docId ?? this.docId,
        content: content ?? this.content,
        embeddingJson:
            embeddingJson.present ? embeddingJson.value : this.embeddingJson,
        index: index ?? this.index,
      );
  KnowledgeChunk copyWithCompanion(KnowledgeChunksCompanion data) {
    return KnowledgeChunk(
      id: data.id.present ? data.id.value : this.id,
      docId: data.docId.present ? data.docId.value : this.docId,
      content: data.content.present ? data.content.value : this.content,
      embeddingJson: data.embeddingJson.present
          ? data.embeddingJson.value
          : this.embeddingJson,
      index: data.index.present ? data.index.value : this.index,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KnowledgeChunk(')
          ..write('id: $id, ')
          ..write('docId: $docId, ')
          ..write('content: $content, ')
          ..write('embeddingJson: $embeddingJson, ')
          ..write('index: $index')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, docId, content, embeddingJson, index);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KnowledgeChunk &&
          other.id == this.id &&
          other.docId == this.docId &&
          other.content == this.content &&
          other.embeddingJson == this.embeddingJson &&
          other.index == this.index);
}

class KnowledgeChunksCompanion extends UpdateCompanion<KnowledgeChunk> {
  final Value<String> id;
  final Value<String> docId;
  final Value<String> content;
  final Value<String?> embeddingJson;
  final Value<int> index;
  final Value<int> rowid;
  const KnowledgeChunksCompanion({
    this.id = const Value.absent(),
    this.docId = const Value.absent(),
    this.content = const Value.absent(),
    this.embeddingJson = const Value.absent(),
    this.index = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KnowledgeChunksCompanion.insert({
    required String id,
    required String docId,
    required String content,
    this.embeddingJson = const Value.absent(),
    required int index,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        docId = Value(docId),
        content = Value(content),
        index = Value(index);
  static Insertable<KnowledgeChunk> custom({
    Expression<String>? id,
    Expression<String>? docId,
    Expression<String>? content,
    Expression<String>? embeddingJson,
    Expression<int>? index,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (docId != null) 'doc_id': docId,
      if (content != null) 'content': content,
      if (embeddingJson != null) 'embedding_json': embeddingJson,
      if (index != null) 'index': index,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KnowledgeChunksCompanion copyWith(
      {Value<String>? id,
      Value<String>? docId,
      Value<String>? content,
      Value<String?>? embeddingJson,
      Value<int>? index,
      Value<int>? rowid}) {
    return KnowledgeChunksCompanion(
      id: id ?? this.id,
      docId: docId ?? this.docId,
      content: content ?? this.content,
      embeddingJson: embeddingJson ?? this.embeddingJson,
      index: index ?? this.index,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (docId.present) {
      map['doc_id'] = Variable<String>(docId.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (embeddingJson.present) {
      map['embedding_json'] = Variable<String>(embeddingJson.value);
    }
    if (index.present) {
      map['index'] = Variable<int>(index.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KnowledgeChunksCompanion(')
          ..write('id: $id, ')
          ..write('docId: $docId, ')
          ..write('content: $content, ')
          ..write('embeddingJson: $embeddingJson, ')
          ..write('index: $index, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ScheduledTasksTable extends ScheduledTasks
    with TableInfo<$ScheduledTasksTable, ScheduledTask> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScheduledTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _promptMeta = const VerificationMeta('prompt');
  @override
  late final GeneratedColumn<String> prompt = GeneratedColumn<String>(
      'prompt', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cronMeta = const VerificationMeta('cron');
  @override
  late final GeneratedColumn<String> cron = GeneratedColumn<String>(
      'cron', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _agentIdMeta =
      const VerificationMeta('agentId');
  @override
  late final GeneratedColumn<String> agentId = GeneratedColumn<String>(
      'agent_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _lastResultMeta =
      const VerificationMeta('lastResult');
  @override
  late final GeneratedColumn<String> lastResult = GeneratedColumn<String>(
      'last_result', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        prompt,
        cron,
        agentId,
        enabled,
        lastResult,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scheduled_tasks';
  @override
  VerificationContext validateIntegrity(Insertable<ScheduledTask> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('prompt')) {
      context.handle(_promptMeta,
          prompt.isAcceptableOrUnknown(data['prompt']!, _promptMeta));
    } else if (isInserting) {
      context.missing(_promptMeta);
    }
    if (data.containsKey('cron')) {
      context.handle(
          _cronMeta, cron.isAcceptableOrUnknown(data['cron']!, _cronMeta));
    } else if (isInserting) {
      context.missing(_cronMeta);
    }
    if (data.containsKey('agent_id')) {
      context.handle(_agentIdMeta,
          agentId.isAcceptableOrUnknown(data['agent_id']!, _agentIdMeta));
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    }
    if (data.containsKey('last_result')) {
      context.handle(
          _lastResultMeta,
          lastResult.isAcceptableOrUnknown(
              data['last_result']!, _lastResultMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ScheduledTask map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScheduledTask(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      prompt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}prompt'])!,
      cron: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cron'])!,
      agentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}agent_id']),
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
      lastResult: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_result']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ScheduledTasksTable createAlias(String alias) {
    return $ScheduledTasksTable(attachedDatabase, alias);
  }
}

class ScheduledTask extends DataClass implements Insertable<ScheduledTask> {
  final String id;
  final String name;
  final String prompt;
  final String cron;
  final String? agentId;
  final bool enabled;
  final String? lastResult;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ScheduledTask(
      {required this.id,
      required this.name,
      required this.prompt,
      required this.cron,
      this.agentId,
      required this.enabled,
      this.lastResult,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['prompt'] = Variable<String>(prompt);
    map['cron'] = Variable<String>(cron);
    if (!nullToAbsent || agentId != null) {
      map['agent_id'] = Variable<String>(agentId);
    }
    map['enabled'] = Variable<bool>(enabled);
    if (!nullToAbsent || lastResult != null) {
      map['last_result'] = Variable<String>(lastResult);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ScheduledTasksCompanion toCompanion(bool nullToAbsent) {
    return ScheduledTasksCompanion(
      id: Value(id),
      name: Value(name),
      prompt: Value(prompt),
      cron: Value(cron),
      agentId: agentId == null && nullToAbsent
          ? const Value.absent()
          : Value(agentId),
      enabled: Value(enabled),
      lastResult: lastResult == null && nullToAbsent
          ? const Value.absent()
          : Value(lastResult),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ScheduledTask.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScheduledTask(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      prompt: serializer.fromJson<String>(json['prompt']),
      cron: serializer.fromJson<String>(json['cron']),
      agentId: serializer.fromJson<String?>(json['agentId']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      lastResult: serializer.fromJson<String?>(json['lastResult']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'prompt': serializer.toJson<String>(prompt),
      'cron': serializer.toJson<String>(cron),
      'agentId': serializer.toJson<String?>(agentId),
      'enabled': serializer.toJson<bool>(enabled),
      'lastResult': serializer.toJson<String?>(lastResult),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ScheduledTask copyWith(
          {String? id,
          String? name,
          String? prompt,
          String? cron,
          Value<String?> agentId = const Value.absent(),
          bool? enabled,
          Value<String?> lastResult = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      ScheduledTask(
        id: id ?? this.id,
        name: name ?? this.name,
        prompt: prompt ?? this.prompt,
        cron: cron ?? this.cron,
        agentId: agentId.present ? agentId.value : this.agentId,
        enabled: enabled ?? this.enabled,
        lastResult: lastResult.present ? lastResult.value : this.lastResult,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  ScheduledTask copyWithCompanion(ScheduledTasksCompanion data) {
    return ScheduledTask(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      prompt: data.prompt.present ? data.prompt.value : this.prompt,
      cron: data.cron.present ? data.cron.value : this.cron,
      agentId: data.agentId.present ? data.agentId.value : this.agentId,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      lastResult:
          data.lastResult.present ? data.lastResult.value : this.lastResult,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScheduledTask(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('prompt: $prompt, ')
          ..write('cron: $cron, ')
          ..write('agentId: $agentId, ')
          ..write('enabled: $enabled, ')
          ..write('lastResult: $lastResult, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, prompt, cron, agentId, enabled,
      lastResult, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduledTask &&
          other.id == this.id &&
          other.name == this.name &&
          other.prompt == this.prompt &&
          other.cron == this.cron &&
          other.agentId == this.agentId &&
          other.enabled == this.enabled &&
          other.lastResult == this.lastResult &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ScheduledTasksCompanion extends UpdateCompanion<ScheduledTask> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> prompt;
  final Value<String> cron;
  final Value<String?> agentId;
  final Value<bool> enabled;
  final Value<String?> lastResult;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ScheduledTasksCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.prompt = const Value.absent(),
    this.cron = const Value.absent(),
    this.agentId = const Value.absent(),
    this.enabled = const Value.absent(),
    this.lastResult = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ScheduledTasksCompanion.insert({
    required String id,
    required String name,
    required String prompt,
    required String cron,
    this.agentId = const Value.absent(),
    this.enabled = const Value.absent(),
    this.lastResult = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        prompt = Value(prompt),
        cron = Value(cron),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<ScheduledTask> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? prompt,
    Expression<String>? cron,
    Expression<String>? agentId,
    Expression<bool>? enabled,
    Expression<String>? lastResult,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (prompt != null) 'prompt': prompt,
      if (cron != null) 'cron': cron,
      if (agentId != null) 'agent_id': agentId,
      if (enabled != null) 'enabled': enabled,
      if (lastResult != null) 'last_result': lastResult,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ScheduledTasksCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? prompt,
      Value<String>? cron,
      Value<String?>? agentId,
      Value<bool>? enabled,
      Value<String?>? lastResult,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return ScheduledTasksCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      prompt: prompt ?? this.prompt,
      cron: cron ?? this.cron,
      agentId: agentId ?? this.agentId,
      enabled: enabled ?? this.enabled,
      lastResult: lastResult ?? this.lastResult,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (prompt.present) {
      map['prompt'] = Variable<String>(prompt.value);
    }
    if (cron.present) {
      map['cron'] = Variable<String>(cron.value);
    }
    if (agentId.present) {
      map['agent_id'] = Variable<String>(agentId.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (lastResult.present) {
      map['last_result'] = Variable<String>(lastResult.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScheduledTasksCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('prompt: $prompt, ')
          ..write('cron: $cron, ')
          ..write('agentId: $agentId, ')
          ..write('enabled: $enabled, ')
          ..write('lastResult: $lastResult, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AuditLogsTable extends AuditLogs
    with TableInfo<$AuditLogsTable, AuditLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AuditLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _conversationIdMeta =
      const VerificationMeta('conversationId');
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
      'conversation_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _detailMeta = const VerificationMeta('detail');
  @override
  late final GeneratedColumn<String> detail = GeneratedColumn<String>(
      'detail', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _decisionMeta =
      const VerificationMeta('decision');
  @override
  late final GeneratedColumn<String> decision = GeneratedColumn<String>(
      'decision', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _riskMeta = const VerificationMeta('risk');
  @override
  late final GeneratedColumn<String> risk = GeneratedColumn<String>(
      'risk', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, conversationId, type, detail, decision, risk, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'audit_logs';
  @override
  VerificationContext validateIntegrity(Insertable<AuditLog> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
          _conversationIdMeta,
          conversationId.isAcceptableOrUnknown(
              data['conversation_id']!, _conversationIdMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('detail')) {
      context.handle(_detailMeta,
          detail.isAcceptableOrUnknown(data['detail']!, _detailMeta));
    } else if (isInserting) {
      context.missing(_detailMeta);
    }
    if (data.containsKey('decision')) {
      context.handle(_decisionMeta,
          decision.isAcceptableOrUnknown(data['decision']!, _decisionMeta));
    }
    if (data.containsKey('risk')) {
      context.handle(
          _riskMeta, risk.isAcceptableOrUnknown(data['risk']!, _riskMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AuditLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AuditLog(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      conversationId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}conversation_id']),
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      detail: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}detail'])!,
      decision: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}decision']),
      risk: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}risk']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $AuditLogsTable createAlias(String alias) {
    return $AuditLogsTable(attachedDatabase, alias);
  }
}

class AuditLog extends DataClass implements Insertable<AuditLog> {
  final String id;
  final String? conversationId;
  final String type;
  final String detail;
  final String? decision;
  final String? risk;
  final DateTime createdAt;
  const AuditLog(
      {required this.id,
      this.conversationId,
      required this.type,
      required this.detail,
      this.decision,
      this.risk,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || conversationId != null) {
      map['conversation_id'] = Variable<String>(conversationId);
    }
    map['type'] = Variable<String>(type);
    map['detail'] = Variable<String>(detail);
    if (!nullToAbsent || decision != null) {
      map['decision'] = Variable<String>(decision);
    }
    if (!nullToAbsent || risk != null) {
      map['risk'] = Variable<String>(risk);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  AuditLogsCompanion toCompanion(bool nullToAbsent) {
    return AuditLogsCompanion(
      id: Value(id),
      conversationId: conversationId == null && nullToAbsent
          ? const Value.absent()
          : Value(conversationId),
      type: Value(type),
      detail: Value(detail),
      decision: decision == null && nullToAbsent
          ? const Value.absent()
          : Value(decision),
      risk: risk == null && nullToAbsent ? const Value.absent() : Value(risk),
      createdAt: Value(createdAt),
    );
  }

  factory AuditLog.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AuditLog(
      id: serializer.fromJson<String>(json['id']),
      conversationId: serializer.fromJson<String?>(json['conversationId']),
      type: serializer.fromJson<String>(json['type']),
      detail: serializer.fromJson<String>(json['detail']),
      decision: serializer.fromJson<String?>(json['decision']),
      risk: serializer.fromJson<String?>(json['risk']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationId': serializer.toJson<String?>(conversationId),
      'type': serializer.toJson<String>(type),
      'detail': serializer.toJson<String>(detail),
      'decision': serializer.toJson<String?>(decision),
      'risk': serializer.toJson<String?>(risk),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  AuditLog copyWith(
          {String? id,
          Value<String?> conversationId = const Value.absent(),
          String? type,
          String? detail,
          Value<String?> decision = const Value.absent(),
          Value<String?> risk = const Value.absent(),
          DateTime? createdAt}) =>
      AuditLog(
        id: id ?? this.id,
        conversationId:
            conversationId.present ? conversationId.value : this.conversationId,
        type: type ?? this.type,
        detail: detail ?? this.detail,
        decision: decision.present ? decision.value : this.decision,
        risk: risk.present ? risk.value : this.risk,
        createdAt: createdAt ?? this.createdAt,
      );
  AuditLog copyWithCompanion(AuditLogsCompanion data) {
    return AuditLog(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      type: data.type.present ? data.type.value : this.type,
      detail: data.detail.present ? data.detail.value : this.detail,
      decision: data.decision.present ? data.decision.value : this.decision,
      risk: data.risk.present ? data.risk.value : this.risk,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AuditLog(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('type: $type, ')
          ..write('detail: $detail, ')
          ..write('decision: $decision, ')
          ..write('risk: $risk, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, conversationId, type, detail, decision, risk, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuditLog &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.type == this.type &&
          other.detail == this.detail &&
          other.decision == this.decision &&
          other.risk == this.risk &&
          other.createdAt == this.createdAt);
}

class AuditLogsCompanion extends UpdateCompanion<AuditLog> {
  final Value<String> id;
  final Value<String?> conversationId;
  final Value<String> type;
  final Value<String> detail;
  final Value<String?> decision;
  final Value<String?> risk;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const AuditLogsCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.type = const Value.absent(),
    this.detail = const Value.absent(),
    this.decision = const Value.absent(),
    this.risk = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AuditLogsCompanion.insert({
    required String id,
    this.conversationId = const Value.absent(),
    required String type,
    required String detail,
    this.decision = const Value.absent(),
    this.risk = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        type = Value(type),
        detail = Value(detail),
        createdAt = Value(createdAt);
  static Insertable<AuditLog> custom({
    Expression<String>? id,
    Expression<String>? conversationId,
    Expression<String>? type,
    Expression<String>? detail,
    Expression<String>? decision,
    Expression<String>? risk,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (type != null) 'type': type,
      if (detail != null) 'detail': detail,
      if (decision != null) 'decision': decision,
      if (risk != null) 'risk': risk,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AuditLogsCompanion copyWith(
      {Value<String>? id,
      Value<String?>? conversationId,
      Value<String>? type,
      Value<String>? detail,
      Value<String?>? decision,
      Value<String?>? risk,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return AuditLogsCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      type: type ?? this.type,
      detail: detail ?? this.detail,
      decision: decision ?? this.decision,
      risk: risk ?? this.risk,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (detail.present) {
      map['detail'] = Variable<String>(detail.value);
    }
    if (decision.present) {
      map['decision'] = Variable<String>(decision.value);
    }
    if (risk.present) {
      map['risk'] = Variable<String>(risk.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AuditLogsCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('type: $type, ')
          ..write('detail: $detail, ')
          ..write('decision: $decision, ')
          ..write('risk: $risk, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PluginsTable extends Plugins with TableInfo<$PluginsTable, Plugin> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PluginsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _manifestJsonMeta =
      const VerificationMeta('manifestJson');
  @override
  late final GeneratedColumn<String> manifestJson = GeneratedColumn<String>(
      'manifest_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
      'version', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('1.0.0'));
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, kind, manifestJson, version, enabled, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plugins';
  @override
  VerificationContext validateIntegrity(Insertable<Plugin> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('manifest_json')) {
      context.handle(
          _manifestJsonMeta,
          manifestJson.isAcceptableOrUnknown(
              data['manifest_json']!, _manifestJsonMeta));
    } else if (isInserting) {
      context.missing(_manifestJsonMeta);
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Plugin map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Plugin(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      manifestJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}manifest_json'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}version'])!,
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $PluginsTable createAlias(String alias) {
    return $PluginsTable(attachedDatabase, alias);
  }
}

class Plugin extends DataClass implements Insertable<Plugin> {
  final String id;
  final String name;
  final String kind;
  final String manifestJson;
  final String version;
  final bool enabled;
  final DateTime createdAt;
  const Plugin(
      {required this.id,
      required this.name,
      required this.kind,
      required this.manifestJson,
      required this.version,
      required this.enabled,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['kind'] = Variable<String>(kind);
    map['manifest_json'] = Variable<String>(manifestJson);
    map['version'] = Variable<String>(version);
    map['enabled'] = Variable<bool>(enabled);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PluginsCompanion toCompanion(bool nullToAbsent) {
    return PluginsCompanion(
      id: Value(id),
      name: Value(name),
      kind: Value(kind),
      manifestJson: Value(manifestJson),
      version: Value(version),
      enabled: Value(enabled),
      createdAt: Value(createdAt),
    );
  }

  factory Plugin.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Plugin(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      kind: serializer.fromJson<String>(json['kind']),
      manifestJson: serializer.fromJson<String>(json['manifestJson']),
      version: serializer.fromJson<String>(json['version']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<String>(kind),
      'manifestJson': serializer.toJson<String>(manifestJson),
      'version': serializer.toJson<String>(version),
      'enabled': serializer.toJson<bool>(enabled),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Plugin copyWith(
          {String? id,
          String? name,
          String? kind,
          String? manifestJson,
          String? version,
          bool? enabled,
          DateTime? createdAt}) =>
      Plugin(
        id: id ?? this.id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        manifestJson: manifestJson ?? this.manifestJson,
        version: version ?? this.version,
        enabled: enabled ?? this.enabled,
        createdAt: createdAt ?? this.createdAt,
      );
  Plugin copyWithCompanion(PluginsCompanion data) {
    return Plugin(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      manifestJson: data.manifestJson.present
          ? data.manifestJson.value
          : this.manifestJson,
      version: data.version.present ? data.version.value : this.version,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Plugin(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('manifestJson: $manifestJson, ')
          ..write('version: $version, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, kind, manifestJson, version, enabled, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Plugin &&
          other.id == this.id &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.manifestJson == this.manifestJson &&
          other.version == this.version &&
          other.enabled == this.enabled &&
          other.createdAt == this.createdAt);
}

class PluginsCompanion extends UpdateCompanion<Plugin> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> kind;
  final Value<String> manifestJson;
  final Value<String> version;
  final Value<bool> enabled;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const PluginsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.manifestJson = const Value.absent(),
    this.version = const Value.absent(),
    this.enabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PluginsCompanion.insert({
    required String id,
    required String name,
    required String kind,
    required String manifestJson,
    this.version = const Value.absent(),
    this.enabled = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        kind = Value(kind),
        manifestJson = Value(manifestJson),
        createdAt = Value(createdAt);
  static Insertable<Plugin> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<String>? manifestJson,
    Expression<String>? version,
    Expression<bool>? enabled,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (manifestJson != null) 'manifest_json': manifestJson,
      if (version != null) 'version': version,
      if (enabled != null) 'enabled': enabled,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PluginsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? kind,
      Value<String>? manifestJson,
      Value<String>? version,
      Value<bool>? enabled,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return PluginsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      manifestJson: manifestJson ?? this.manifestJson,
      version: version ?? this.version,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (manifestJson.present) {
      map['manifest_json'] = Variable<String>(manifestJson.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PluginsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('manifestJson: $manifestJson, ')
          ..write('version: $version, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SkillPacksTable extends SkillPacks
    with TableInfo<$SkillPacksTable, SkillPack> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SkillPacksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
      'author', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
      'version', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('0.0.1'));
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
      'source', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _repoMeta = const VerificationMeta('repo');
  @override
  late final GeneratedColumn<String> repo = GeneratedColumn<String>(
      'repo', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _refMeta = const VerificationMeta('ref');
  @override
  late final GeneratedColumn<String> ref = GeneratedColumn<String>(
      'ref', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _subPathMeta =
      const VerificationMeta('subPath');
  @override
  late final GeneratedColumn<String> subPath = GeneratedColumn<String>(
      'sub_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _installRootMeta =
      const VerificationMeta('installRoot');
  @override
  late final GeneratedColumn<String> installRoot = GeneratedColumn<String>(
      'install_root', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fileListJsonMeta =
      const VerificationMeta('fileListJson');
  @override
  late final GeneratedColumn<String> fileListJson = GeneratedColumn<String>(
      'file_list_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _installedAtMeta =
      const VerificationMeta('installedAt');
  @override
  late final GeneratedColumn<DateTime> installedAt = GeneratedColumn<DateTime>(
      'installed_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
      'sha256', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        description,
        author,
        version,
        source,
        repo,
        ref,
        subPath,
        installRoot,
        fileListJson,
        enabled,
        installedAt,
        updatedAt,
        sha256
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'skill_packs';
  @override
  VerificationContext validateIntegrity(Insertable<SkillPack> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('author')) {
      context.handle(_authorMeta,
          author.isAcceptableOrUnknown(data['author']!, _authorMeta));
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    }
    if (data.containsKey('source')) {
      context.handle(_sourceMeta,
          source.isAcceptableOrUnknown(data['source']!, _sourceMeta));
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('repo')) {
      context.handle(
          _repoMeta, repo.isAcceptableOrUnknown(data['repo']!, _repoMeta));
    } else if (isInserting) {
      context.missing(_repoMeta);
    }
    if (data.containsKey('ref')) {
      context.handle(
          _refMeta, ref.isAcceptableOrUnknown(data['ref']!, _refMeta));
    } else if (isInserting) {
      context.missing(_refMeta);
    }
    if (data.containsKey('sub_path')) {
      context.handle(_subPathMeta,
          subPath.isAcceptableOrUnknown(data['sub_path']!, _subPathMeta));
    }
    if (data.containsKey('install_root')) {
      context.handle(
          _installRootMeta,
          installRoot.isAcceptableOrUnknown(
              data['install_root']!, _installRootMeta));
    } else if (isInserting) {
      context.missing(_installRootMeta);
    }
    if (data.containsKey('file_list_json')) {
      context.handle(
          _fileListJsonMeta,
          fileListJson.isAcceptableOrUnknown(
              data['file_list_json']!, _fileListJsonMeta));
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    }
    if (data.containsKey('installed_at')) {
      context.handle(
          _installedAtMeta,
          installedAt.isAcceptableOrUnknown(
              data['installed_at']!, _installedAtMeta));
    } else if (isInserting) {
      context.missing(_installedAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(_sha256Meta,
          sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta));
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SkillPack map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SkillPack(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      author: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}author']),
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}version'])!,
      source: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source'])!,
      repo: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}repo'])!,
      ref: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}ref'])!,
      subPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sub_path']),
      installRoot: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}install_root'])!,
      fileListJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_list_json'])!,
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
      installedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}installed_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      sha256: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sha256'])!,
    );
  }

  @override
  $SkillPacksTable createAlias(String alias) {
    return $SkillPacksTable(attachedDatabase, alias);
  }
}

class SkillPack extends DataClass implements Insertable<SkillPack> {
  final String id;
  final String name;
  final String description;
  final String? author;
  final String version;
  final String source;
  final String repo;
  final String ref;
  final String? subPath;
  final String installRoot;
  final String fileListJson;
  final bool enabled;
  final DateTime installedAt;
  final DateTime updatedAt;
  final String sha256;
  const SkillPack(
      {required this.id,
      required this.name,
      required this.description,
      this.author,
      required this.version,
      required this.source,
      required this.repo,
      required this.ref,
      this.subPath,
      required this.installRoot,
      required this.fileListJson,
      required this.enabled,
      required this.installedAt,
      required this.updatedAt,
      required this.sha256});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['description'] = Variable<String>(description);
    if (!nullToAbsent || author != null) {
      map['author'] = Variable<String>(author);
    }
    map['version'] = Variable<String>(version);
    map['source'] = Variable<String>(source);
    map['repo'] = Variable<String>(repo);
    map['ref'] = Variable<String>(ref);
    if (!nullToAbsent || subPath != null) {
      map['sub_path'] = Variable<String>(subPath);
    }
    map['install_root'] = Variable<String>(installRoot);
    map['file_list_json'] = Variable<String>(fileListJson);
    map['enabled'] = Variable<bool>(enabled);
    map['installed_at'] = Variable<DateTime>(installedAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['sha256'] = Variable<String>(sha256);
    return map;
  }

  SkillPacksCompanion toCompanion(bool nullToAbsent) {
    return SkillPacksCompanion(
      id: Value(id),
      name: Value(name),
      description: Value(description),
      author:
          author == null && nullToAbsent ? const Value.absent() : Value(author),
      version: Value(version),
      source: Value(source),
      repo: Value(repo),
      ref: Value(ref),
      subPath: subPath == null && nullToAbsent
          ? const Value.absent()
          : Value(subPath),
      installRoot: Value(installRoot),
      fileListJson: Value(fileListJson),
      enabled: Value(enabled),
      installedAt: Value(installedAt),
      updatedAt: Value(updatedAt),
      sha256: Value(sha256),
    );
  }

  factory SkillPack.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SkillPack(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String>(json['description']),
      author: serializer.fromJson<String?>(json['author']),
      version: serializer.fromJson<String>(json['version']),
      source: serializer.fromJson<String>(json['source']),
      repo: serializer.fromJson<String>(json['repo']),
      ref: serializer.fromJson<String>(json['ref']),
      subPath: serializer.fromJson<String?>(json['subPath']),
      installRoot: serializer.fromJson<String>(json['installRoot']),
      fileListJson: serializer.fromJson<String>(json['fileListJson']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      installedAt: serializer.fromJson<DateTime>(json['installedAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      sha256: serializer.fromJson<String>(json['sha256']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String>(description),
      'author': serializer.toJson<String?>(author),
      'version': serializer.toJson<String>(version),
      'source': serializer.toJson<String>(source),
      'repo': serializer.toJson<String>(repo),
      'ref': serializer.toJson<String>(ref),
      'subPath': serializer.toJson<String?>(subPath),
      'installRoot': serializer.toJson<String>(installRoot),
      'fileListJson': serializer.toJson<String>(fileListJson),
      'enabled': serializer.toJson<bool>(enabled),
      'installedAt': serializer.toJson<DateTime>(installedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'sha256': serializer.toJson<String>(sha256),
    };
  }

  SkillPack copyWith(
          {String? id,
          String? name,
          String? description,
          Value<String?> author = const Value.absent(),
          String? version,
          String? source,
          String? repo,
          String? ref,
          Value<String?> subPath = const Value.absent(),
          String? installRoot,
          String? fileListJson,
          bool? enabled,
          DateTime? installedAt,
          DateTime? updatedAt,
          String? sha256}) =>
      SkillPack(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        author: author.present ? author.value : this.author,
        version: version ?? this.version,
        source: source ?? this.source,
        repo: repo ?? this.repo,
        ref: ref ?? this.ref,
        subPath: subPath.present ? subPath.value : this.subPath,
        installRoot: installRoot ?? this.installRoot,
        fileListJson: fileListJson ?? this.fileListJson,
        enabled: enabled ?? this.enabled,
        installedAt: installedAt ?? this.installedAt,
        updatedAt: updatedAt ?? this.updatedAt,
        sha256: sha256 ?? this.sha256,
      );
  SkillPack copyWithCompanion(SkillPacksCompanion data) {
    return SkillPack(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description:
          data.description.present ? data.description.value : this.description,
      author: data.author.present ? data.author.value : this.author,
      version: data.version.present ? data.version.value : this.version,
      source: data.source.present ? data.source.value : this.source,
      repo: data.repo.present ? data.repo.value : this.repo,
      ref: data.ref.present ? data.ref.value : this.ref,
      subPath: data.subPath.present ? data.subPath.value : this.subPath,
      installRoot:
          data.installRoot.present ? data.installRoot.value : this.installRoot,
      fileListJson: data.fileListJson.present
          ? data.fileListJson.value
          : this.fileListJson,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      installedAt:
          data.installedAt.present ? data.installedAt.value : this.installedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SkillPack(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('author: $author, ')
          ..write('version: $version, ')
          ..write('source: $source, ')
          ..write('repo: $repo, ')
          ..write('ref: $ref, ')
          ..write('subPath: $subPath, ')
          ..write('installRoot: $installRoot, ')
          ..write('fileListJson: $fileListJson, ')
          ..write('enabled: $enabled, ')
          ..write('installedAt: $installedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sha256: $sha256')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      name,
      description,
      author,
      version,
      source,
      repo,
      ref,
      subPath,
      installRoot,
      fileListJson,
      enabled,
      installedAt,
      updatedAt,
      sha256);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SkillPack &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.author == this.author &&
          other.version == this.version &&
          other.source == this.source &&
          other.repo == this.repo &&
          other.ref == this.ref &&
          other.subPath == this.subPath &&
          other.installRoot == this.installRoot &&
          other.fileListJson == this.fileListJson &&
          other.enabled == this.enabled &&
          other.installedAt == this.installedAt &&
          other.updatedAt == this.updatedAt &&
          other.sha256 == this.sha256);
}

class SkillPacksCompanion extends UpdateCompanion<SkillPack> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> description;
  final Value<String?> author;
  final Value<String> version;
  final Value<String> source;
  final Value<String> repo;
  final Value<String> ref;
  final Value<String?> subPath;
  final Value<String> installRoot;
  final Value<String> fileListJson;
  final Value<bool> enabled;
  final Value<DateTime> installedAt;
  final Value<DateTime> updatedAt;
  final Value<String> sha256;
  final Value<int> rowid;
  const SkillPacksCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.author = const Value.absent(),
    this.version = const Value.absent(),
    this.source = const Value.absent(),
    this.repo = const Value.absent(),
    this.ref = const Value.absent(),
    this.subPath = const Value.absent(),
    this.installRoot = const Value.absent(),
    this.fileListJson = const Value.absent(),
    this.enabled = const Value.absent(),
    this.installedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SkillPacksCompanion.insert({
    required String id,
    required String name,
    required String description,
    this.author = const Value.absent(),
    this.version = const Value.absent(),
    required String source,
    required String repo,
    required String ref,
    this.subPath = const Value.absent(),
    required String installRoot,
    this.fileListJson = const Value.absent(),
    this.enabled = const Value.absent(),
    required DateTime installedAt,
    required DateTime updatedAt,
    required String sha256,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        description = Value(description),
        source = Value(source),
        repo = Value(repo),
        ref = Value(ref),
        installRoot = Value(installRoot),
        installedAt = Value(installedAt),
        updatedAt = Value(updatedAt),
        sha256 = Value(sha256);
  static Insertable<SkillPack> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? author,
    Expression<String>? version,
    Expression<String>? source,
    Expression<String>? repo,
    Expression<String>? ref,
    Expression<String>? subPath,
    Expression<String>? installRoot,
    Expression<String>? fileListJson,
    Expression<bool>? enabled,
    Expression<DateTime>? installedAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? sha256,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (author != null) 'author': author,
      if (version != null) 'version': version,
      if (source != null) 'source': source,
      if (repo != null) 'repo': repo,
      if (ref != null) 'ref': ref,
      if (subPath != null) 'sub_path': subPath,
      if (installRoot != null) 'install_root': installRoot,
      if (fileListJson != null) 'file_list_json': fileListJson,
      if (enabled != null) 'enabled': enabled,
      if (installedAt != null) 'installed_at': installedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (sha256 != null) 'sha256': sha256,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SkillPacksCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? description,
      Value<String?>? author,
      Value<String>? version,
      Value<String>? source,
      Value<String>? repo,
      Value<String>? ref,
      Value<String?>? subPath,
      Value<String>? installRoot,
      Value<String>? fileListJson,
      Value<bool>? enabled,
      Value<DateTime>? installedAt,
      Value<DateTime>? updatedAt,
      Value<String>? sha256,
      Value<int>? rowid}) {
    return SkillPacksCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      author: author ?? this.author,
      version: version ?? this.version,
      source: source ?? this.source,
      repo: repo ?? this.repo,
      ref: ref ?? this.ref,
      subPath: subPath ?? this.subPath,
      installRoot: installRoot ?? this.installRoot,
      fileListJson: fileListJson ?? this.fileListJson,
      enabled: enabled ?? this.enabled,
      installedAt: installedAt ?? this.installedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sha256: sha256 ?? this.sha256,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (repo.present) {
      map['repo'] = Variable<String>(repo.value);
    }
    if (ref.present) {
      map['ref'] = Variable<String>(ref.value);
    }
    if (subPath.present) {
      map['sub_path'] = Variable<String>(subPath.value);
    }
    if (installRoot.present) {
      map['install_root'] = Variable<String>(installRoot.value);
    }
    if (fileListJson.present) {
      map['file_list_json'] = Variable<String>(fileListJson.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (installedAt.present) {
      map['installed_at'] = Variable<DateTime>(installedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SkillPacksCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('author: $author, ')
          ..write('version: $version, ')
          ..write('source: $source, ')
          ..write('repo: $repo, ')
          ..write('ref: $ref, ')
          ..write('subPath: $subPath, ')
          ..write('installRoot: $installRoot, ')
          ..write('fileListJson: $fileListJson, ')
          ..write('enabled: $enabled, ')
          ..write('installedAt: $installedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sha256: $sha256, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $McpServersTable extends McpServers
    with TableInfo<$McpServersTable, McpServer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $McpServersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
      'url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _commandMeta =
      const VerificationMeta('command');
  @override
  late final GeneratedColumn<String> command = GeneratedColumn<String>(
      'command', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _argsMeta = const VerificationMeta('args');
  @override
  late final GeneratedColumn<String> args = GeneratedColumn<String>(
      'args', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, kind, url, command, args, enabled];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mcp_servers';
  @override
  VerificationContext validateIntegrity(Insertable<McpServer> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
          _urlMeta, url.isAcceptableOrUnknown(data['url']!, _urlMeta));
    }
    if (data.containsKey('command')) {
      context.handle(_commandMeta,
          command.isAcceptableOrUnknown(data['command']!, _commandMeta));
    }
    if (data.containsKey('args')) {
      context.handle(
          _argsMeta, args.isAcceptableOrUnknown(data['args']!, _argsMeta));
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  McpServer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return McpServer(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      url: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}url']),
      command: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}command']),
      args: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}args'])!,
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
    );
  }

  @override
  $McpServersTable createAlias(String alias) {
    return $McpServersTable(attachedDatabase, alias);
  }
}

class McpServer extends DataClass implements Insertable<McpServer> {
  final String id;
  final String name;
  final String kind;
  final String? url;
  final String? command;
  final String args;
  final bool enabled;
  const McpServer(
      {required this.id,
      required this.name,
      required this.kind,
      this.url,
      this.command,
      required this.args,
      required this.enabled});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || url != null) {
      map['url'] = Variable<String>(url);
    }
    if (!nullToAbsent || command != null) {
      map['command'] = Variable<String>(command);
    }
    map['args'] = Variable<String>(args);
    map['enabled'] = Variable<bool>(enabled);
    return map;
  }

  McpServersCompanion toCompanion(bool nullToAbsent) {
    return McpServersCompanion(
      id: Value(id),
      name: Value(name),
      kind: Value(kind),
      url: url == null && nullToAbsent ? const Value.absent() : Value(url),
      command: command == null && nullToAbsent
          ? const Value.absent()
          : Value(command),
      args: Value(args),
      enabled: Value(enabled),
    );
  }

  factory McpServer.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return McpServer(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      kind: serializer.fromJson<String>(json['kind']),
      url: serializer.fromJson<String?>(json['url']),
      command: serializer.fromJson<String?>(json['command']),
      args: serializer.fromJson<String>(json['args']),
      enabled: serializer.fromJson<bool>(json['enabled']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<String>(kind),
      'url': serializer.toJson<String?>(url),
      'command': serializer.toJson<String?>(command),
      'args': serializer.toJson<String>(args),
      'enabled': serializer.toJson<bool>(enabled),
    };
  }

  McpServer copyWith(
          {String? id,
          String? name,
          String? kind,
          Value<String?> url = const Value.absent(),
          Value<String?> command = const Value.absent(),
          String? args,
          bool? enabled}) =>
      McpServer(
        id: id ?? this.id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        url: url.present ? url.value : this.url,
        command: command.present ? command.value : this.command,
        args: args ?? this.args,
        enabled: enabled ?? this.enabled,
      );
  McpServer copyWithCompanion(McpServersCompanion data) {
    return McpServer(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      url: data.url.present ? data.url.value : this.url,
      command: data.command.present ? data.command.value : this.command,
      args: data.args.present ? data.args.value : this.args,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
    );
  }

  @override
  String toString() {
    return (StringBuffer('McpServer(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('url: $url, ')
          ..write('command: $command, ')
          ..write('args: $args, ')
          ..write('enabled: $enabled')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, kind, url, command, args, enabled);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is McpServer &&
          other.id == this.id &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.url == this.url &&
          other.command == this.command &&
          other.args == this.args &&
          other.enabled == this.enabled);
}

class McpServersCompanion extends UpdateCompanion<McpServer> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> kind;
  final Value<String?> url;
  final Value<String?> command;
  final Value<String> args;
  final Value<bool> enabled;
  final Value<int> rowid;
  const McpServersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.url = const Value.absent(),
    this.command = const Value.absent(),
    this.args = const Value.absent(),
    this.enabled = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  McpServersCompanion.insert({
    required String id,
    required String name,
    required String kind,
    this.url = const Value.absent(),
    this.command = const Value.absent(),
    this.args = const Value.absent(),
    this.enabled = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        kind = Value(kind);
  static Insertable<McpServer> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<String>? url,
    Expression<String>? command,
    Expression<String>? args,
    Expression<bool>? enabled,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (url != null) 'url': url,
      if (command != null) 'command': command,
      if (args != null) 'args': args,
      if (enabled != null) 'enabled': enabled,
      if (rowid != null) 'rowid': rowid,
    });
  }

  McpServersCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? kind,
      Value<String?>? url,
      Value<String?>? command,
      Value<String>? args,
      Value<bool>? enabled,
      Value<int>? rowid}) {
    return McpServersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      url: url ?? this.url,
      command: command ?? this.command,
      args: args ?? this.args,
      enabled: enabled ?? this.enabled,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (command.present) {
      map['command'] = Variable<String>(command.value);
    }
    if (args.present) {
      map['args'] = Variable<String>(args.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('McpServersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('url: $url, ')
          ..write('command: $command, ')
          ..write('args: $args, ')
          ..write('enabled: $enabled, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AccountMetaTable extends AccountMeta
    with TableInfo<$AccountMetaTable, AccountMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isProMeta = const VerificationMeta('isPro');
  @override
  late final GeneratedColumn<bool> isPro = GeneratedColumn<bool>(
      'is_pro', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_pro" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _balanceCentsMeta =
      const VerificationMeta('balanceCents');
  @override
  late final GeneratedColumn<String> balanceCents = GeneratedColumn<String>(
      'balance_cents', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('0'));
  static const VerificationMeta _configJsonMeta =
      const VerificationMeta('configJson');
  @override
  late final GeneratedColumn<String> configJson = GeneratedColumn<String>(
      'config_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('{}'));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, userId, isPro, balanceCents, configJson, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'account_meta';
  @override
  VerificationContext validateIntegrity(Insertable<AccountMetaData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    }
    if (data.containsKey('is_pro')) {
      context.handle(
          _isProMeta, isPro.isAcceptableOrUnknown(data['is_pro']!, _isProMeta));
    }
    if (data.containsKey('balance_cents')) {
      context.handle(
          _balanceCentsMeta,
          balanceCents.isAcceptableOrUnknown(
              data['balance_cents']!, _balanceCentsMeta));
    }
    if (data.containsKey('config_json')) {
      context.handle(
          _configJsonMeta,
          configJson.isAcceptableOrUnknown(
              data['config_json']!, _configJsonMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AccountMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AccountMetaData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id']),
      isPro: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_pro'])!,
      balanceCents: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}balance_cents'])!,
      configJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}config_json'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $AccountMetaTable createAlias(String alias) {
    return $AccountMetaTable(attachedDatabase, alias);
  }
}

class AccountMetaData extends DataClass implements Insertable<AccountMetaData> {
  final String id;
  final String? userId;
  final bool isPro;
  final String balanceCents;
  final String configJson;
  final DateTime updatedAt;
  const AccountMetaData(
      {required this.id,
      this.userId,
      required this.isPro,
      required this.balanceCents,
      required this.configJson,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    map['is_pro'] = Variable<bool>(isPro);
    map['balance_cents'] = Variable<String>(balanceCents);
    map['config_json'] = Variable<String>(configJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AccountMetaCompanion toCompanion(bool nullToAbsent) {
    return AccountMetaCompanion(
      id: Value(id),
      userId:
          userId == null && nullToAbsent ? const Value.absent() : Value(userId),
      isPro: Value(isPro),
      balanceCents: Value(balanceCents),
      configJson: Value(configJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory AccountMetaData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AccountMetaData(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String?>(json['userId']),
      isPro: serializer.fromJson<bool>(json['isPro']),
      balanceCents: serializer.fromJson<String>(json['balanceCents']),
      configJson: serializer.fromJson<String>(json['configJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String?>(userId),
      'isPro': serializer.toJson<bool>(isPro),
      'balanceCents': serializer.toJson<String>(balanceCents),
      'configJson': serializer.toJson<String>(configJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AccountMetaData copyWith(
          {String? id,
          Value<String?> userId = const Value.absent(),
          bool? isPro,
          String? balanceCents,
          String? configJson,
          DateTime? updatedAt}) =>
      AccountMetaData(
        id: id ?? this.id,
        userId: userId.present ? userId.value : this.userId,
        isPro: isPro ?? this.isPro,
        balanceCents: balanceCents ?? this.balanceCents,
        configJson: configJson ?? this.configJson,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  AccountMetaData copyWithCompanion(AccountMetaCompanion data) {
    return AccountMetaData(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      isPro: data.isPro.present ? data.isPro.value : this.isPro,
      balanceCents: data.balanceCents.present
          ? data.balanceCents.value
          : this.balanceCents,
      configJson:
          data.configJson.present ? data.configJson.value : this.configJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AccountMetaData(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('isPro: $isPro, ')
          ..write('balanceCents: $balanceCents, ')
          ..write('configJson: $configJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, userId, isPro, balanceCents, configJson, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountMetaData &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.isPro == this.isPro &&
          other.balanceCents == this.balanceCents &&
          other.configJson == this.configJson &&
          other.updatedAt == this.updatedAt);
}

class AccountMetaCompanion extends UpdateCompanion<AccountMetaData> {
  final Value<String> id;
  final Value<String?> userId;
  final Value<bool> isPro;
  final Value<String> balanceCents;
  final Value<String> configJson;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AccountMetaCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.isPro = const Value.absent(),
    this.balanceCents = const Value.absent(),
    this.configJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AccountMetaCompanion.insert({
    required String id,
    this.userId = const Value.absent(),
    this.isPro = const Value.absent(),
    this.balanceCents = const Value.absent(),
    this.configJson = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        updatedAt = Value(updatedAt);
  static Insertable<AccountMetaData> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<bool>? isPro,
    Expression<String>? balanceCents,
    Expression<String>? configJson,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (isPro != null) 'is_pro': isPro,
      if (balanceCents != null) 'balance_cents': balanceCents,
      if (configJson != null) 'config_json': configJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AccountMetaCompanion copyWith(
      {Value<String>? id,
      Value<String?>? userId,
      Value<bool>? isPro,
      Value<String>? balanceCents,
      Value<String>? configJson,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return AccountMetaCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      isPro: isPro ?? this.isPro,
      balanceCents: balanceCents ?? this.balanceCents,
      configJson: configJson ?? this.configJson,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (isPro.present) {
      map['is_pro'] = Variable<bool>(isPro.value);
    }
    if (balanceCents.present) {
      map['balance_cents'] = Variable<String>(balanceCents.value);
    }
    if (configJson.present) {
      map['config_json'] = Variable<String>(configJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountMetaCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('isPro: $isPro, ')
          ..write('balanceCents: $balanceCents, ')
          ..write('configJson: $configJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RunRecordsTable extends RunRecords
    with TableInfo<$RunRecordsTable, RunRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RunRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  @override
  late final GeneratedColumn<String> runId = GeneratedColumn<String>(
      'run_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _conversationIdMeta =
      const VerificationMeta('conversationId');
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
      'conversation_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
      'model', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('unknown'));
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('running'));
  static const VerificationMeta _startedAtMeta =
      const VerificationMeta('startedAt');
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
      'started_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _endedAtMeta =
      const VerificationMeta('endedAt');
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
      'ended_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _inputTokensMeta =
      const VerificationMeta('inputTokens');
  @override
  late final GeneratedColumn<int> inputTokens = GeneratedColumn<int>(
      'input_tokens', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _outputTokensMeta =
      const VerificationMeta('outputTokens');
  @override
  late final GeneratedColumn<int> outputTokens = GeneratedColumn<int>(
      'output_tokens', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _cachedTokensMeta =
      const VerificationMeta('cachedTokens');
  @override
  late final GeneratedColumn<int> cachedTokens = GeneratedColumn<int>(
      'cached_tokens', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _estimatedCostCentsMeta =
      const VerificationMeta('estimatedCostCents');
  @override
  late final GeneratedColumn<int> estimatedCostCents = GeneratedColumn<int>(
      'estimated_cost_cents', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _eventCountMeta =
      const VerificationMeta('eventCount');
  @override
  late final GeneratedColumn<int> eventCount = GeneratedColumn<int>(
      'event_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _totalDurationMsMeta =
      const VerificationMeta('totalDurationMs');
  @override
  late final GeneratedColumn<int> totalDurationMs = GeneratedColumn<int>(
      'total_duration_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _retryCountMeta =
      const VerificationMeta('retryCount');
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
      'retry_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _firstTokenDurationMsMeta =
      const VerificationMeta('firstTokenDurationMs');
  @override
  late final GeneratedColumn<int> firstTokenDurationMs = GeneratedColumn<int>(
      'first_token_duration_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        runId,
        conversationId,
        model,
        status,
        startedAt,
        endedAt,
        inputTokens,
        outputTokens,
        cachedTokens,
        estimatedCostCents,
        eventCount,
        totalDurationMs,
        retryCount,
        firstTokenDurationMs
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'run_records';
  @override
  VerificationContext validateIntegrity(Insertable<RunRecord> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('run_id')) {
      context.handle(
          _runIdMeta, runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta));
    } else if (isInserting) {
      context.missing(_runIdMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
          _conversationIdMeta,
          conversationId.isAcceptableOrUnknown(
              data['conversation_id']!, _conversationIdMeta));
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
          _modelMeta, model.isAcceptableOrUnknown(data['model']!, _modelMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('started_at')) {
      context.handle(_startedAtMeta,
          startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta));
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(_endedAtMeta,
          endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta));
    }
    if (data.containsKey('input_tokens')) {
      context.handle(
          _inputTokensMeta,
          inputTokens.isAcceptableOrUnknown(
              data['input_tokens']!, _inputTokensMeta));
    }
    if (data.containsKey('output_tokens')) {
      context.handle(
          _outputTokensMeta,
          outputTokens.isAcceptableOrUnknown(
              data['output_tokens']!, _outputTokensMeta));
    }
    if (data.containsKey('cached_tokens')) {
      context.handle(
          _cachedTokensMeta,
          cachedTokens.isAcceptableOrUnknown(
              data['cached_tokens']!, _cachedTokensMeta));
    }
    if (data.containsKey('estimated_cost_cents')) {
      context.handle(
          _estimatedCostCentsMeta,
          estimatedCostCents.isAcceptableOrUnknown(
              data['estimated_cost_cents']!, _estimatedCostCentsMeta));
    }
    if (data.containsKey('event_count')) {
      context.handle(
          _eventCountMeta,
          eventCount.isAcceptableOrUnknown(
              data['event_count']!, _eventCountMeta));
    }
    if (data.containsKey('total_duration_ms')) {
      context.handle(
          _totalDurationMsMeta,
          totalDurationMs.isAcceptableOrUnknown(
              data['total_duration_ms']!, _totalDurationMsMeta));
    }
    if (data.containsKey('retry_count')) {
      context.handle(
          _retryCountMeta,
          retryCount.isAcceptableOrUnknown(
              data['retry_count']!, _retryCountMeta));
    }
    if (data.containsKey('first_token_duration_ms')) {
      context.handle(
          _firstTokenDurationMsMeta,
          firstTokenDurationMs.isAcceptableOrUnknown(
              data['first_token_duration_ms']!, _firstTokenDurationMsMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {runId};
  @override
  RunRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RunRecord(
      runId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}run_id'])!,
      conversationId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}conversation_id'])!,
      model: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}model'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      startedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}started_at'])!,
      endedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}ended_at']),
      inputTokens: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}input_tokens'])!,
      outputTokens: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}output_tokens'])!,
      cachedTokens: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}cached_tokens'])!,
      estimatedCostCents: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}estimated_cost_cents']),
      eventCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}event_count'])!,
      totalDurationMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}total_duration_ms']),
      retryCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}retry_count'])!,
      firstTokenDurationMs: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}first_token_duration_ms']),
    );
  }

  @override
  $RunRecordsTable createAlias(String alias) {
    return $RunRecordsTable(attachedDatabase, alias);
  }
}

class RunRecord extends DataClass implements Insertable<RunRecord> {
  final String runId;
  final String conversationId;
  final String model;
  final String status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int inputTokens;
  final int outputTokens;
  final int cachedTokens;
  final int? estimatedCostCents;
  final int eventCount;
  final int? totalDurationMs;
  final int retryCount;
  final int? firstTokenDurationMs;
  const RunRecord(
      {required this.runId,
      required this.conversationId,
      required this.model,
      required this.status,
      required this.startedAt,
      this.endedAt,
      required this.inputTokens,
      required this.outputTokens,
      required this.cachedTokens,
      this.estimatedCostCents,
      required this.eventCount,
      this.totalDurationMs,
      required this.retryCount,
      this.firstTokenDurationMs});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['run_id'] = Variable<String>(runId);
    map['conversation_id'] = Variable<String>(conversationId);
    map['model'] = Variable<String>(model);
    map['status'] = Variable<String>(status);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<DateTime>(endedAt);
    }
    map['input_tokens'] = Variable<int>(inputTokens);
    map['output_tokens'] = Variable<int>(outputTokens);
    map['cached_tokens'] = Variable<int>(cachedTokens);
    if (!nullToAbsent || estimatedCostCents != null) {
      map['estimated_cost_cents'] = Variable<int>(estimatedCostCents);
    }
    map['event_count'] = Variable<int>(eventCount);
    if (!nullToAbsent || totalDurationMs != null) {
      map['total_duration_ms'] = Variable<int>(totalDurationMs);
    }
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || firstTokenDurationMs != null) {
      map['first_token_duration_ms'] = Variable<int>(firstTokenDurationMs);
    }
    return map;
  }

  RunRecordsCompanion toCompanion(bool nullToAbsent) {
    return RunRecordsCompanion(
      runId: Value(runId),
      conversationId: Value(conversationId),
      model: Value(model),
      status: Value(status),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      inputTokens: Value(inputTokens),
      outputTokens: Value(outputTokens),
      cachedTokens: Value(cachedTokens),
      estimatedCostCents: estimatedCostCents == null && nullToAbsent
          ? const Value.absent()
          : Value(estimatedCostCents),
      eventCount: Value(eventCount),
      totalDurationMs: totalDurationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(totalDurationMs),
      retryCount: Value(retryCount),
      firstTokenDurationMs: firstTokenDurationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(firstTokenDurationMs),
    );
  }

  factory RunRecord.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RunRecord(
      runId: serializer.fromJson<String>(json['runId']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      model: serializer.fromJson<String>(json['model']),
      status: serializer.fromJson<String>(json['status']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
      inputTokens: serializer.fromJson<int>(json['inputTokens']),
      outputTokens: serializer.fromJson<int>(json['outputTokens']),
      cachedTokens: serializer.fromJson<int>(json['cachedTokens']),
      estimatedCostCents: serializer.fromJson<int?>(json['estimatedCostCents']),
      eventCount: serializer.fromJson<int>(json['eventCount']),
      totalDurationMs: serializer.fromJson<int?>(json['totalDurationMs']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      firstTokenDurationMs:
          serializer.fromJson<int?>(json['firstTokenDurationMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'runId': serializer.toJson<String>(runId),
      'conversationId': serializer.toJson<String>(conversationId),
      'model': serializer.toJson<String>(model),
      'status': serializer.toJson<String>(status),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
      'inputTokens': serializer.toJson<int>(inputTokens),
      'outputTokens': serializer.toJson<int>(outputTokens),
      'cachedTokens': serializer.toJson<int>(cachedTokens),
      'estimatedCostCents': serializer.toJson<int?>(estimatedCostCents),
      'eventCount': serializer.toJson<int>(eventCount),
      'totalDurationMs': serializer.toJson<int?>(totalDurationMs),
      'retryCount': serializer.toJson<int>(retryCount),
      'firstTokenDurationMs': serializer.toJson<int?>(firstTokenDurationMs),
    };
  }

  RunRecord copyWith(
          {String? runId,
          String? conversationId,
          String? model,
          String? status,
          DateTime? startedAt,
          Value<DateTime?> endedAt = const Value.absent(),
          int? inputTokens,
          int? outputTokens,
          int? cachedTokens,
          Value<int?> estimatedCostCents = const Value.absent(),
          int? eventCount,
          Value<int?> totalDurationMs = const Value.absent(),
          int? retryCount,
          Value<int?> firstTokenDurationMs = const Value.absent()}) =>
      RunRecord(
        runId: runId ?? this.runId,
        conversationId: conversationId ?? this.conversationId,
        model: model ?? this.model,
        status: status ?? this.status,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt.present ? endedAt.value : this.endedAt,
        inputTokens: inputTokens ?? this.inputTokens,
        outputTokens: outputTokens ?? this.outputTokens,
        cachedTokens: cachedTokens ?? this.cachedTokens,
        estimatedCostCents: estimatedCostCents.present
            ? estimatedCostCents.value
            : this.estimatedCostCents,
        eventCount: eventCount ?? this.eventCount,
        totalDurationMs: totalDurationMs.present
            ? totalDurationMs.value
            : this.totalDurationMs,
        retryCount: retryCount ?? this.retryCount,
        firstTokenDurationMs: firstTokenDurationMs.present
            ? firstTokenDurationMs.value
            : this.firstTokenDurationMs,
      );
  RunRecord copyWithCompanion(RunRecordsCompanion data) {
    return RunRecord(
      runId: data.runId.present ? data.runId.value : this.runId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      model: data.model.present ? data.model.value : this.model,
      status: data.status.present ? data.status.value : this.status,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      inputTokens:
          data.inputTokens.present ? data.inputTokens.value : this.inputTokens,
      outputTokens: data.outputTokens.present
          ? data.outputTokens.value
          : this.outputTokens,
      cachedTokens: data.cachedTokens.present
          ? data.cachedTokens.value
          : this.cachedTokens,
      estimatedCostCents: data.estimatedCostCents.present
          ? data.estimatedCostCents.value
          : this.estimatedCostCents,
      eventCount:
          data.eventCount.present ? data.eventCount.value : this.eventCount,
      totalDurationMs: data.totalDurationMs.present
          ? data.totalDurationMs.value
          : this.totalDurationMs,
      retryCount:
          data.retryCount.present ? data.retryCount.value : this.retryCount,
      firstTokenDurationMs: data.firstTokenDurationMs.present
          ? data.firstTokenDurationMs.value
          : this.firstTokenDurationMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RunRecord(')
          ..write('runId: $runId, ')
          ..write('conversationId: $conversationId, ')
          ..write('model: $model, ')
          ..write('status: $status, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('inputTokens: $inputTokens, ')
          ..write('outputTokens: $outputTokens, ')
          ..write('cachedTokens: $cachedTokens, ')
          ..write('estimatedCostCents: $estimatedCostCents, ')
          ..write('eventCount: $eventCount, ')
          ..write('totalDurationMs: $totalDurationMs, ')
          ..write('retryCount: $retryCount, ')
          ..write('firstTokenDurationMs: $firstTokenDurationMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      runId,
      conversationId,
      model,
      status,
      startedAt,
      endedAt,
      inputTokens,
      outputTokens,
      cachedTokens,
      estimatedCostCents,
      eventCount,
      totalDurationMs,
      retryCount,
      firstTokenDurationMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RunRecord &&
          other.runId == this.runId &&
          other.conversationId == this.conversationId &&
          other.model == this.model &&
          other.status == this.status &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.inputTokens == this.inputTokens &&
          other.outputTokens == this.outputTokens &&
          other.cachedTokens == this.cachedTokens &&
          other.estimatedCostCents == this.estimatedCostCents &&
          other.eventCount == this.eventCount &&
          other.totalDurationMs == this.totalDurationMs &&
          other.retryCount == this.retryCount &&
          other.firstTokenDurationMs == this.firstTokenDurationMs);
}

class RunRecordsCompanion extends UpdateCompanion<RunRecord> {
  final Value<String> runId;
  final Value<String> conversationId;
  final Value<String> model;
  final Value<String> status;
  final Value<DateTime> startedAt;
  final Value<DateTime?> endedAt;
  final Value<int> inputTokens;
  final Value<int> outputTokens;
  final Value<int> cachedTokens;
  final Value<int?> estimatedCostCents;
  final Value<int> eventCount;
  final Value<int?> totalDurationMs;
  final Value<int> retryCount;
  final Value<int?> firstTokenDurationMs;
  final Value<int> rowid;
  const RunRecordsCompanion({
    this.runId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.model = const Value.absent(),
    this.status = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.inputTokens = const Value.absent(),
    this.outputTokens = const Value.absent(),
    this.cachedTokens = const Value.absent(),
    this.estimatedCostCents = const Value.absent(),
    this.eventCount = const Value.absent(),
    this.totalDurationMs = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.firstTokenDurationMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RunRecordsCompanion.insert({
    required String runId,
    required String conversationId,
    this.model = const Value.absent(),
    this.status = const Value.absent(),
    required DateTime startedAt,
    this.endedAt = const Value.absent(),
    this.inputTokens = const Value.absent(),
    this.outputTokens = const Value.absent(),
    this.cachedTokens = const Value.absent(),
    this.estimatedCostCents = const Value.absent(),
    this.eventCount = const Value.absent(),
    this.totalDurationMs = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.firstTokenDurationMs = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : runId = Value(runId),
        conversationId = Value(conversationId),
        startedAt = Value(startedAt);
  static Insertable<RunRecord> custom({
    Expression<String>? runId,
    Expression<String>? conversationId,
    Expression<String>? model,
    Expression<String>? status,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endedAt,
    Expression<int>? inputTokens,
    Expression<int>? outputTokens,
    Expression<int>? cachedTokens,
    Expression<int>? estimatedCostCents,
    Expression<int>? eventCount,
    Expression<int>? totalDurationMs,
    Expression<int>? retryCount,
    Expression<int>? firstTokenDurationMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (runId != null) 'run_id': runId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (model != null) 'model': model,
      if (status != null) 'status': status,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (inputTokens != null) 'input_tokens': inputTokens,
      if (outputTokens != null) 'output_tokens': outputTokens,
      if (cachedTokens != null) 'cached_tokens': cachedTokens,
      if (estimatedCostCents != null)
        'estimated_cost_cents': estimatedCostCents,
      if (eventCount != null) 'event_count': eventCount,
      if (totalDurationMs != null) 'total_duration_ms': totalDurationMs,
      if (retryCount != null) 'retry_count': retryCount,
      if (firstTokenDurationMs != null)
        'first_token_duration_ms': firstTokenDurationMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RunRecordsCompanion copyWith(
      {Value<String>? runId,
      Value<String>? conversationId,
      Value<String>? model,
      Value<String>? status,
      Value<DateTime>? startedAt,
      Value<DateTime?>? endedAt,
      Value<int>? inputTokens,
      Value<int>? outputTokens,
      Value<int>? cachedTokens,
      Value<int?>? estimatedCostCents,
      Value<int>? eventCount,
      Value<int?>? totalDurationMs,
      Value<int>? retryCount,
      Value<int?>? firstTokenDurationMs,
      Value<int>? rowid}) {
    return RunRecordsCompanion(
      runId: runId ?? this.runId,
      conversationId: conversationId ?? this.conversationId,
      model: model ?? this.model,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      inputTokens: inputTokens ?? this.inputTokens,
      outputTokens: outputTokens ?? this.outputTokens,
      cachedTokens: cachedTokens ?? this.cachedTokens,
      estimatedCostCents: estimatedCostCents ?? this.estimatedCostCents,
      eventCount: eventCount ?? this.eventCount,
      totalDurationMs: totalDurationMs ?? this.totalDurationMs,
      retryCount: retryCount ?? this.retryCount,
      firstTokenDurationMs: firstTokenDurationMs ?? this.firstTokenDurationMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (runId.present) {
      map['run_id'] = Variable<String>(runId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (inputTokens.present) {
      map['input_tokens'] = Variable<int>(inputTokens.value);
    }
    if (outputTokens.present) {
      map['output_tokens'] = Variable<int>(outputTokens.value);
    }
    if (cachedTokens.present) {
      map['cached_tokens'] = Variable<int>(cachedTokens.value);
    }
    if (estimatedCostCents.present) {
      map['estimated_cost_cents'] = Variable<int>(estimatedCostCents.value);
    }
    if (eventCount.present) {
      map['event_count'] = Variable<int>(eventCount.value);
    }
    if (totalDurationMs.present) {
      map['total_duration_ms'] = Variable<int>(totalDurationMs.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (firstTokenDurationMs.present) {
      map['first_token_duration_ms'] =
          Variable<int>(firstTokenDurationMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RunRecordsCompanion(')
          ..write('runId: $runId, ')
          ..write('conversationId: $conversationId, ')
          ..write('model: $model, ')
          ..write('status: $status, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('inputTokens: $inputTokens, ')
          ..write('outputTokens: $outputTokens, ')
          ..write('cachedTokens: $cachedTokens, ')
          ..write('estimatedCostCents: $estimatedCostCents, ')
          ..write('eventCount: $eventCount, ')
          ..write('totalDurationMs: $totalDurationMs, ')
          ..write('retryCount: $retryCount, ')
          ..write('firstTokenDurationMs: $firstTokenDurationMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RunEventsTable extends RunEvents
    with TableInfo<$RunEventsTable, RunEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RunEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _eventIdMeta =
      const VerificationMeta('eventId');
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
      'event_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  @override
  late final GeneratedColumn<String> runId = GeneratedColumn<String>(
      'run_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sequenceNoMeta =
      const VerificationMeta('sequenceNo');
  @override
  late final GeneratedColumn<int> sequenceNo = GeneratedColumn<int>(
      'sequence_no', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _startedAtMeta =
      const VerificationMeta('startedAt');
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
      'started_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _endedAtMeta =
      const VerificationMeta('endedAt');
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
      'ended_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _durationMsMeta =
      const VerificationMeta('durationMs');
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
      'duration_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _inputSummaryMeta =
      const VerificationMeta('inputSummary');
  @override
  late final GeneratedColumn<String> inputSummary = GeneratedColumn<String>(
      'input_summary', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _outputSummaryMeta =
      const VerificationMeta('outputSummary');
  @override
  late final GeneratedColumn<String> outputSummary = GeneratedColumn<String>(
      'output_summary', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _metadataJsonMeta =
      const VerificationMeta('metadataJson');
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
      'metadata_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('{}'));
  @override
  List<GeneratedColumn> get $columns => [
        eventId,
        runId,
        sequenceNo,
        type,
        status,
        name,
        startedAt,
        endedAt,
        durationMs,
        inputSummary,
        outputSummary,
        metadataJson
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'run_events';
  @override
  VerificationContext validateIntegrity(Insertable<RunEvent> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('event_id')) {
      context.handle(_eventIdMeta,
          eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta));
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('run_id')) {
      context.handle(
          _runIdMeta, runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta));
    } else if (isInserting) {
      context.missing(_runIdMeta);
    }
    if (data.containsKey('sequence_no')) {
      context.handle(
          _sequenceNoMeta,
          sequenceNo.isAcceptableOrUnknown(
              data['sequence_no']!, _sequenceNoMeta));
    } else if (isInserting) {
      context.missing(_sequenceNoMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(_startedAtMeta,
          startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta));
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(_endedAtMeta,
          endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta));
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
          _durationMsMeta,
          durationMs.isAcceptableOrUnknown(
              data['duration_ms']!, _durationMsMeta));
    }
    if (data.containsKey('input_summary')) {
      context.handle(
          _inputSummaryMeta,
          inputSummary.isAcceptableOrUnknown(
              data['input_summary']!, _inputSummaryMeta));
    }
    if (data.containsKey('output_summary')) {
      context.handle(
          _outputSummaryMeta,
          outputSummary.isAcceptableOrUnknown(
              data['output_summary']!, _outputSummaryMeta));
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
          _metadataJsonMeta,
          metadataJson.isAcceptableOrUnknown(
              data['metadata_json']!, _metadataJsonMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {eventId};
  @override
  RunEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RunEvent(
      eventId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}event_id'])!,
      runId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}run_id'])!,
      sequenceNo: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sequence_no'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      startedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}started_at'])!,
      endedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}ended_at']),
      durationMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_ms']),
      inputSummary: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}input_summary']),
      outputSummary: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}output_summary']),
      metadataJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}metadata_json'])!,
    );
  }

  @override
  $RunEventsTable createAlias(String alias) {
    return $RunEventsTable(attachedDatabase, alias);
  }
}

class RunEvent extends DataClass implements Insertable<RunEvent> {
  final String eventId;
  final String runId;
  final int sequenceNo;
  final String type;
  final String status;
  final String name;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? durationMs;
  final String? inputSummary;
  final String? outputSummary;
  final String metadataJson;
  const RunEvent(
      {required this.eventId,
      required this.runId,
      required this.sequenceNo,
      required this.type,
      required this.status,
      required this.name,
      required this.startedAt,
      this.endedAt,
      this.durationMs,
      this.inputSummary,
      this.outputSummary,
      required this.metadataJson});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['event_id'] = Variable<String>(eventId);
    map['run_id'] = Variable<String>(runId);
    map['sequence_no'] = Variable<int>(sequenceNo);
    map['type'] = Variable<String>(type);
    map['status'] = Variable<String>(status);
    map['name'] = Variable<String>(name);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<DateTime>(endedAt);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || inputSummary != null) {
      map['input_summary'] = Variable<String>(inputSummary);
    }
    if (!nullToAbsent || outputSummary != null) {
      map['output_summary'] = Variable<String>(outputSummary);
    }
    map['metadata_json'] = Variable<String>(metadataJson);
    return map;
  }

  RunEventsCompanion toCompanion(bool nullToAbsent) {
    return RunEventsCompanion(
      eventId: Value(eventId),
      runId: Value(runId),
      sequenceNo: Value(sequenceNo),
      type: Value(type),
      status: Value(status),
      name: Value(name),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      inputSummary: inputSummary == null && nullToAbsent
          ? const Value.absent()
          : Value(inputSummary),
      outputSummary: outputSummary == null && nullToAbsent
          ? const Value.absent()
          : Value(outputSummary),
      metadataJson: Value(metadataJson),
    );
  }

  factory RunEvent.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RunEvent(
      eventId: serializer.fromJson<String>(json['eventId']),
      runId: serializer.fromJson<String>(json['runId']),
      sequenceNo: serializer.fromJson<int>(json['sequenceNo']),
      type: serializer.fromJson<String>(json['type']),
      status: serializer.fromJson<String>(json['status']),
      name: serializer.fromJson<String>(json['name']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      inputSummary: serializer.fromJson<String?>(json['inputSummary']),
      outputSummary: serializer.fromJson<String?>(json['outputSummary']),
      metadataJson: serializer.fromJson<String>(json['metadataJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'eventId': serializer.toJson<String>(eventId),
      'runId': serializer.toJson<String>(runId),
      'sequenceNo': serializer.toJson<int>(sequenceNo),
      'type': serializer.toJson<String>(type),
      'status': serializer.toJson<String>(status),
      'name': serializer.toJson<String>(name),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
      'durationMs': serializer.toJson<int?>(durationMs),
      'inputSummary': serializer.toJson<String?>(inputSummary),
      'outputSummary': serializer.toJson<String?>(outputSummary),
      'metadataJson': serializer.toJson<String>(metadataJson),
    };
  }

  RunEvent copyWith(
          {String? eventId,
          String? runId,
          int? sequenceNo,
          String? type,
          String? status,
          String? name,
          DateTime? startedAt,
          Value<DateTime?> endedAt = const Value.absent(),
          Value<int?> durationMs = const Value.absent(),
          Value<String?> inputSummary = const Value.absent(),
          Value<String?> outputSummary = const Value.absent(),
          String? metadataJson}) =>
      RunEvent(
        eventId: eventId ?? this.eventId,
        runId: runId ?? this.runId,
        sequenceNo: sequenceNo ?? this.sequenceNo,
        type: type ?? this.type,
        status: status ?? this.status,
        name: name ?? this.name,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt.present ? endedAt.value : this.endedAt,
        durationMs: durationMs.present ? durationMs.value : this.durationMs,
        inputSummary:
            inputSummary.present ? inputSummary.value : this.inputSummary,
        outputSummary:
            outputSummary.present ? outputSummary.value : this.outputSummary,
        metadataJson: metadataJson ?? this.metadataJson,
      );
  RunEvent copyWithCompanion(RunEventsCompanion data) {
    return RunEvent(
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      runId: data.runId.present ? data.runId.value : this.runId,
      sequenceNo:
          data.sequenceNo.present ? data.sequenceNo.value : this.sequenceNo,
      type: data.type.present ? data.type.value : this.type,
      status: data.status.present ? data.status.value : this.status,
      name: data.name.present ? data.name.value : this.name,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      durationMs:
          data.durationMs.present ? data.durationMs.value : this.durationMs,
      inputSummary: data.inputSummary.present
          ? data.inputSummary.value
          : this.inputSummary,
      outputSummary: data.outputSummary.present
          ? data.outputSummary.value
          : this.outputSummary,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RunEvent(')
          ..write('eventId: $eventId, ')
          ..write('runId: $runId, ')
          ..write('sequenceNo: $sequenceNo, ')
          ..write('type: $type, ')
          ..write('status: $status, ')
          ..write('name: $name, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('durationMs: $durationMs, ')
          ..write('inputSummary: $inputSummary, ')
          ..write('outputSummary: $outputSummary, ')
          ..write('metadataJson: $metadataJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      eventId,
      runId,
      sequenceNo,
      type,
      status,
      name,
      startedAt,
      endedAt,
      durationMs,
      inputSummary,
      outputSummary,
      metadataJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RunEvent &&
          other.eventId == this.eventId &&
          other.runId == this.runId &&
          other.sequenceNo == this.sequenceNo &&
          other.type == this.type &&
          other.status == this.status &&
          other.name == this.name &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.durationMs == this.durationMs &&
          other.inputSummary == this.inputSummary &&
          other.outputSummary == this.outputSummary &&
          other.metadataJson == this.metadataJson);
}

class RunEventsCompanion extends UpdateCompanion<RunEvent> {
  final Value<String> eventId;
  final Value<String> runId;
  final Value<int> sequenceNo;
  final Value<String> type;
  final Value<String> status;
  final Value<String> name;
  final Value<DateTime> startedAt;
  final Value<DateTime?> endedAt;
  final Value<int?> durationMs;
  final Value<String?> inputSummary;
  final Value<String?> outputSummary;
  final Value<String> metadataJson;
  final Value<int> rowid;
  const RunEventsCompanion({
    this.eventId = const Value.absent(),
    this.runId = const Value.absent(),
    this.sequenceNo = const Value.absent(),
    this.type = const Value.absent(),
    this.status = const Value.absent(),
    this.name = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.inputSummary = const Value.absent(),
    this.outputSummary = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RunEventsCompanion.insert({
    required String eventId,
    required String runId,
    required int sequenceNo,
    required String type,
    required String status,
    required String name,
    required DateTime startedAt,
    this.endedAt = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.inputSummary = const Value.absent(),
    this.outputSummary = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : eventId = Value(eventId),
        runId = Value(runId),
        sequenceNo = Value(sequenceNo),
        type = Value(type),
        status = Value(status),
        name = Value(name),
        startedAt = Value(startedAt);
  static Insertable<RunEvent> custom({
    Expression<String>? eventId,
    Expression<String>? runId,
    Expression<int>? sequenceNo,
    Expression<String>? type,
    Expression<String>? status,
    Expression<String>? name,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endedAt,
    Expression<int>? durationMs,
    Expression<String>? inputSummary,
    Expression<String>? outputSummary,
    Expression<String>? metadataJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (eventId != null) 'event_id': eventId,
      if (runId != null) 'run_id': runId,
      if (sequenceNo != null) 'sequence_no': sequenceNo,
      if (type != null) 'type': type,
      if (status != null) 'status': status,
      if (name != null) 'name': name,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (durationMs != null) 'duration_ms': durationMs,
      if (inputSummary != null) 'input_summary': inputSummary,
      if (outputSummary != null) 'output_summary': outputSummary,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RunEventsCompanion copyWith(
      {Value<String>? eventId,
      Value<String>? runId,
      Value<int>? sequenceNo,
      Value<String>? type,
      Value<String>? status,
      Value<String>? name,
      Value<DateTime>? startedAt,
      Value<DateTime?>? endedAt,
      Value<int?>? durationMs,
      Value<String?>? inputSummary,
      Value<String?>? outputSummary,
      Value<String>? metadataJson,
      Value<int>? rowid}) {
    return RunEventsCompanion(
      eventId: eventId ?? this.eventId,
      runId: runId ?? this.runId,
      sequenceNo: sequenceNo ?? this.sequenceNo,
      type: type ?? this.type,
      status: status ?? this.status,
      name: name ?? this.name,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      durationMs: durationMs ?? this.durationMs,
      inputSummary: inputSummary ?? this.inputSummary,
      outputSummary: outputSummary ?? this.outputSummary,
      metadataJson: metadataJson ?? this.metadataJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (runId.present) {
      map['run_id'] = Variable<String>(runId.value);
    }
    if (sequenceNo.present) {
      map['sequence_no'] = Variable<int>(sequenceNo.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (inputSummary.present) {
      map['input_summary'] = Variable<String>(inputSummary.value);
    }
    if (outputSummary.present) {
      map['output_summary'] = Variable<String>(outputSummary.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RunEventsCompanion(')
          ..write('eventId: $eventId, ')
          ..write('runId: $runId, ')
          ..write('sequenceNo: $sequenceNo, ')
          ..write('type: $type, ')
          ..write('status: $status, ')
          ..write('name: $name, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('durationMs: $durationMs, ')
          ..write('inputSummary: $inputSummary, ')
          ..write('outputSummary: $outputSummary, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LogRecordsTable extends LogRecords
    with TableInfo<$LogRecordsTable, LogRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LogRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _logIdMeta = const VerificationMeta('logId');
  @override
  late final GeneratedColumn<String> logId = GeneratedColumn<String>(
      'log_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  @override
  late final GeneratedColumn<String> runId = GeneratedColumn<String>(
      'run_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _eventIdMeta =
      const VerificationMeta('eventId');
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
      'event_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<String> level = GeneratedColumn<String>(
      'level', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _messageMeta =
      const VerificationMeta('message');
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
      'message', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _detailJsonMeta =
      const VerificationMeta('detailJson');
  @override
  late final GeneratedColumn<String> detailJson = GeneratedColumn<String>(
      'detail_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _errorCodeMeta =
      const VerificationMeta('errorCode');
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
      'error_code', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _stackTraceMeta =
      const VerificationMeta('stackTrace');
  @override
  late final GeneratedColumn<String> stackTrace = GeneratedColumn<String>(
      'stack_trace', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _retryableMeta =
      const VerificationMeta('retryable');
  @override
  late final GeneratedColumn<bool> retryable = GeneratedColumn<bool>(
      'retryable', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("retryable" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        logId,
        runId,
        eventId,
        level,
        category,
        message,
        detailJson,
        errorCode,
        stackTrace,
        createdAt,
        retryable
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'log_records';
  @override
  VerificationContext validateIntegrity(Insertable<LogRecord> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('log_id')) {
      context.handle(
          _logIdMeta, logId.isAcceptableOrUnknown(data['log_id']!, _logIdMeta));
    } else if (isInserting) {
      context.missing(_logIdMeta);
    }
    if (data.containsKey('run_id')) {
      context.handle(
          _runIdMeta, runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta));
    }
    if (data.containsKey('event_id')) {
      context.handle(_eventIdMeta,
          eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta));
    }
    if (data.containsKey('level')) {
      context.handle(
          _levelMeta, level.isAcceptableOrUnknown(data['level']!, _levelMeta));
    } else if (isInserting) {
      context.missing(_levelMeta);
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('message')) {
      context.handle(_messageMeta,
          message.isAcceptableOrUnknown(data['message']!, _messageMeta));
    } else if (isInserting) {
      context.missing(_messageMeta);
    }
    if (data.containsKey('detail_json')) {
      context.handle(
          _detailJsonMeta,
          detailJson.isAcceptableOrUnknown(
              data['detail_json']!, _detailJsonMeta));
    }
    if (data.containsKey('error_code')) {
      context.handle(_errorCodeMeta,
          errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta));
    }
    if (data.containsKey('stack_trace')) {
      context.handle(
          _stackTraceMeta,
          stackTrace.isAcceptableOrUnknown(
              data['stack_trace']!, _stackTraceMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('retryable')) {
      context.handle(_retryableMeta,
          retryable.isAcceptableOrUnknown(data['retryable']!, _retryableMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {logId};
  @override
  LogRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LogRecord(
      logId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}log_id'])!,
      runId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}run_id']),
      eventId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}event_id']),
      level: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}level'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
      message: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}message'])!,
      detailJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}detail_json']),
      errorCode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}error_code']),
      stackTrace: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}stack_trace']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      retryable: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}retryable'])!,
    );
  }

  @override
  $LogRecordsTable createAlias(String alias) {
    return $LogRecordsTable(attachedDatabase, alias);
  }
}

class LogRecord extends DataClass implements Insertable<LogRecord> {
  final String logId;
  final String? runId;
  final String? eventId;
  final String level;
  final String category;
  final String message;
  final String? detailJson;
  final String? errorCode;
  final String? stackTrace;
  final DateTime createdAt;
  final bool retryable;
  const LogRecord(
      {required this.logId,
      this.runId,
      this.eventId,
      required this.level,
      required this.category,
      required this.message,
      this.detailJson,
      this.errorCode,
      this.stackTrace,
      required this.createdAt,
      required this.retryable});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['log_id'] = Variable<String>(logId);
    if (!nullToAbsent || runId != null) {
      map['run_id'] = Variable<String>(runId);
    }
    if (!nullToAbsent || eventId != null) {
      map['event_id'] = Variable<String>(eventId);
    }
    map['level'] = Variable<String>(level);
    map['category'] = Variable<String>(category);
    map['message'] = Variable<String>(message);
    if (!nullToAbsent || detailJson != null) {
      map['detail_json'] = Variable<String>(detailJson);
    }
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    if (!nullToAbsent || stackTrace != null) {
      map['stack_trace'] = Variable<String>(stackTrace);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['retryable'] = Variable<bool>(retryable);
    return map;
  }

  LogRecordsCompanion toCompanion(bool nullToAbsent) {
    return LogRecordsCompanion(
      logId: Value(logId),
      runId:
          runId == null && nullToAbsent ? const Value.absent() : Value(runId),
      eventId: eventId == null && nullToAbsent
          ? const Value.absent()
          : Value(eventId),
      level: Value(level),
      category: Value(category),
      message: Value(message),
      detailJson: detailJson == null && nullToAbsent
          ? const Value.absent()
          : Value(detailJson),
      errorCode: errorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(errorCode),
      stackTrace: stackTrace == null && nullToAbsent
          ? const Value.absent()
          : Value(stackTrace),
      createdAt: Value(createdAt),
      retryable: Value(retryable),
    );
  }

  factory LogRecord.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LogRecord(
      logId: serializer.fromJson<String>(json['logId']),
      runId: serializer.fromJson<String?>(json['runId']),
      eventId: serializer.fromJson<String?>(json['eventId']),
      level: serializer.fromJson<String>(json['level']),
      category: serializer.fromJson<String>(json['category']),
      message: serializer.fromJson<String>(json['message']),
      detailJson: serializer.fromJson<String?>(json['detailJson']),
      errorCode: serializer.fromJson<String?>(json['errorCode']),
      stackTrace: serializer.fromJson<String?>(json['stackTrace']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      retryable: serializer.fromJson<bool>(json['retryable']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'logId': serializer.toJson<String>(logId),
      'runId': serializer.toJson<String?>(runId),
      'eventId': serializer.toJson<String?>(eventId),
      'level': serializer.toJson<String>(level),
      'category': serializer.toJson<String>(category),
      'message': serializer.toJson<String>(message),
      'detailJson': serializer.toJson<String?>(detailJson),
      'errorCode': serializer.toJson<String?>(errorCode),
      'stackTrace': serializer.toJson<String?>(stackTrace),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'retryable': serializer.toJson<bool>(retryable),
    };
  }

  LogRecord copyWith(
          {String? logId,
          Value<String?> runId = const Value.absent(),
          Value<String?> eventId = const Value.absent(),
          String? level,
          String? category,
          String? message,
          Value<String?> detailJson = const Value.absent(),
          Value<String?> errorCode = const Value.absent(),
          Value<String?> stackTrace = const Value.absent(),
          DateTime? createdAt,
          bool? retryable}) =>
      LogRecord(
        logId: logId ?? this.logId,
        runId: runId.present ? runId.value : this.runId,
        eventId: eventId.present ? eventId.value : this.eventId,
        level: level ?? this.level,
        category: category ?? this.category,
        message: message ?? this.message,
        detailJson: detailJson.present ? detailJson.value : this.detailJson,
        errorCode: errorCode.present ? errorCode.value : this.errorCode,
        stackTrace: stackTrace.present ? stackTrace.value : this.stackTrace,
        createdAt: createdAt ?? this.createdAt,
        retryable: retryable ?? this.retryable,
      );
  LogRecord copyWithCompanion(LogRecordsCompanion data) {
    return LogRecord(
      logId: data.logId.present ? data.logId.value : this.logId,
      runId: data.runId.present ? data.runId.value : this.runId,
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      level: data.level.present ? data.level.value : this.level,
      category: data.category.present ? data.category.value : this.category,
      message: data.message.present ? data.message.value : this.message,
      detailJson:
          data.detailJson.present ? data.detailJson.value : this.detailJson,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      stackTrace:
          data.stackTrace.present ? data.stackTrace.value : this.stackTrace,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      retryable: data.retryable.present ? data.retryable.value : this.retryable,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LogRecord(')
          ..write('logId: $logId, ')
          ..write('runId: $runId, ')
          ..write('eventId: $eventId, ')
          ..write('level: $level, ')
          ..write('category: $category, ')
          ..write('message: $message, ')
          ..write('detailJson: $detailJson, ')
          ..write('errorCode: $errorCode, ')
          ..write('stackTrace: $stackTrace, ')
          ..write('createdAt: $createdAt, ')
          ..write('retryable: $retryable')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(logId, runId, eventId, level, category,
      message, detailJson, errorCode, stackTrace, createdAt, retryable);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LogRecord &&
          other.logId == this.logId &&
          other.runId == this.runId &&
          other.eventId == this.eventId &&
          other.level == this.level &&
          other.category == this.category &&
          other.message == this.message &&
          other.detailJson == this.detailJson &&
          other.errorCode == this.errorCode &&
          other.stackTrace == this.stackTrace &&
          other.createdAt == this.createdAt &&
          other.retryable == this.retryable);
}

class LogRecordsCompanion extends UpdateCompanion<LogRecord> {
  final Value<String> logId;
  final Value<String?> runId;
  final Value<String?> eventId;
  final Value<String> level;
  final Value<String> category;
  final Value<String> message;
  final Value<String?> detailJson;
  final Value<String?> errorCode;
  final Value<String?> stackTrace;
  final Value<DateTime> createdAt;
  final Value<bool> retryable;
  final Value<int> rowid;
  const LogRecordsCompanion({
    this.logId = const Value.absent(),
    this.runId = const Value.absent(),
    this.eventId = const Value.absent(),
    this.level = const Value.absent(),
    this.category = const Value.absent(),
    this.message = const Value.absent(),
    this.detailJson = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.stackTrace = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.retryable = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LogRecordsCompanion.insert({
    required String logId,
    this.runId = const Value.absent(),
    this.eventId = const Value.absent(),
    required String level,
    required String category,
    required String message,
    this.detailJson = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.stackTrace = const Value.absent(),
    required DateTime createdAt,
    this.retryable = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : logId = Value(logId),
        level = Value(level),
        category = Value(category),
        message = Value(message),
        createdAt = Value(createdAt);
  static Insertable<LogRecord> custom({
    Expression<String>? logId,
    Expression<String>? runId,
    Expression<String>? eventId,
    Expression<String>? level,
    Expression<String>? category,
    Expression<String>? message,
    Expression<String>? detailJson,
    Expression<String>? errorCode,
    Expression<String>? stackTrace,
    Expression<DateTime>? createdAt,
    Expression<bool>? retryable,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (logId != null) 'log_id': logId,
      if (runId != null) 'run_id': runId,
      if (eventId != null) 'event_id': eventId,
      if (level != null) 'level': level,
      if (category != null) 'category': category,
      if (message != null) 'message': message,
      if (detailJson != null) 'detail_json': detailJson,
      if (errorCode != null) 'error_code': errorCode,
      if (stackTrace != null) 'stack_trace': stackTrace,
      if (createdAt != null) 'created_at': createdAt,
      if (retryable != null) 'retryable': retryable,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LogRecordsCompanion copyWith(
      {Value<String>? logId,
      Value<String?>? runId,
      Value<String?>? eventId,
      Value<String>? level,
      Value<String>? category,
      Value<String>? message,
      Value<String?>? detailJson,
      Value<String?>? errorCode,
      Value<String?>? stackTrace,
      Value<DateTime>? createdAt,
      Value<bool>? retryable,
      Value<int>? rowid}) {
    return LogRecordsCompanion(
      logId: logId ?? this.logId,
      runId: runId ?? this.runId,
      eventId: eventId ?? this.eventId,
      level: level ?? this.level,
      category: category ?? this.category,
      message: message ?? this.message,
      detailJson: detailJson ?? this.detailJson,
      errorCode: errorCode ?? this.errorCode,
      stackTrace: stackTrace ?? this.stackTrace,
      createdAt: createdAt ?? this.createdAt,
      retryable: retryable ?? this.retryable,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (logId.present) {
      map['log_id'] = Variable<String>(logId.value);
    }
    if (runId.present) {
      map['run_id'] = Variable<String>(runId.value);
    }
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (level.present) {
      map['level'] = Variable<String>(level.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (detailJson.present) {
      map['detail_json'] = Variable<String>(detailJson.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (stackTrace.present) {
      map['stack_trace'] = Variable<String>(stackTrace.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (retryable.present) {
      map['retryable'] = Variable<bool>(retryable.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LogRecordsCompanion(')
          ..write('logId: $logId, ')
          ..write('runId: $runId, ')
          ..write('eventId: $eventId, ')
          ..write('level: $level, ')
          ..write('category: $category, ')
          ..write('message: $message, ')
          ..write('detailJson: $detailJson, ')
          ..write('errorCode: $errorCode, ')
          ..write('stackTrace: $stackTrace, ')
          ..write('createdAt: $createdAt, ')
          ..write('retryable: $retryable, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ConversationsTable conversations = $ConversationsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $AgentsTable agents = $AgentsTable(this);
  late final $PromptTemplatesTable promptTemplates =
      $PromptTemplatesTable(this);
  late final $ModelProfilesTable modelProfiles = $ModelProfilesTable(this);
  late final $MemoriesTable memories = $MemoriesTable(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $SyncMetaTable syncMeta = $SyncMetaTable(this);
  late final $KnowledgeDocsTable knowledgeDocs = $KnowledgeDocsTable(this);
  late final $KnowledgeChunksTable knowledgeChunks =
      $KnowledgeChunksTable(this);
  late final $ScheduledTasksTable scheduledTasks = $ScheduledTasksTable(this);
  late final $AuditLogsTable auditLogs = $AuditLogsTable(this);
  late final $PluginsTable plugins = $PluginsTable(this);
  late final $SkillPacksTable skillPacks = $SkillPacksTable(this);
  late final $McpServersTable mcpServers = $McpServersTable(this);
  late final $AccountMetaTable accountMeta = $AccountMetaTable(this);
  late final $RunRecordsTable runRecords = $RunRecordsTable(this);
  late final $RunEventsTable runEvents = $RunEventsTable(this);
  late final $LogRecordsTable logRecords = $LogRecordsTable(this);
  late final Index idxMessagesConversation = Index('idx_messages_conversation',
      'CREATE INDEX idx_messages_conversation ON messages (conversation_id)');
  late final Index idxRunEventsRunSequence = Index(
      'idx_run_events_run_sequence',
      'CREATE UNIQUE INDEX idx_run_events_run_sequence ON run_events (run_id, sequence_no)');
  late final Index idxLogRecordsRunCreated = Index(
      'idx_log_records_run_created',
      'CREATE INDEX idx_log_records_run_created ON log_records (run_id, created_at)');
  late final Index idxLogRecordsLevelCreated = Index(
      'idx_log_records_level_created',
      'CREATE INDEX idx_log_records_level_created ON log_records (level, created_at)');
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        conversations,
        messages,
        agents,
        promptTemplates,
        modelProfiles,
        memories,
        tasks,
        syncMeta,
        knowledgeDocs,
        knowledgeChunks,
        scheduledTasks,
        auditLogs,
        plugins,
        skillPacks,
        mcpServers,
        accountMeta,
        runRecords,
        runEvents,
        logRecords,
        idxMessagesConversation,
        idxRunEventsRunSequence,
        idxLogRecordsRunCreated,
        idxLogRecordsLevelCreated
      ];
}

typedef $$ConversationsTableCreateCompanionBuilder = ConversationsCompanion
    Function({
  required String id,
  Value<String> title,
  Value<String?> agentId,
  Value<bool> isPinned,
  Value<bool> isFavorite,
  Value<String> tagsJson,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$ConversationsTableUpdateCompanionBuilder = ConversationsCompanion
    Function({
  Value<String> id,
  Value<String> title,
  Value<String?> agentId,
  Value<bool> isPinned,
  Value<bool> isFavorite,
  Value<String> tagsJson,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$ConversationsTableFilterComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get agentId => $composableBuilder(
      column: $table.agentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isPinned => $composableBuilder(
      column: $table.isPinned, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isFavorite => $composableBuilder(
      column: $table.isFavorite, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tagsJson => $composableBuilder(
      column: $table.tagsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$ConversationsTableOrderingComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get agentId => $composableBuilder(
      column: $table.agentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isPinned => $composableBuilder(
      column: $table.isPinned, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
      column: $table.isFavorite, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tagsJson => $composableBuilder(
      column: $table.tagsJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$ConversationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get agentId =>
      $composableBuilder(column: $table.agentId, builder: (column) => column);

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
      column: $table.isFavorite, builder: (column) => column);

  GeneratedColumn<String> get tagsJson =>
      $composableBuilder(column: $table.tagsJson, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ConversationsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ConversationsTable,
    Conversation,
    $$ConversationsTableFilterComposer,
    $$ConversationsTableOrderingComposer,
    $$ConversationsTableAnnotationComposer,
    $$ConversationsTableCreateCompanionBuilder,
    $$ConversationsTableUpdateCompanionBuilder,
    (
      Conversation,
      BaseReferences<_$AppDatabase, $ConversationsTable, Conversation>
    ),
    Conversation,
    PrefetchHooks Function()> {
  $$ConversationsTableTableManager(_$AppDatabase db, $ConversationsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String?> agentId = const Value.absent(),
            Value<bool> isPinned = const Value.absent(),
            Value<bool> isFavorite = const Value.absent(),
            Value<String> tagsJson = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ConversationsCompanion(
            id: id,
            title: title,
            agentId: agentId,
            isPinned: isPinned,
            isFavorite: isFavorite,
            tagsJson: tagsJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String> title = const Value.absent(),
            Value<String?> agentId = const Value.absent(),
            Value<bool> isPinned = const Value.absent(),
            Value<bool> isFavorite = const Value.absent(),
            Value<String> tagsJson = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ConversationsCompanion.insert(
            id: id,
            title: title,
            agentId: agentId,
            isPinned: isPinned,
            isFavorite: isFavorite,
            tagsJson: tagsJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ConversationsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ConversationsTable,
    Conversation,
    $$ConversationsTableFilterComposer,
    $$ConversationsTableOrderingComposer,
    $$ConversationsTableAnnotationComposer,
    $$ConversationsTableCreateCompanionBuilder,
    $$ConversationsTableUpdateCompanionBuilder,
    (
      Conversation,
      BaseReferences<_$AppDatabase, $ConversationsTable, Conversation>
    ),
    Conversation,
    PrefetchHooks Function()>;
typedef $$MessagesTableCreateCompanionBuilder = MessagesCompanion Function({
  required String id,
  required String conversationId,
  required String role,
  required String content,
  Value<String?> toolCallId,
  Value<String?> toolCallsJson,
  Value<String?> reasoningContent,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$MessagesTableUpdateCompanionBuilder = MessagesCompanion Function({
  Value<String> id,
  Value<String> conversationId,
  Value<String> role,
  Value<String> content,
  Value<String?> toolCallId,
  Value<String?> toolCallsJson,
  Value<String?> reasoningContent,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$MessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get conversationId => $composableBuilder(
      column: $table.conversationId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get toolCallId => $composableBuilder(
      column: $table.toolCallId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get toolCallsJson => $composableBuilder(
      column: $table.toolCallsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get reasoningContent => $composableBuilder(
      column: $table.reasoningContent,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get conversationId => $composableBuilder(
      column: $table.conversationId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get toolCallId => $composableBuilder(
      column: $table.toolCallId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get toolCallsJson => $composableBuilder(
      column: $table.toolCallsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get reasoningContent => $composableBuilder(
      column: $table.reasoningContent,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
      column: $table.conversationId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get toolCallId => $composableBuilder(
      column: $table.toolCallId, builder: (column) => column);

  GeneratedColumn<String> get toolCallsJson => $composableBuilder(
      column: $table.toolCallsJson, builder: (column) => column);

  GeneratedColumn<String> get reasoningContent => $composableBuilder(
      column: $table.reasoningContent, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$MessagesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MessagesTable,
    Message,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (Message, BaseReferences<_$AppDatabase, $MessagesTable, Message>),
    Message,
    PrefetchHooks Function()> {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> conversationId = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<String?> toolCallId = const Value.absent(),
            Value<String?> toolCallsJson = const Value.absent(),
            Value<String?> reasoningContent = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MessagesCompanion(
            id: id,
            conversationId: conversationId,
            role: role,
            content: content,
            toolCallId: toolCallId,
            toolCallsJson: toolCallsJson,
            reasoningContent: reasoningContent,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String conversationId,
            required String role,
            required String content,
            Value<String?> toolCallId = const Value.absent(),
            Value<String?> toolCallsJson = const Value.absent(),
            Value<String?> reasoningContent = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              MessagesCompanion.insert(
            id: id,
            conversationId: conversationId,
            role: role,
            content: content,
            toolCallId: toolCallId,
            toolCallsJson: toolCallsJson,
            reasoningContent: reasoningContent,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MessagesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MessagesTable,
    Message,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (Message, BaseReferences<_$AppDatabase, $MessagesTable, Message>),
    Message,
    PrefetchHooks Function()>;
typedef $$AgentsTableCreateCompanionBuilder = AgentsCompanion Function({
  required String id,
  required String name,
  Value<String> systemPrompt,
  required String modelProfileId,
  Value<String> enabledToolsJson,
  Value<double> temperature,
  Value<int> maxTokens,
  Value<int> maxSteps,
  Value<double> topP,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$AgentsTableUpdateCompanionBuilder = AgentsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> systemPrompt,
  Value<String> modelProfileId,
  Value<String> enabledToolsJson,
  Value<double> temperature,
  Value<int> maxTokens,
  Value<int> maxSteps,
  Value<double> topP,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$AgentsTableFilterComposer
    extends Composer<_$AppDatabase, $AgentsTable> {
  $$AgentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get systemPrompt => $composableBuilder(
      column: $table.systemPrompt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get modelProfileId => $composableBuilder(
      column: $table.modelProfileId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get enabledToolsJson => $composableBuilder(
      column: $table.enabledToolsJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get temperature => $composableBuilder(
      column: $table.temperature, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get maxTokens => $composableBuilder(
      column: $table.maxTokens, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get maxSteps => $composableBuilder(
      column: $table.maxSteps, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get topP => $composableBuilder(
      column: $table.topP, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$AgentsTableOrderingComposer
    extends Composer<_$AppDatabase, $AgentsTable> {
  $$AgentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get systemPrompt => $composableBuilder(
      column: $table.systemPrompt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get modelProfileId => $composableBuilder(
      column: $table.modelProfileId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get enabledToolsJson => $composableBuilder(
      column: $table.enabledToolsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get temperature => $composableBuilder(
      column: $table.temperature, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get maxTokens => $composableBuilder(
      column: $table.maxTokens, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get maxSteps => $composableBuilder(
      column: $table.maxSteps, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get topP => $composableBuilder(
      column: $table.topP, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$AgentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AgentsTable> {
  $$AgentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get systemPrompt => $composableBuilder(
      column: $table.systemPrompt, builder: (column) => column);

  GeneratedColumn<String> get modelProfileId => $composableBuilder(
      column: $table.modelProfileId, builder: (column) => column);

  GeneratedColumn<String> get enabledToolsJson => $composableBuilder(
      column: $table.enabledToolsJson, builder: (column) => column);

  GeneratedColumn<double> get temperature => $composableBuilder(
      column: $table.temperature, builder: (column) => column);

  GeneratedColumn<int> get maxTokens =>
      $composableBuilder(column: $table.maxTokens, builder: (column) => column);

  GeneratedColumn<int> get maxSteps =>
      $composableBuilder(column: $table.maxSteps, builder: (column) => column);

  GeneratedColumn<double> get topP =>
      $composableBuilder(column: $table.topP, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AgentsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AgentsTable,
    Agent,
    $$AgentsTableFilterComposer,
    $$AgentsTableOrderingComposer,
    $$AgentsTableAnnotationComposer,
    $$AgentsTableCreateCompanionBuilder,
    $$AgentsTableUpdateCompanionBuilder,
    (Agent, BaseReferences<_$AppDatabase, $AgentsTable, Agent>),
    Agent,
    PrefetchHooks Function()> {
  $$AgentsTableTableManager(_$AppDatabase db, $AgentsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AgentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AgentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AgentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> systemPrompt = const Value.absent(),
            Value<String> modelProfileId = const Value.absent(),
            Value<String> enabledToolsJson = const Value.absent(),
            Value<double> temperature = const Value.absent(),
            Value<int> maxTokens = const Value.absent(),
            Value<int> maxSteps = const Value.absent(),
            Value<double> topP = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AgentsCompanion(
            id: id,
            name: name,
            systemPrompt: systemPrompt,
            modelProfileId: modelProfileId,
            enabledToolsJson: enabledToolsJson,
            temperature: temperature,
            maxTokens: maxTokens,
            maxSteps: maxSteps,
            topP: topP,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<String> systemPrompt = const Value.absent(),
            required String modelProfileId,
            Value<String> enabledToolsJson = const Value.absent(),
            Value<double> temperature = const Value.absent(),
            Value<int> maxTokens = const Value.absent(),
            Value<int> maxSteps = const Value.absent(),
            Value<double> topP = const Value.absent(),
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              AgentsCompanion.insert(
            id: id,
            name: name,
            systemPrompt: systemPrompt,
            modelProfileId: modelProfileId,
            enabledToolsJson: enabledToolsJson,
            temperature: temperature,
            maxTokens: maxTokens,
            maxSteps: maxSteps,
            topP: topP,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AgentsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AgentsTable,
    Agent,
    $$AgentsTableFilterComposer,
    $$AgentsTableOrderingComposer,
    $$AgentsTableAnnotationComposer,
    $$AgentsTableCreateCompanionBuilder,
    $$AgentsTableUpdateCompanionBuilder,
    (Agent, BaseReferences<_$AppDatabase, $AgentsTable, Agent>),
    Agent,
    PrefetchHooks Function()>;
typedef $$PromptTemplatesTableCreateCompanionBuilder = PromptTemplatesCompanion
    Function({
  required String id,
  required String name,
  required String content,
  Value<String> category,
  Value<String> tagsJson,
  Value<bool> isFavorite,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$PromptTemplatesTableUpdateCompanionBuilder = PromptTemplatesCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<String> content,
  Value<String> category,
  Value<String> tagsJson,
  Value<bool> isFavorite,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$PromptTemplatesTableFilterComposer
    extends Composer<_$AppDatabase, $PromptTemplatesTable> {
  $$PromptTemplatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tagsJson => $composableBuilder(
      column: $table.tagsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isFavorite => $composableBuilder(
      column: $table.isFavorite, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$PromptTemplatesTableOrderingComposer
    extends Composer<_$AppDatabase, $PromptTemplatesTable> {
  $$PromptTemplatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tagsJson => $composableBuilder(
      column: $table.tagsJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
      column: $table.isFavorite, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$PromptTemplatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PromptTemplatesTable> {
  $$PromptTemplatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get tagsJson =>
      $composableBuilder(column: $table.tagsJson, builder: (column) => column);

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
      column: $table.isFavorite, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PromptTemplatesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PromptTemplatesTable,
    PromptTemplate,
    $$PromptTemplatesTableFilterComposer,
    $$PromptTemplatesTableOrderingComposer,
    $$PromptTemplatesTableAnnotationComposer,
    $$PromptTemplatesTableCreateCompanionBuilder,
    $$PromptTemplatesTableUpdateCompanionBuilder,
    (
      PromptTemplate,
      BaseReferences<_$AppDatabase, $PromptTemplatesTable, PromptTemplate>
    ),
    PromptTemplate,
    PrefetchHooks Function()> {
  $$PromptTemplatesTableTableManager(
      _$AppDatabase db, $PromptTemplatesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PromptTemplatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PromptTemplatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PromptTemplatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<String> tagsJson = const Value.absent(),
            Value<bool> isFavorite = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PromptTemplatesCompanion(
            id: id,
            name: name,
            content: content,
            category: category,
            tagsJson: tagsJson,
            isFavorite: isFavorite,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String content,
            Value<String> category = const Value.absent(),
            Value<String> tagsJson = const Value.absent(),
            Value<bool> isFavorite = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              PromptTemplatesCompanion.insert(
            id: id,
            name: name,
            content: content,
            category: category,
            tagsJson: tagsJson,
            isFavorite: isFavorite,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PromptTemplatesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PromptTemplatesTable,
    PromptTemplate,
    $$PromptTemplatesTableFilterComposer,
    $$PromptTemplatesTableOrderingComposer,
    $$PromptTemplatesTableAnnotationComposer,
    $$PromptTemplatesTableCreateCompanionBuilder,
    $$PromptTemplatesTableUpdateCompanionBuilder,
    (
      PromptTemplate,
      BaseReferences<_$AppDatabase, $PromptTemplatesTable, PromptTemplate>
    ),
    PromptTemplate,
    PrefetchHooks Function()>;
typedef $$ModelProfilesTableCreateCompanionBuilder = ModelProfilesCompanion
    Function({
  required String id,
  required String name,
  required String baseUrl,
  required String modelName,
  required String apiKeyRef,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$ModelProfilesTableUpdateCompanionBuilder = ModelProfilesCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<String> baseUrl,
  Value<String> modelName,
  Value<String> apiKeyRef,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$ModelProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $ModelProfilesTable> {
  $$ModelProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get baseUrl => $composableBuilder(
      column: $table.baseUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get modelName => $composableBuilder(
      column: $table.modelName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get apiKeyRef => $composableBuilder(
      column: $table.apiKeyRef, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$ModelProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $ModelProfilesTable> {
  $$ModelProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get baseUrl => $composableBuilder(
      column: $table.baseUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get modelName => $composableBuilder(
      column: $table.modelName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get apiKeyRef => $composableBuilder(
      column: $table.apiKeyRef, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$ModelProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ModelProfilesTable> {
  $$ModelProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get baseUrl =>
      $composableBuilder(column: $table.baseUrl, builder: (column) => column);

  GeneratedColumn<String> get modelName =>
      $composableBuilder(column: $table.modelName, builder: (column) => column);

  GeneratedColumn<String> get apiKeyRef =>
      $composableBuilder(column: $table.apiKeyRef, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ModelProfilesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ModelProfilesTable,
    ModelProfile,
    $$ModelProfilesTableFilterComposer,
    $$ModelProfilesTableOrderingComposer,
    $$ModelProfilesTableAnnotationComposer,
    $$ModelProfilesTableCreateCompanionBuilder,
    $$ModelProfilesTableUpdateCompanionBuilder,
    (
      ModelProfile,
      BaseReferences<_$AppDatabase, $ModelProfilesTable, ModelProfile>
    ),
    ModelProfile,
    PrefetchHooks Function()> {
  $$ModelProfilesTableTableManager(_$AppDatabase db, $ModelProfilesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ModelProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ModelProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ModelProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> baseUrl = const Value.absent(),
            Value<String> modelName = const Value.absent(),
            Value<String> apiKeyRef = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ModelProfilesCompanion(
            id: id,
            name: name,
            baseUrl: baseUrl,
            modelName: modelName,
            apiKeyRef: apiKeyRef,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String baseUrl,
            required String modelName,
            required String apiKeyRef,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ModelProfilesCompanion.insert(
            id: id,
            name: name,
            baseUrl: baseUrl,
            modelName: modelName,
            apiKeyRef: apiKeyRef,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ModelProfilesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ModelProfilesTable,
    ModelProfile,
    $$ModelProfilesTableFilterComposer,
    $$ModelProfilesTableOrderingComposer,
    $$ModelProfilesTableAnnotationComposer,
    $$ModelProfilesTableCreateCompanionBuilder,
    $$ModelProfilesTableUpdateCompanionBuilder,
    (
      ModelProfile,
      BaseReferences<_$AppDatabase, $ModelProfilesTable, ModelProfile>
    ),
    ModelProfile,
    PrefetchHooks Function()>;
typedef $$MemoriesTableCreateCompanionBuilder = MemoriesCompanion Function({
  required String id,
  required String content,
  Value<String> category,
  Value<String?> sourceConversationId,
  Value<String> sourceType,
  Value<bool> enabled,
  Value<int> importance,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$MemoriesTableUpdateCompanionBuilder = MemoriesCompanion Function({
  Value<String> id,
  Value<String> content,
  Value<String> category,
  Value<String?> sourceConversationId,
  Value<String> sourceType,
  Value<bool> enabled,
  Value<int> importance,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$MemoriesTableFilterComposer
    extends Composer<_$AppDatabase, $MemoriesTable> {
  $$MemoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceConversationId => $composableBuilder(
      column: $table.sourceConversationId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceType => $composableBuilder(
      column: $table.sourceType, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get importance => $composableBuilder(
      column: $table.importance, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$MemoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $MemoriesTable> {
  $$MemoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceConversationId => $composableBuilder(
      column: $table.sourceConversationId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceType => $composableBuilder(
      column: $table.sourceType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get importance => $composableBuilder(
      column: $table.importance, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$MemoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MemoriesTable> {
  $$MemoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get sourceConversationId => $composableBuilder(
      column: $table.sourceConversationId, builder: (column) => column);

  GeneratedColumn<String> get sourceType => $composableBuilder(
      column: $table.sourceType, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get importance => $composableBuilder(
      column: $table.importance, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$MemoriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MemoriesTable,
    Memory,
    $$MemoriesTableFilterComposer,
    $$MemoriesTableOrderingComposer,
    $$MemoriesTableAnnotationComposer,
    $$MemoriesTableCreateCompanionBuilder,
    $$MemoriesTableUpdateCompanionBuilder,
    (Memory, BaseReferences<_$AppDatabase, $MemoriesTable, Memory>),
    Memory,
    PrefetchHooks Function()> {
  $$MemoriesTableTableManager(_$AppDatabase db, $MemoriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MemoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MemoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MemoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<String?> sourceConversationId = const Value.absent(),
            Value<String> sourceType = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<int> importance = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MemoriesCompanion(
            id: id,
            content: content,
            category: category,
            sourceConversationId: sourceConversationId,
            sourceType: sourceType,
            enabled: enabled,
            importance: importance,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String content,
            Value<String> category = const Value.absent(),
            Value<String?> sourceConversationId = const Value.absent(),
            Value<String> sourceType = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<int> importance = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              MemoriesCompanion.insert(
            id: id,
            content: content,
            category: category,
            sourceConversationId: sourceConversationId,
            sourceType: sourceType,
            enabled: enabled,
            importance: importance,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MemoriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MemoriesTable,
    Memory,
    $$MemoriesTableFilterComposer,
    $$MemoriesTableOrderingComposer,
    $$MemoriesTableAnnotationComposer,
    $$MemoriesTableCreateCompanionBuilder,
    $$MemoriesTableUpdateCompanionBuilder,
    (Memory, BaseReferences<_$AppDatabase, $MemoriesTable, Memory>),
    Memory,
    PrefetchHooks Function()>;
typedef $$TasksTableCreateCompanionBuilder = TasksCompanion Function({
  required String id,
  required String conversationId,
  Value<String> type,
  Value<String> status,
  required String requestJson,
  Value<String> progressJson,
  Value<int> resumeCount,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$TasksTableUpdateCompanionBuilder = TasksCompanion Function({
  Value<String> id,
  Value<String> conversationId,
  Value<String> type,
  Value<String> status,
  Value<String> requestJson,
  Value<String> progressJson,
  Value<int> resumeCount,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$TasksTableFilterComposer extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get conversationId => $composableBuilder(
      column: $table.conversationId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get requestJson => $composableBuilder(
      column: $table.requestJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get progressJson => $composableBuilder(
      column: $table.progressJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get resumeCount => $composableBuilder(
      column: $table.resumeCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$TasksTableOrderingComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get conversationId => $composableBuilder(
      column: $table.conversationId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get requestJson => $composableBuilder(
      column: $table.requestJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get progressJson => $composableBuilder(
      column: $table.progressJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get resumeCount => $composableBuilder(
      column: $table.resumeCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$TasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
      column: $table.conversationId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get requestJson => $composableBuilder(
      column: $table.requestJson, builder: (column) => column);

  GeneratedColumn<String> get progressJson => $composableBuilder(
      column: $table.progressJson, builder: (column) => column);

  GeneratedColumn<int> get resumeCount => $composableBuilder(
      column: $table.resumeCount, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$TasksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TasksTable,
    Task,
    $$TasksTableFilterComposer,
    $$TasksTableOrderingComposer,
    $$TasksTableAnnotationComposer,
    $$TasksTableCreateCompanionBuilder,
    $$TasksTableUpdateCompanionBuilder,
    (Task, BaseReferences<_$AppDatabase, $TasksTable, Task>),
    Task,
    PrefetchHooks Function()> {
  $$TasksTableTableManager(_$AppDatabase db, $TasksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> conversationId = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String> requestJson = const Value.absent(),
            Value<String> progressJson = const Value.absent(),
            Value<int> resumeCount = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TasksCompanion(
            id: id,
            conversationId: conversationId,
            type: type,
            status: status,
            requestJson: requestJson,
            progressJson: progressJson,
            resumeCount: resumeCount,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String conversationId,
            Value<String> type = const Value.absent(),
            Value<String> status = const Value.absent(),
            required String requestJson,
            Value<String> progressJson = const Value.absent(),
            Value<int> resumeCount = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              TasksCompanion.insert(
            id: id,
            conversationId: conversationId,
            type: type,
            status: status,
            requestJson: requestJson,
            progressJson: progressJson,
            resumeCount: resumeCount,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TasksTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TasksTable,
    Task,
    $$TasksTableFilterComposer,
    $$TasksTableOrderingComposer,
    $$TasksTableAnnotationComposer,
    $$TasksTableCreateCompanionBuilder,
    $$TasksTableUpdateCompanionBuilder,
    (Task, BaseReferences<_$AppDatabase, $TasksTable, Task>),
    Task,
    PrefetchHooks Function()>;
typedef $$SyncMetaTableCreateCompanionBuilder = SyncMetaCompanion Function({
  required String objectId,
  required String table,
  required String rowJson,
  Value<int> version,
  Value<bool> dirty,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$SyncMetaTableUpdateCompanionBuilder = SyncMetaCompanion Function({
  Value<String> objectId,
  Value<String> table,
  Value<String> rowJson,
  Value<int> version,
  Value<bool> dirty,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$SyncMetaTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get objectId => $composableBuilder(
      column: $table.objectId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get table => $composableBuilder(
      column: $table.table, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rowJson => $composableBuilder(
      column: $table.rowJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get dirty => $composableBuilder(
      column: $table.dirty, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$SyncMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get objectId => $composableBuilder(
      column: $table.objectId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get table => $composableBuilder(
      column: $table.table, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rowJson => $composableBuilder(
      column: $table.rowJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get dirty => $composableBuilder(
      column: $table.dirty, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$SyncMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get objectId =>
      $composableBuilder(column: $table.objectId, builder: (column) => column);

  GeneratedColumn<String> get table =>
      $composableBuilder(column: $table.table, builder: (column) => column);

  GeneratedColumn<String> get rowJson =>
      $composableBuilder(column: $table.rowJson, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SyncMetaTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncMetaTable,
    SyncMetaData,
    $$SyncMetaTableFilterComposer,
    $$SyncMetaTableOrderingComposer,
    $$SyncMetaTableAnnotationComposer,
    $$SyncMetaTableCreateCompanionBuilder,
    $$SyncMetaTableUpdateCompanionBuilder,
    (SyncMetaData, BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaData>),
    SyncMetaData,
    PrefetchHooks Function()> {
  $$SyncMetaTableTableManager(_$AppDatabase db, $SyncMetaTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> objectId = const Value.absent(),
            Value<String> table = const Value.absent(),
            Value<String> rowJson = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<bool> dirty = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncMetaCompanion(
            objectId: objectId,
            table: table,
            rowJson: rowJson,
            version: version,
            dirty: dirty,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String objectId,
            required String table,
            required String rowJson,
            Value<int> version = const Value.absent(),
            Value<bool> dirty = const Value.absent(),
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncMetaCompanion.insert(
            objectId: objectId,
            table: table,
            rowJson: rowJson,
            version: version,
            dirty: dirty,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncMetaTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SyncMetaTable,
    SyncMetaData,
    $$SyncMetaTableFilterComposer,
    $$SyncMetaTableOrderingComposer,
    $$SyncMetaTableAnnotationComposer,
    $$SyncMetaTableCreateCompanionBuilder,
    $$SyncMetaTableUpdateCompanionBuilder,
    (SyncMetaData, BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaData>),
    SyncMetaData,
    PrefetchHooks Function()>;
typedef $$KnowledgeDocsTableCreateCompanionBuilder = KnowledgeDocsCompanion
    Function({
  required String id,
  required String name,
  required String sourceType,
  Value<int> chunkCount,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$KnowledgeDocsTableUpdateCompanionBuilder = KnowledgeDocsCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<String> sourceType,
  Value<int> chunkCount,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$KnowledgeDocsTableFilterComposer
    extends Composer<_$AppDatabase, $KnowledgeDocsTable> {
  $$KnowledgeDocsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceType => $composableBuilder(
      column: $table.sourceType, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get chunkCount => $composableBuilder(
      column: $table.chunkCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$KnowledgeDocsTableOrderingComposer
    extends Composer<_$AppDatabase, $KnowledgeDocsTable> {
  $$KnowledgeDocsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceType => $composableBuilder(
      column: $table.sourceType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get chunkCount => $composableBuilder(
      column: $table.chunkCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$KnowledgeDocsTableAnnotationComposer
    extends Composer<_$AppDatabase, $KnowledgeDocsTable> {
  $$KnowledgeDocsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get sourceType => $composableBuilder(
      column: $table.sourceType, builder: (column) => column);

  GeneratedColumn<int> get chunkCount => $composableBuilder(
      column: $table.chunkCount, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$KnowledgeDocsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $KnowledgeDocsTable,
    KnowledgeDoc,
    $$KnowledgeDocsTableFilterComposer,
    $$KnowledgeDocsTableOrderingComposer,
    $$KnowledgeDocsTableAnnotationComposer,
    $$KnowledgeDocsTableCreateCompanionBuilder,
    $$KnowledgeDocsTableUpdateCompanionBuilder,
    (
      KnowledgeDoc,
      BaseReferences<_$AppDatabase, $KnowledgeDocsTable, KnowledgeDoc>
    ),
    KnowledgeDoc,
    PrefetchHooks Function()> {
  $$KnowledgeDocsTableTableManager(_$AppDatabase db, $KnowledgeDocsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KnowledgeDocsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KnowledgeDocsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KnowledgeDocsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> sourceType = const Value.absent(),
            Value<int> chunkCount = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              KnowledgeDocsCompanion(
            id: id,
            name: name,
            sourceType: sourceType,
            chunkCount: chunkCount,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String sourceType,
            Value<int> chunkCount = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              KnowledgeDocsCompanion.insert(
            id: id,
            name: name,
            sourceType: sourceType,
            chunkCount: chunkCount,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$KnowledgeDocsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $KnowledgeDocsTable,
    KnowledgeDoc,
    $$KnowledgeDocsTableFilterComposer,
    $$KnowledgeDocsTableOrderingComposer,
    $$KnowledgeDocsTableAnnotationComposer,
    $$KnowledgeDocsTableCreateCompanionBuilder,
    $$KnowledgeDocsTableUpdateCompanionBuilder,
    (
      KnowledgeDoc,
      BaseReferences<_$AppDatabase, $KnowledgeDocsTable, KnowledgeDoc>
    ),
    KnowledgeDoc,
    PrefetchHooks Function()>;
typedef $$KnowledgeChunksTableCreateCompanionBuilder = KnowledgeChunksCompanion
    Function({
  required String id,
  required String docId,
  required String content,
  Value<String?> embeddingJson,
  required int index,
  Value<int> rowid,
});
typedef $$KnowledgeChunksTableUpdateCompanionBuilder = KnowledgeChunksCompanion
    Function({
  Value<String> id,
  Value<String> docId,
  Value<String> content,
  Value<String?> embeddingJson,
  Value<int> index,
  Value<int> rowid,
});

class $$KnowledgeChunksTableFilterComposer
    extends Composer<_$AppDatabase, $KnowledgeChunksTable> {
  $$KnowledgeChunksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get docId => $composableBuilder(
      column: $table.docId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get embeddingJson => $composableBuilder(
      column: $table.embeddingJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get index => $composableBuilder(
      column: $table.index, builder: (column) => ColumnFilters(column));
}

class $$KnowledgeChunksTableOrderingComposer
    extends Composer<_$AppDatabase, $KnowledgeChunksTable> {
  $$KnowledgeChunksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get docId => $composableBuilder(
      column: $table.docId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get embeddingJson => $composableBuilder(
      column: $table.embeddingJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get index => $composableBuilder(
      column: $table.index, builder: (column) => ColumnOrderings(column));
}

class $$KnowledgeChunksTableAnnotationComposer
    extends Composer<_$AppDatabase, $KnowledgeChunksTable> {
  $$KnowledgeChunksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get docId =>
      $composableBuilder(column: $table.docId, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get embeddingJson => $composableBuilder(
      column: $table.embeddingJson, builder: (column) => column);

  GeneratedColumn<int> get index =>
      $composableBuilder(column: $table.index, builder: (column) => column);
}

class $$KnowledgeChunksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $KnowledgeChunksTable,
    KnowledgeChunk,
    $$KnowledgeChunksTableFilterComposer,
    $$KnowledgeChunksTableOrderingComposer,
    $$KnowledgeChunksTableAnnotationComposer,
    $$KnowledgeChunksTableCreateCompanionBuilder,
    $$KnowledgeChunksTableUpdateCompanionBuilder,
    (
      KnowledgeChunk,
      BaseReferences<_$AppDatabase, $KnowledgeChunksTable, KnowledgeChunk>
    ),
    KnowledgeChunk,
    PrefetchHooks Function()> {
  $$KnowledgeChunksTableTableManager(
      _$AppDatabase db, $KnowledgeChunksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KnowledgeChunksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KnowledgeChunksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KnowledgeChunksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> docId = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<String?> embeddingJson = const Value.absent(),
            Value<int> index = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              KnowledgeChunksCompanion(
            id: id,
            docId: docId,
            content: content,
            embeddingJson: embeddingJson,
            index: index,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String docId,
            required String content,
            Value<String?> embeddingJson = const Value.absent(),
            required int index,
            Value<int> rowid = const Value.absent(),
          }) =>
              KnowledgeChunksCompanion.insert(
            id: id,
            docId: docId,
            content: content,
            embeddingJson: embeddingJson,
            index: index,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$KnowledgeChunksTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $KnowledgeChunksTable,
    KnowledgeChunk,
    $$KnowledgeChunksTableFilterComposer,
    $$KnowledgeChunksTableOrderingComposer,
    $$KnowledgeChunksTableAnnotationComposer,
    $$KnowledgeChunksTableCreateCompanionBuilder,
    $$KnowledgeChunksTableUpdateCompanionBuilder,
    (
      KnowledgeChunk,
      BaseReferences<_$AppDatabase, $KnowledgeChunksTable, KnowledgeChunk>
    ),
    KnowledgeChunk,
    PrefetchHooks Function()>;
typedef $$ScheduledTasksTableCreateCompanionBuilder = ScheduledTasksCompanion
    Function({
  required String id,
  required String name,
  required String prompt,
  required String cron,
  Value<String?> agentId,
  Value<bool> enabled,
  Value<String?> lastResult,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$ScheduledTasksTableUpdateCompanionBuilder = ScheduledTasksCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<String> prompt,
  Value<String> cron,
  Value<String?> agentId,
  Value<bool> enabled,
  Value<String?> lastResult,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$ScheduledTasksTableFilterComposer
    extends Composer<_$AppDatabase, $ScheduledTasksTable> {
  $$ScheduledTasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get prompt => $composableBuilder(
      column: $table.prompt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cron => $composableBuilder(
      column: $table.cron, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get agentId => $composableBuilder(
      column: $table.agentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastResult => $composableBuilder(
      column: $table.lastResult, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$ScheduledTasksTableOrderingComposer
    extends Composer<_$AppDatabase, $ScheduledTasksTable> {
  $$ScheduledTasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get prompt => $composableBuilder(
      column: $table.prompt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cron => $composableBuilder(
      column: $table.cron, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get agentId => $composableBuilder(
      column: $table.agentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastResult => $composableBuilder(
      column: $table.lastResult, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$ScheduledTasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScheduledTasksTable> {
  $$ScheduledTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get prompt =>
      $composableBuilder(column: $table.prompt, builder: (column) => column);

  GeneratedColumn<String> get cron =>
      $composableBuilder(column: $table.cron, builder: (column) => column);

  GeneratedColumn<String> get agentId =>
      $composableBuilder(column: $table.agentId, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<String> get lastResult => $composableBuilder(
      column: $table.lastResult, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ScheduledTasksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ScheduledTasksTable,
    ScheduledTask,
    $$ScheduledTasksTableFilterComposer,
    $$ScheduledTasksTableOrderingComposer,
    $$ScheduledTasksTableAnnotationComposer,
    $$ScheduledTasksTableCreateCompanionBuilder,
    $$ScheduledTasksTableUpdateCompanionBuilder,
    (
      ScheduledTask,
      BaseReferences<_$AppDatabase, $ScheduledTasksTable, ScheduledTask>
    ),
    ScheduledTask,
    PrefetchHooks Function()> {
  $$ScheduledTasksTableTableManager(
      _$AppDatabase db, $ScheduledTasksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScheduledTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ScheduledTasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScheduledTasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> prompt = const Value.absent(),
            Value<String> cron = const Value.absent(),
            Value<String?> agentId = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<String?> lastResult = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ScheduledTasksCompanion(
            id: id,
            name: name,
            prompt: prompt,
            cron: cron,
            agentId: agentId,
            enabled: enabled,
            lastResult: lastResult,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String prompt,
            required String cron,
            Value<String?> agentId = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<String?> lastResult = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ScheduledTasksCompanion.insert(
            id: id,
            name: name,
            prompt: prompt,
            cron: cron,
            agentId: agentId,
            enabled: enabled,
            lastResult: lastResult,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ScheduledTasksTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ScheduledTasksTable,
    ScheduledTask,
    $$ScheduledTasksTableFilterComposer,
    $$ScheduledTasksTableOrderingComposer,
    $$ScheduledTasksTableAnnotationComposer,
    $$ScheduledTasksTableCreateCompanionBuilder,
    $$ScheduledTasksTableUpdateCompanionBuilder,
    (
      ScheduledTask,
      BaseReferences<_$AppDatabase, $ScheduledTasksTable, ScheduledTask>
    ),
    ScheduledTask,
    PrefetchHooks Function()>;
typedef $$AuditLogsTableCreateCompanionBuilder = AuditLogsCompanion Function({
  required String id,
  Value<String?> conversationId,
  required String type,
  required String detail,
  Value<String?> decision,
  Value<String?> risk,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$AuditLogsTableUpdateCompanionBuilder = AuditLogsCompanion Function({
  Value<String> id,
  Value<String?> conversationId,
  Value<String> type,
  Value<String> detail,
  Value<String?> decision,
  Value<String?> risk,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$AuditLogsTableFilterComposer
    extends Composer<_$AppDatabase, $AuditLogsTable> {
  $$AuditLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get conversationId => $composableBuilder(
      column: $table.conversationId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get detail => $composableBuilder(
      column: $table.detail, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get decision => $composableBuilder(
      column: $table.decision, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get risk => $composableBuilder(
      column: $table.risk, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$AuditLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $AuditLogsTable> {
  $$AuditLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get conversationId => $composableBuilder(
      column: $table.conversationId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get detail => $composableBuilder(
      column: $table.detail, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get decision => $composableBuilder(
      column: $table.decision, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get risk => $composableBuilder(
      column: $table.risk, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$AuditLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AuditLogsTable> {
  $$AuditLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
      column: $table.conversationId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get detail =>
      $composableBuilder(column: $table.detail, builder: (column) => column);

  GeneratedColumn<String> get decision =>
      $composableBuilder(column: $table.decision, builder: (column) => column);

  GeneratedColumn<String> get risk =>
      $composableBuilder(column: $table.risk, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$AuditLogsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AuditLogsTable,
    AuditLog,
    $$AuditLogsTableFilterComposer,
    $$AuditLogsTableOrderingComposer,
    $$AuditLogsTableAnnotationComposer,
    $$AuditLogsTableCreateCompanionBuilder,
    $$AuditLogsTableUpdateCompanionBuilder,
    (AuditLog, BaseReferences<_$AppDatabase, $AuditLogsTable, AuditLog>),
    AuditLog,
    PrefetchHooks Function()> {
  $$AuditLogsTableTableManager(_$AppDatabase db, $AuditLogsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AuditLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AuditLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AuditLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String?> conversationId = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> detail = const Value.absent(),
            Value<String?> decision = const Value.absent(),
            Value<String?> risk = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AuditLogsCompanion(
            id: id,
            conversationId: conversationId,
            type: type,
            detail: detail,
            decision: decision,
            risk: risk,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String?> conversationId = const Value.absent(),
            required String type,
            required String detail,
            Value<String?> decision = const Value.absent(),
            Value<String?> risk = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              AuditLogsCompanion.insert(
            id: id,
            conversationId: conversationId,
            type: type,
            detail: detail,
            decision: decision,
            risk: risk,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AuditLogsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AuditLogsTable,
    AuditLog,
    $$AuditLogsTableFilterComposer,
    $$AuditLogsTableOrderingComposer,
    $$AuditLogsTableAnnotationComposer,
    $$AuditLogsTableCreateCompanionBuilder,
    $$AuditLogsTableUpdateCompanionBuilder,
    (AuditLog, BaseReferences<_$AppDatabase, $AuditLogsTable, AuditLog>),
    AuditLog,
    PrefetchHooks Function()>;
typedef $$PluginsTableCreateCompanionBuilder = PluginsCompanion Function({
  required String id,
  required String name,
  required String kind,
  required String manifestJson,
  Value<String> version,
  Value<bool> enabled,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$PluginsTableUpdateCompanionBuilder = PluginsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> kind,
  Value<String> manifestJson,
  Value<String> version,
  Value<bool> enabled,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$PluginsTableFilterComposer
    extends Composer<_$AppDatabase, $PluginsTable> {
  $$PluginsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get manifestJson => $composableBuilder(
      column: $table.manifestJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$PluginsTableOrderingComposer
    extends Composer<_$AppDatabase, $PluginsTable> {
  $$PluginsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get manifestJson => $composableBuilder(
      column: $table.manifestJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$PluginsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PluginsTable> {
  $$PluginsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get manifestJson => $composableBuilder(
      column: $table.manifestJson, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$PluginsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PluginsTable,
    Plugin,
    $$PluginsTableFilterComposer,
    $$PluginsTableOrderingComposer,
    $$PluginsTableAnnotationComposer,
    $$PluginsTableCreateCompanionBuilder,
    $$PluginsTableUpdateCompanionBuilder,
    (Plugin, BaseReferences<_$AppDatabase, $PluginsTable, Plugin>),
    Plugin,
    PrefetchHooks Function()> {
  $$PluginsTableTableManager(_$AppDatabase db, $PluginsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PluginsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PluginsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PluginsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> kind = const Value.absent(),
            Value<String> manifestJson = const Value.absent(),
            Value<String> version = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PluginsCompanion(
            id: id,
            name: name,
            kind: kind,
            manifestJson: manifestJson,
            version: version,
            enabled: enabled,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String kind,
            required String manifestJson,
            Value<String> version = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              PluginsCompanion.insert(
            id: id,
            name: name,
            kind: kind,
            manifestJson: manifestJson,
            version: version,
            enabled: enabled,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PluginsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PluginsTable,
    Plugin,
    $$PluginsTableFilterComposer,
    $$PluginsTableOrderingComposer,
    $$PluginsTableAnnotationComposer,
    $$PluginsTableCreateCompanionBuilder,
    $$PluginsTableUpdateCompanionBuilder,
    (Plugin, BaseReferences<_$AppDatabase, $PluginsTable, Plugin>),
    Plugin,
    PrefetchHooks Function()>;
typedef $$SkillPacksTableCreateCompanionBuilder = SkillPacksCompanion Function({
  required String id,
  required String name,
  required String description,
  Value<String?> author,
  Value<String> version,
  required String source,
  required String repo,
  required String ref,
  Value<String?> subPath,
  required String installRoot,
  Value<String> fileListJson,
  Value<bool> enabled,
  required DateTime installedAt,
  required DateTime updatedAt,
  required String sha256,
  Value<int> rowid,
});
typedef $$SkillPacksTableUpdateCompanionBuilder = SkillPacksCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> description,
  Value<String?> author,
  Value<String> version,
  Value<String> source,
  Value<String> repo,
  Value<String> ref,
  Value<String?> subPath,
  Value<String> installRoot,
  Value<String> fileListJson,
  Value<bool> enabled,
  Value<DateTime> installedAt,
  Value<DateTime> updatedAt,
  Value<String> sha256,
  Value<int> rowid,
});

class $$SkillPacksTableFilterComposer
    extends Composer<_$AppDatabase, $SkillPacksTable> {
  $$SkillPacksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get author => $composableBuilder(
      column: $table.author, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get repo => $composableBuilder(
      column: $table.repo, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ref => $composableBuilder(
      column: $table.ref, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get subPath => $composableBuilder(
      column: $table.subPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get installRoot => $composableBuilder(
      column: $table.installRoot, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fileListJson => $composableBuilder(
      column: $table.fileListJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get installedAt => $composableBuilder(
      column: $table.installedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sha256 => $composableBuilder(
      column: $table.sha256, builder: (column) => ColumnFilters(column));
}

class $$SkillPacksTableOrderingComposer
    extends Composer<_$AppDatabase, $SkillPacksTable> {
  $$SkillPacksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get author => $composableBuilder(
      column: $table.author, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get repo => $composableBuilder(
      column: $table.repo, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ref => $composableBuilder(
      column: $table.ref, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get subPath => $composableBuilder(
      column: $table.subPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get installRoot => $composableBuilder(
      column: $table.installRoot, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fileListJson => $composableBuilder(
      column: $table.fileListJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get installedAt => $composableBuilder(
      column: $table.installedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sha256 => $composableBuilder(
      column: $table.sha256, builder: (column) => ColumnOrderings(column));
}

class $$SkillPacksTableAnnotationComposer
    extends Composer<_$AppDatabase, $SkillPacksTable> {
  $$SkillPacksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get repo =>
      $composableBuilder(column: $table.repo, builder: (column) => column);

  GeneratedColumn<String> get ref =>
      $composableBuilder(column: $table.ref, builder: (column) => column);

  GeneratedColumn<String> get subPath =>
      $composableBuilder(column: $table.subPath, builder: (column) => column);

  GeneratedColumn<String> get installRoot => $composableBuilder(
      column: $table.installRoot, builder: (column) => column);

  GeneratedColumn<String> get fileListJson => $composableBuilder(
      column: $table.fileListJson, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<DateTime> get installedAt => $composableBuilder(
      column: $table.installedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);
}

class $$SkillPacksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SkillPacksTable,
    SkillPack,
    $$SkillPacksTableFilterComposer,
    $$SkillPacksTableOrderingComposer,
    $$SkillPacksTableAnnotationComposer,
    $$SkillPacksTableCreateCompanionBuilder,
    $$SkillPacksTableUpdateCompanionBuilder,
    (SkillPack, BaseReferences<_$AppDatabase, $SkillPacksTable, SkillPack>),
    SkillPack,
    PrefetchHooks Function()> {
  $$SkillPacksTableTableManager(_$AppDatabase db, $SkillPacksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SkillPacksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SkillPacksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SkillPacksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<String?> author = const Value.absent(),
            Value<String> version = const Value.absent(),
            Value<String> source = const Value.absent(),
            Value<String> repo = const Value.absent(),
            Value<String> ref = const Value.absent(),
            Value<String?> subPath = const Value.absent(),
            Value<String> installRoot = const Value.absent(),
            Value<String> fileListJson = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<DateTime> installedAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<String> sha256 = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SkillPacksCompanion(
            id: id,
            name: name,
            description: description,
            author: author,
            version: version,
            source: source,
            repo: repo,
            ref: ref,
            subPath: subPath,
            installRoot: installRoot,
            fileListJson: fileListJson,
            enabled: enabled,
            installedAt: installedAt,
            updatedAt: updatedAt,
            sha256: sha256,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String description,
            Value<String?> author = const Value.absent(),
            Value<String> version = const Value.absent(),
            required String source,
            required String repo,
            required String ref,
            Value<String?> subPath = const Value.absent(),
            required String installRoot,
            Value<String> fileListJson = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            required DateTime installedAt,
            required DateTime updatedAt,
            required String sha256,
            Value<int> rowid = const Value.absent(),
          }) =>
              SkillPacksCompanion.insert(
            id: id,
            name: name,
            description: description,
            author: author,
            version: version,
            source: source,
            repo: repo,
            ref: ref,
            subPath: subPath,
            installRoot: installRoot,
            fileListJson: fileListJson,
            enabled: enabled,
            installedAt: installedAt,
            updatedAt: updatedAt,
            sha256: sha256,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SkillPacksTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SkillPacksTable,
    SkillPack,
    $$SkillPacksTableFilterComposer,
    $$SkillPacksTableOrderingComposer,
    $$SkillPacksTableAnnotationComposer,
    $$SkillPacksTableCreateCompanionBuilder,
    $$SkillPacksTableUpdateCompanionBuilder,
    (SkillPack, BaseReferences<_$AppDatabase, $SkillPacksTable, SkillPack>),
    SkillPack,
    PrefetchHooks Function()>;
typedef $$McpServersTableCreateCompanionBuilder = McpServersCompanion Function({
  required String id,
  required String name,
  required String kind,
  Value<String?> url,
  Value<String?> command,
  Value<String> args,
  Value<bool> enabled,
  Value<int> rowid,
});
typedef $$McpServersTableUpdateCompanionBuilder = McpServersCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> kind,
  Value<String?> url,
  Value<String?> command,
  Value<String> args,
  Value<bool> enabled,
  Value<int> rowid,
});

class $$McpServersTableFilterComposer
    extends Composer<_$AppDatabase, $McpServersTable> {
  $$McpServersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get url => $composableBuilder(
      column: $table.url, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get command => $composableBuilder(
      column: $table.command, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get args => $composableBuilder(
      column: $table.args, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));
}

class $$McpServersTableOrderingComposer
    extends Composer<_$AppDatabase, $McpServersTable> {
  $$McpServersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get url => $composableBuilder(
      column: $table.url, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get command => $composableBuilder(
      column: $table.command, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get args => $composableBuilder(
      column: $table.args, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));
}

class $$McpServersTableAnnotationComposer
    extends Composer<_$AppDatabase, $McpServersTable> {
  $$McpServersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get command =>
      $composableBuilder(column: $table.command, builder: (column) => column);

  GeneratedColumn<String> get args =>
      $composableBuilder(column: $table.args, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);
}

class $$McpServersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $McpServersTable,
    McpServer,
    $$McpServersTableFilterComposer,
    $$McpServersTableOrderingComposer,
    $$McpServersTableAnnotationComposer,
    $$McpServersTableCreateCompanionBuilder,
    $$McpServersTableUpdateCompanionBuilder,
    (McpServer, BaseReferences<_$AppDatabase, $McpServersTable, McpServer>),
    McpServer,
    PrefetchHooks Function()> {
  $$McpServersTableTableManager(_$AppDatabase db, $McpServersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$McpServersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$McpServersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$McpServersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> kind = const Value.absent(),
            Value<String?> url = const Value.absent(),
            Value<String?> command = const Value.absent(),
            Value<String> args = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              McpServersCompanion(
            id: id,
            name: name,
            kind: kind,
            url: url,
            command: command,
            args: args,
            enabled: enabled,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String kind,
            Value<String?> url = const Value.absent(),
            Value<String?> command = const Value.absent(),
            Value<String> args = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              McpServersCompanion.insert(
            id: id,
            name: name,
            kind: kind,
            url: url,
            command: command,
            args: args,
            enabled: enabled,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$McpServersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $McpServersTable,
    McpServer,
    $$McpServersTableFilterComposer,
    $$McpServersTableOrderingComposer,
    $$McpServersTableAnnotationComposer,
    $$McpServersTableCreateCompanionBuilder,
    $$McpServersTableUpdateCompanionBuilder,
    (McpServer, BaseReferences<_$AppDatabase, $McpServersTable, McpServer>),
    McpServer,
    PrefetchHooks Function()>;
typedef $$AccountMetaTableCreateCompanionBuilder = AccountMetaCompanion
    Function({
  required String id,
  Value<String?> userId,
  Value<bool> isPro,
  Value<String> balanceCents,
  Value<String> configJson,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$AccountMetaTableUpdateCompanionBuilder = AccountMetaCompanion
    Function({
  Value<String> id,
  Value<String?> userId,
  Value<bool> isPro,
  Value<String> balanceCents,
  Value<String> configJson,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$AccountMetaTableFilterComposer
    extends Composer<_$AppDatabase, $AccountMetaTable> {
  $$AccountMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isPro => $composableBuilder(
      column: $table.isPro, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get balanceCents => $composableBuilder(
      column: $table.balanceCents, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get configJson => $composableBuilder(
      column: $table.configJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$AccountMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $AccountMetaTable> {
  $$AccountMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isPro => $composableBuilder(
      column: $table.isPro, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get balanceCents => $composableBuilder(
      column: $table.balanceCents,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get configJson => $composableBuilder(
      column: $table.configJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$AccountMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $AccountMetaTable> {
  $$AccountMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<bool> get isPro =>
      $composableBuilder(column: $table.isPro, builder: (column) => column);

  GeneratedColumn<String> get balanceCents => $composableBuilder(
      column: $table.balanceCents, builder: (column) => column);

  GeneratedColumn<String> get configJson => $composableBuilder(
      column: $table.configJson, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AccountMetaTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AccountMetaTable,
    AccountMetaData,
    $$AccountMetaTableFilterComposer,
    $$AccountMetaTableOrderingComposer,
    $$AccountMetaTableAnnotationComposer,
    $$AccountMetaTableCreateCompanionBuilder,
    $$AccountMetaTableUpdateCompanionBuilder,
    (
      AccountMetaData,
      BaseReferences<_$AppDatabase, $AccountMetaTable, AccountMetaData>
    ),
    AccountMetaData,
    PrefetchHooks Function()> {
  $$AccountMetaTableTableManager(_$AppDatabase db, $AccountMetaTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AccountMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AccountMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AccountMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String?> userId = const Value.absent(),
            Value<bool> isPro = const Value.absent(),
            Value<String> balanceCents = const Value.absent(),
            Value<String> configJson = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AccountMetaCompanion(
            id: id,
            userId: userId,
            isPro: isPro,
            balanceCents: balanceCents,
            configJson: configJson,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String?> userId = const Value.absent(),
            Value<bool> isPro = const Value.absent(),
            Value<String> balanceCents = const Value.absent(),
            Value<String> configJson = const Value.absent(),
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              AccountMetaCompanion.insert(
            id: id,
            userId: userId,
            isPro: isPro,
            balanceCents: balanceCents,
            configJson: configJson,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AccountMetaTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AccountMetaTable,
    AccountMetaData,
    $$AccountMetaTableFilterComposer,
    $$AccountMetaTableOrderingComposer,
    $$AccountMetaTableAnnotationComposer,
    $$AccountMetaTableCreateCompanionBuilder,
    $$AccountMetaTableUpdateCompanionBuilder,
    (
      AccountMetaData,
      BaseReferences<_$AppDatabase, $AccountMetaTable, AccountMetaData>
    ),
    AccountMetaData,
    PrefetchHooks Function()>;
typedef $$RunRecordsTableCreateCompanionBuilder = RunRecordsCompanion Function({
  required String runId,
  required String conversationId,
  Value<String> model,
  Value<String> status,
  required DateTime startedAt,
  Value<DateTime?> endedAt,
  Value<int> inputTokens,
  Value<int> outputTokens,
  Value<int> cachedTokens,
  Value<int?> estimatedCostCents,
  Value<int> eventCount,
  Value<int?> totalDurationMs,
  Value<int> retryCount,
  Value<int?> firstTokenDurationMs,
  Value<int> rowid,
});
typedef $$RunRecordsTableUpdateCompanionBuilder = RunRecordsCompanion Function({
  Value<String> runId,
  Value<String> conversationId,
  Value<String> model,
  Value<String> status,
  Value<DateTime> startedAt,
  Value<DateTime?> endedAt,
  Value<int> inputTokens,
  Value<int> outputTokens,
  Value<int> cachedTokens,
  Value<int?> estimatedCostCents,
  Value<int> eventCount,
  Value<int?> totalDurationMs,
  Value<int> retryCount,
  Value<int?> firstTokenDurationMs,
  Value<int> rowid,
});

class $$RunRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $RunRecordsTable> {
  $$RunRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get runId => $composableBuilder(
      column: $table.runId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get conversationId => $composableBuilder(
      column: $table.conversationId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get model => $composableBuilder(
      column: $table.model, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
      column: $table.endedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get inputTokens => $composableBuilder(
      column: $table.inputTokens, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get outputTokens => $composableBuilder(
      column: $table.outputTokens, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get cachedTokens => $composableBuilder(
      column: $table.cachedTokens, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get estimatedCostCents => $composableBuilder(
      column: $table.estimatedCostCents,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get eventCount => $composableBuilder(
      column: $table.eventCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get totalDurationMs => $composableBuilder(
      column: $table.totalDurationMs,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get firstTokenDurationMs => $composableBuilder(
      column: $table.firstTokenDurationMs,
      builder: (column) => ColumnFilters(column));
}

class $$RunRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $RunRecordsTable> {
  $$RunRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get runId => $composableBuilder(
      column: $table.runId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get conversationId => $composableBuilder(
      column: $table.conversationId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get model => $composableBuilder(
      column: $table.model, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
      column: $table.endedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get inputTokens => $composableBuilder(
      column: $table.inputTokens, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get outputTokens => $composableBuilder(
      column: $table.outputTokens,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get cachedTokens => $composableBuilder(
      column: $table.cachedTokens,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get estimatedCostCents => $composableBuilder(
      column: $table.estimatedCostCents,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get eventCount => $composableBuilder(
      column: $table.eventCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get totalDurationMs => $composableBuilder(
      column: $table.totalDurationMs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get firstTokenDurationMs => $composableBuilder(
      column: $table.firstTokenDurationMs,
      builder: (column) => ColumnOrderings(column));
}

class $$RunRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RunRecordsTable> {
  $$RunRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get runId =>
      $composableBuilder(column: $table.runId, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
      column: $table.conversationId, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<int> get inputTokens => $composableBuilder(
      column: $table.inputTokens, builder: (column) => column);

  GeneratedColumn<int> get outputTokens => $composableBuilder(
      column: $table.outputTokens, builder: (column) => column);

  GeneratedColumn<int> get cachedTokens => $composableBuilder(
      column: $table.cachedTokens, builder: (column) => column);

  GeneratedColumn<int> get estimatedCostCents => $composableBuilder(
      column: $table.estimatedCostCents, builder: (column) => column);

  GeneratedColumn<int> get eventCount => $composableBuilder(
      column: $table.eventCount, builder: (column) => column);

  GeneratedColumn<int> get totalDurationMs => $composableBuilder(
      column: $table.totalDurationMs, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => column);

  GeneratedColumn<int> get firstTokenDurationMs => $composableBuilder(
      column: $table.firstTokenDurationMs, builder: (column) => column);
}

class $$RunRecordsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RunRecordsTable,
    RunRecord,
    $$RunRecordsTableFilterComposer,
    $$RunRecordsTableOrderingComposer,
    $$RunRecordsTableAnnotationComposer,
    $$RunRecordsTableCreateCompanionBuilder,
    $$RunRecordsTableUpdateCompanionBuilder,
    (RunRecord, BaseReferences<_$AppDatabase, $RunRecordsTable, RunRecord>),
    RunRecord,
    PrefetchHooks Function()> {
  $$RunRecordsTableTableManager(_$AppDatabase db, $RunRecordsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RunRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RunRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RunRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> runId = const Value.absent(),
            Value<String> conversationId = const Value.absent(),
            Value<String> model = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<DateTime> startedAt = const Value.absent(),
            Value<DateTime?> endedAt = const Value.absent(),
            Value<int> inputTokens = const Value.absent(),
            Value<int> outputTokens = const Value.absent(),
            Value<int> cachedTokens = const Value.absent(),
            Value<int?> estimatedCostCents = const Value.absent(),
            Value<int> eventCount = const Value.absent(),
            Value<int?> totalDurationMs = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            Value<int?> firstTokenDurationMs = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RunRecordsCompanion(
            runId: runId,
            conversationId: conversationId,
            model: model,
            status: status,
            startedAt: startedAt,
            endedAt: endedAt,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedTokens: cachedTokens,
            estimatedCostCents: estimatedCostCents,
            eventCount: eventCount,
            totalDurationMs: totalDurationMs,
            retryCount: retryCount,
            firstTokenDurationMs: firstTokenDurationMs,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String runId,
            required String conversationId,
            Value<String> model = const Value.absent(),
            Value<String> status = const Value.absent(),
            required DateTime startedAt,
            Value<DateTime?> endedAt = const Value.absent(),
            Value<int> inputTokens = const Value.absent(),
            Value<int> outputTokens = const Value.absent(),
            Value<int> cachedTokens = const Value.absent(),
            Value<int?> estimatedCostCents = const Value.absent(),
            Value<int> eventCount = const Value.absent(),
            Value<int?> totalDurationMs = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            Value<int?> firstTokenDurationMs = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RunRecordsCompanion.insert(
            runId: runId,
            conversationId: conversationId,
            model: model,
            status: status,
            startedAt: startedAt,
            endedAt: endedAt,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedTokens: cachedTokens,
            estimatedCostCents: estimatedCostCents,
            eventCount: eventCount,
            totalDurationMs: totalDurationMs,
            retryCount: retryCount,
            firstTokenDurationMs: firstTokenDurationMs,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$RunRecordsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $RunRecordsTable,
    RunRecord,
    $$RunRecordsTableFilterComposer,
    $$RunRecordsTableOrderingComposer,
    $$RunRecordsTableAnnotationComposer,
    $$RunRecordsTableCreateCompanionBuilder,
    $$RunRecordsTableUpdateCompanionBuilder,
    (RunRecord, BaseReferences<_$AppDatabase, $RunRecordsTable, RunRecord>),
    RunRecord,
    PrefetchHooks Function()>;
typedef $$RunEventsTableCreateCompanionBuilder = RunEventsCompanion Function({
  required String eventId,
  required String runId,
  required int sequenceNo,
  required String type,
  required String status,
  required String name,
  required DateTime startedAt,
  Value<DateTime?> endedAt,
  Value<int?> durationMs,
  Value<String?> inputSummary,
  Value<String?> outputSummary,
  Value<String> metadataJson,
  Value<int> rowid,
});
typedef $$RunEventsTableUpdateCompanionBuilder = RunEventsCompanion Function({
  Value<String> eventId,
  Value<String> runId,
  Value<int> sequenceNo,
  Value<String> type,
  Value<String> status,
  Value<String> name,
  Value<DateTime> startedAt,
  Value<DateTime?> endedAt,
  Value<int?> durationMs,
  Value<String?> inputSummary,
  Value<String?> outputSummary,
  Value<String> metadataJson,
  Value<int> rowid,
});

class $$RunEventsTableFilterComposer
    extends Composer<_$AppDatabase, $RunEventsTable> {
  $$RunEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get eventId => $composableBuilder(
      column: $table.eventId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get runId => $composableBuilder(
      column: $table.runId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sequenceNo => $composableBuilder(
      column: $table.sequenceNo, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
      column: $table.endedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get inputSummary => $composableBuilder(
      column: $table.inputSummary, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get outputSummary => $composableBuilder(
      column: $table.outputSummary, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get metadataJson => $composableBuilder(
      column: $table.metadataJson, builder: (column) => ColumnFilters(column));
}

class $$RunEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $RunEventsTable> {
  $$RunEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get eventId => $composableBuilder(
      column: $table.eventId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get runId => $composableBuilder(
      column: $table.runId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sequenceNo => $composableBuilder(
      column: $table.sequenceNo, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
      column: $table.endedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get inputSummary => $composableBuilder(
      column: $table.inputSummary,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get outputSummary => $composableBuilder(
      column: $table.outputSummary,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get metadataJson => $composableBuilder(
      column: $table.metadataJson,
      builder: (column) => ColumnOrderings(column));
}

class $$RunEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RunEventsTable> {
  $$RunEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get runId =>
      $composableBuilder(column: $table.runId, builder: (column) => column);

  GeneratedColumn<int> get sequenceNo => $composableBuilder(
      column: $table.sequenceNo, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => column);

  GeneratedColumn<String> get inputSummary => $composableBuilder(
      column: $table.inputSummary, builder: (column) => column);

  GeneratedColumn<String> get outputSummary => $composableBuilder(
      column: $table.outputSummary, builder: (column) => column);

  GeneratedColumn<String> get metadataJson => $composableBuilder(
      column: $table.metadataJson, builder: (column) => column);
}

class $$RunEventsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RunEventsTable,
    RunEvent,
    $$RunEventsTableFilterComposer,
    $$RunEventsTableOrderingComposer,
    $$RunEventsTableAnnotationComposer,
    $$RunEventsTableCreateCompanionBuilder,
    $$RunEventsTableUpdateCompanionBuilder,
    (RunEvent, BaseReferences<_$AppDatabase, $RunEventsTable, RunEvent>),
    RunEvent,
    PrefetchHooks Function()> {
  $$RunEventsTableTableManager(_$AppDatabase db, $RunEventsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RunEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RunEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RunEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> eventId = const Value.absent(),
            Value<String> runId = const Value.absent(),
            Value<int> sequenceNo = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<DateTime> startedAt = const Value.absent(),
            Value<DateTime?> endedAt = const Value.absent(),
            Value<int?> durationMs = const Value.absent(),
            Value<String?> inputSummary = const Value.absent(),
            Value<String?> outputSummary = const Value.absent(),
            Value<String> metadataJson = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RunEventsCompanion(
            eventId: eventId,
            runId: runId,
            sequenceNo: sequenceNo,
            type: type,
            status: status,
            name: name,
            startedAt: startedAt,
            endedAt: endedAt,
            durationMs: durationMs,
            inputSummary: inputSummary,
            outputSummary: outputSummary,
            metadataJson: metadataJson,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String eventId,
            required String runId,
            required int sequenceNo,
            required String type,
            required String status,
            required String name,
            required DateTime startedAt,
            Value<DateTime?> endedAt = const Value.absent(),
            Value<int?> durationMs = const Value.absent(),
            Value<String?> inputSummary = const Value.absent(),
            Value<String?> outputSummary = const Value.absent(),
            Value<String> metadataJson = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RunEventsCompanion.insert(
            eventId: eventId,
            runId: runId,
            sequenceNo: sequenceNo,
            type: type,
            status: status,
            name: name,
            startedAt: startedAt,
            endedAt: endedAt,
            durationMs: durationMs,
            inputSummary: inputSummary,
            outputSummary: outputSummary,
            metadataJson: metadataJson,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$RunEventsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $RunEventsTable,
    RunEvent,
    $$RunEventsTableFilterComposer,
    $$RunEventsTableOrderingComposer,
    $$RunEventsTableAnnotationComposer,
    $$RunEventsTableCreateCompanionBuilder,
    $$RunEventsTableUpdateCompanionBuilder,
    (RunEvent, BaseReferences<_$AppDatabase, $RunEventsTable, RunEvent>),
    RunEvent,
    PrefetchHooks Function()>;
typedef $$LogRecordsTableCreateCompanionBuilder = LogRecordsCompanion Function({
  required String logId,
  Value<String?> runId,
  Value<String?> eventId,
  required String level,
  required String category,
  required String message,
  Value<String?> detailJson,
  Value<String?> errorCode,
  Value<String?> stackTrace,
  required DateTime createdAt,
  Value<bool> retryable,
  Value<int> rowid,
});
typedef $$LogRecordsTableUpdateCompanionBuilder = LogRecordsCompanion Function({
  Value<String> logId,
  Value<String?> runId,
  Value<String?> eventId,
  Value<String> level,
  Value<String> category,
  Value<String> message,
  Value<String?> detailJson,
  Value<String?> errorCode,
  Value<String?> stackTrace,
  Value<DateTime> createdAt,
  Value<bool> retryable,
  Value<int> rowid,
});

class $$LogRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $LogRecordsTable> {
  $$LogRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get logId => $composableBuilder(
      column: $table.logId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get runId => $composableBuilder(
      column: $table.runId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get eventId => $composableBuilder(
      column: $table.eventId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get level => $composableBuilder(
      column: $table.level, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get message => $composableBuilder(
      column: $table.message, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get detailJson => $composableBuilder(
      column: $table.detailJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get errorCode => $composableBuilder(
      column: $table.errorCode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get stackTrace => $composableBuilder(
      column: $table.stackTrace, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get retryable => $composableBuilder(
      column: $table.retryable, builder: (column) => ColumnFilters(column));
}

class $$LogRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $LogRecordsTable> {
  $$LogRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get logId => $composableBuilder(
      column: $table.logId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get runId => $composableBuilder(
      column: $table.runId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get eventId => $composableBuilder(
      column: $table.eventId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get level => $composableBuilder(
      column: $table.level, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get message => $composableBuilder(
      column: $table.message, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get detailJson => $composableBuilder(
      column: $table.detailJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get errorCode => $composableBuilder(
      column: $table.errorCode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get stackTrace => $composableBuilder(
      column: $table.stackTrace, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get retryable => $composableBuilder(
      column: $table.retryable, builder: (column) => ColumnOrderings(column));
}

class $$LogRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LogRecordsTable> {
  $$LogRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get logId =>
      $composableBuilder(column: $table.logId, builder: (column) => column);

  GeneratedColumn<String> get runId =>
      $composableBuilder(column: $table.runId, builder: (column) => column);

  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<String> get detailJson => $composableBuilder(
      column: $table.detailJson, builder: (column) => column);

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);

  GeneratedColumn<String> get stackTrace => $composableBuilder(
      column: $table.stackTrace, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get retryable =>
      $composableBuilder(column: $table.retryable, builder: (column) => column);
}

class $$LogRecordsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LogRecordsTable,
    LogRecord,
    $$LogRecordsTableFilterComposer,
    $$LogRecordsTableOrderingComposer,
    $$LogRecordsTableAnnotationComposer,
    $$LogRecordsTableCreateCompanionBuilder,
    $$LogRecordsTableUpdateCompanionBuilder,
    (LogRecord, BaseReferences<_$AppDatabase, $LogRecordsTable, LogRecord>),
    LogRecord,
    PrefetchHooks Function()> {
  $$LogRecordsTableTableManager(_$AppDatabase db, $LogRecordsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LogRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LogRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LogRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> logId = const Value.absent(),
            Value<String?> runId = const Value.absent(),
            Value<String?> eventId = const Value.absent(),
            Value<String> level = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<String> message = const Value.absent(),
            Value<String?> detailJson = const Value.absent(),
            Value<String?> errorCode = const Value.absent(),
            Value<String?> stackTrace = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<bool> retryable = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LogRecordsCompanion(
            logId: logId,
            runId: runId,
            eventId: eventId,
            level: level,
            category: category,
            message: message,
            detailJson: detailJson,
            errorCode: errorCode,
            stackTrace: stackTrace,
            createdAt: createdAt,
            retryable: retryable,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String logId,
            Value<String?> runId = const Value.absent(),
            Value<String?> eventId = const Value.absent(),
            required String level,
            required String category,
            required String message,
            Value<String?> detailJson = const Value.absent(),
            Value<String?> errorCode = const Value.absent(),
            Value<String?> stackTrace = const Value.absent(),
            required DateTime createdAt,
            Value<bool> retryable = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LogRecordsCompanion.insert(
            logId: logId,
            runId: runId,
            eventId: eventId,
            level: level,
            category: category,
            message: message,
            detailJson: detailJson,
            errorCode: errorCode,
            stackTrace: stackTrace,
            createdAt: createdAt,
            retryable: retryable,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LogRecordsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LogRecordsTable,
    LogRecord,
    $$LogRecordsTableFilterComposer,
    $$LogRecordsTableOrderingComposer,
    $$LogRecordsTableAnnotationComposer,
    $$LogRecordsTableCreateCompanionBuilder,
    $$LogRecordsTableUpdateCompanionBuilder,
    (LogRecord, BaseReferences<_$AppDatabase, $LogRecordsTable, LogRecord>),
    LogRecord,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db, _db.conversations);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$AgentsTableTableManager get agents =>
      $$AgentsTableTableManager(_db, _db.agents);
  $$PromptTemplatesTableTableManager get promptTemplates =>
      $$PromptTemplatesTableTableManager(_db, _db.promptTemplates);
  $$ModelProfilesTableTableManager get modelProfiles =>
      $$ModelProfilesTableTableManager(_db, _db.modelProfiles);
  $$MemoriesTableTableManager get memories =>
      $$MemoriesTableTableManager(_db, _db.memories);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$SyncMetaTableTableManager get syncMeta =>
      $$SyncMetaTableTableManager(_db, _db.syncMeta);
  $$KnowledgeDocsTableTableManager get knowledgeDocs =>
      $$KnowledgeDocsTableTableManager(_db, _db.knowledgeDocs);
  $$KnowledgeChunksTableTableManager get knowledgeChunks =>
      $$KnowledgeChunksTableTableManager(_db, _db.knowledgeChunks);
  $$ScheduledTasksTableTableManager get scheduledTasks =>
      $$ScheduledTasksTableTableManager(_db, _db.scheduledTasks);
  $$AuditLogsTableTableManager get auditLogs =>
      $$AuditLogsTableTableManager(_db, _db.auditLogs);
  $$PluginsTableTableManager get plugins =>
      $$PluginsTableTableManager(_db, _db.plugins);
  $$SkillPacksTableTableManager get skillPacks =>
      $$SkillPacksTableTableManager(_db, _db.skillPacks);
  $$McpServersTableTableManager get mcpServers =>
      $$McpServersTableTableManager(_db, _db.mcpServers);
  $$AccountMetaTableTableManager get accountMeta =>
      $$AccountMetaTableTableManager(_db, _db.accountMeta);
  $$RunRecordsTableTableManager get runRecords =>
      $$RunRecordsTableTableManager(_db, _db.runRecords);
  $$RunEventsTableTableManager get runEvents =>
      $$RunEventsTableTableManager(_db, _db.runEvents);
  $$LogRecordsTableTableManager get logRecords =>
      $$LogRecordsTableTableManager(_db, _db.logRecords);
}
