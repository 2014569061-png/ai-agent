/// F17 关联个人上下文的领域模型与纯逻辑。
///
/// 这一层刻意不依赖 Flutter 与 drift：实体、来源、确认状态和消歧规则都是
/// 纯数据 + 纯函数。这样既能在内存夹具里直接验证（见
/// `lib/debug/personal_context_checks.dart`），也避免 SQL 仓储细节反向污染
/// 领域层——注入给模型的判断标准（是否确认、是否过期、是否越权）必须与存储
/// 实现无关。
library;

/// 实体类型。
///
/// 枚举顺序即管理页的分组顺序：先"人/项目/文件"这类强指代对象，再"主题"，
/// 最后才是会过期的"临时事项"与兜底类型。
enum PersonalContextEntityKind {
  person('person', '人物'),
  project('project', '项目'),
  file('file', '文件'),
  topic('topic', '主题'),
  temporaryTask('temporary_task', '临时事项'),
  preference('preference', '偏好'),
  organization('organization', '组织'),
  other('other', '其他');

  const PersonalContextEntityKind(this.wireName, this.label);

  /// 落库与协议使用的稳定字符串。已有数据依赖它，不可修改。
  final String wireName;

  /// 面向用户的中文名称。
  final String label;

  /// 解析外部输入。未知类型返回 null，由调用方决定是否报 unsupported，
  /// 以免领域层把"协议不认识"和"数据损坏"混为一谈。
  static PersonalContextEntityKind? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toLowerCase().replaceAll('-', '_');
    for (final kind in values) {
      if (kind.wireName == normalized) return kind;
    }
    return null;
  }
}

/// 信息来源，决定一条上下文"能不能被当作事实召回"。
enum PersonalContextSource {
  /// 用户自己明确说过的内容，可直接作为事实。
  userExplicit('user_explicit', '用户明确陈述'),

  /// 从用户已授权资料中提取的内容，需要保留授权状态；授权被收回即不召回。
  authorizedMaterial('authorized_material', '授权资料提取'),

  /// 模型推断，只能作为待确认候选；不得自动升级为事实。
  inferred('inferred', '推测');

  const PersonalContextSource(this.wireName, this.label);

  final String wireName;
  final String label;

  bool get isSpeculative => this == inferred;

  bool get requiresAuthorization => this == authorizedMaterial;

  /// 解析外部输入；未知来源返回 null。
  static PersonalContextSource? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toLowerCase().replaceAll('-', '_');
    for (final source in values) {
      if (source.wireName == normalized) return source;
    }
    return null;
  }
}

/// 确认状态。只有 `confirmed` 才允许进入长期上下文注入。
enum PersonalContextConfirmation {
  unconfirmed('unconfirmed', '待确认'),
  confirmed('confirmed', '已确认');

  const PersonalContextConfirmation(this.wireName, this.label);

  final String wireName;
  final String label;

  static PersonalContextConfirmation? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toLowerCase();
    for (final confirmation in values) {
      if (confirmation.wireName == normalized) return confirmation;
    }
    return null;
  }
}

/// 授权状态。`revoked` 的条目保留下来只为可追溯，绝不参与召回。
enum PersonalContextAuthorization {
  notRequired('not_required', '无需授权'),
  granted('granted', '已授权'),
  revoked('revoked', '授权已收回');

  const PersonalContextAuthorization(this.wireName, this.label);

  final String wireName;
  final String label;

  bool get allowsRecall => this != revoked;

  static PersonalContextAuthorization? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toLowerCase().replaceAll('-', '_');
    for (final authorization in values) {
      if (authorization.wireName == normalized) return authorization;
    }
    return null;
  }
}

/// 条目的生命周期。遗忘后保留数据行以便审计，但不再被召回，也不再允许
/// 同一归一化键被自动写回。
enum PersonalContextLifecycle {
  active('active', '有效'),
  forgotten('forgotten', '已遗忘');

  const PersonalContextLifecycle(this.wireName, this.label);

  final String wireName;
  final String label;

  static PersonalContextLifecycle? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toLowerCase();
    for (final lifecycle in values) {
      if (lifecycle.wireName == normalized) return lifecycle;
    }
    return null;
  }
}

/// 遗忘/更正墓碑的原因。
///
/// 墓碑只记录"这个归一化键已经被处理过"，不记录内容，避免删除后原文又被
/// 墓碑自己留存一份。
enum PersonalContextTombstoneReason {
  forgotten('forgotten', '用户遗忘'),
  corrected('corrected', '已更正'),
  revoked('revoked', '授权收回');

  const PersonalContextTombstoneReason(this.wireName, this.label);

  final String wireName;
  final String label;

  static PersonalContextTombstoneReason? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toLowerCase();
    for (final reason in values) {
      if (reason.wireName == normalized) return reason;
    }
    return null;
  }
}

/// 消歧结果状态。
enum PersonalContextResolutionStatus {
  /// 唯一命中，可以安全使用。
  resolved,

  /// 有多个同分/近分候选，必须让用户选择，不得自动挑一个。
  ambiguous,

  /// 完全没匹配到。
  missing,

  /// 只匹配到已过期条目；过期事项不应被召回。
  expired,

  /// 命中墓碑：该条目已被遗忘/更正，禁止自动重新入库。
  blocked,

  /// 命中但来源/确认状态不允许（推测、未确认、授权收回或敏感动作）。
  unauthorized,
}

/// 可区分的错误码。服务层与界面都靠它决定文案与是否给候选。
enum PersonalContextErrorCode {
  /// 参数本身不合法（空标签、负预算等）。
  invalid,

  /// 协议层面不支持（未知实体类型/来源）。
  unsupported,

  /// 授权不足：资料授权被收回，或推测未被允许作为依据。
  unauthorized,

  /// 版本过期 / 事项已过期，需要用户刷新后重试。
  stale,

  /// 键冲突或指代歧义，需要用户选择。
  conflict,

  /// 目标不存在。
  notFound,

  /// 被墓碑拦截，禁止自动重新入库。
  blocked,
}

/// 领域异常。`candidates` 用于把歧义候选直接交给界面做选择。
class PersonalContextException implements Exception {
  const PersonalContextException(
    this.code,
    this.message, {
    this.candidates = const <PersonalContextEntity>[],
  });

  final PersonalContextErrorCode code;
  final String message;
  final List<PersonalContextEntity> candidates;

  /// 面向用户的中文提示；服务层不再重复拼文案。
  String get userMessage {
    switch (code) {
      case PersonalContextErrorCode.invalid:
        return '内容不完整：$message';
      case PersonalContextErrorCode.unsupported:
        return '暂不支持该类型：$message';
      case PersonalContextErrorCode.unauthorized:
        return '没有足够授权：$message';
      case PersonalContextErrorCode.stale:
        return '内容已被改动或已过期：$message';
      case PersonalContextErrorCode.conflict:
        return candidates.isEmpty ? '存在冲突：$message' : '存在多个候选，请选择：$message';
      case PersonalContextErrorCode.notFound:
        return '未找到对应的个人上下文：$message';
      case PersonalContextErrorCode.blocked:
        return '该条目已被遗忘，不会自动重新写入：$message';
    }
  }

  @override
  String toString() => 'PersonalContextException(${code.name}): $message';
}

/// 一条个人上下文实体。
///
/// `projectId` 为 null 表示"全局可召回"；有值时只在同一项目内可见。同名人物
/// 与同名文件靠 `qualifier` 而不是 id 来区分——id 对模型没有意义，而"（甲方
/// 王工）/（乙方王工）"这样的限定词是人能核对、模型能复述的。
class PersonalContextEntity {
  const PersonalContextEntity({
    required this.id,
    required this.kind,
    required this.label,
    required this.normalizedKey,
    this.qualifier = '',
    this.source = PersonalContextSource.userExplicit,
    this.confirmation = PersonalContextConfirmation.unconfirmed,
    this.lifecycle = PersonalContextLifecycle.active,
    this.authorization = PersonalContextAuthorization.notRequired,
    this.revision = 1,
    this.projectId,
    this.validUntil,
    this.attributes = const <String, Object?>{},
    this.originRef = '',
    this.correctionNote = '',
    this.confirmedAt,
    required this.createdAt,
    required this.updatedAt,
    this.forgottenAt,
  });

  static const Object _unset = Object();

  final String id;
  final PersonalContextEntityKind kind;
  final String label;

  /// `kind:归一化标签[#归一化限定词]`，与 `normalizedLabel` 一起构成消歧基础。
  final String normalizedKey;
  final String qualifier;
  final PersonalContextSource source;
  final PersonalContextConfirmation confirmation;
  final PersonalContextLifecycle lifecycle;
  final PersonalContextAuthorization authorization;

  /// 每次更正 +1，供界面/服务判断写入是否基于最新版本。
  final int revision;
  final String? projectId;
  final DateTime? validUntil;

  /// 附加属性（如人物角色、文件路径）。内容自由，但必须是可 JSON 序列化的值。
  final Map<String, Object?> attributes;

  /// 来源定位：会话 id、文档 id 等，便于溯源与"删除范围"提示。
  final String originRef;

  /// 最近一次更正说明，保留"为什么改"。
  final String correctionNote;
  final DateTime? confirmedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? forgottenAt;

  bool get isConfirmed => confirmation == PersonalContextConfirmation.confirmed;

  bool get isForgotten => lifecycle == PersonalContextLifecycle.forgotten;

  bool get isSpeculative => source.isSpeculative;

  bool get isAuthorized => source.requiresAuthorization
      ? authorization == PersonalContextAuthorization.granted
      : authorization.allowsRecall;

  String? get qualifierOrNull => qualifier.isEmpty ? null : qualifier;

  /// 归一化标签（从 key 反推，避免存两份又不同步）。
  String get normalizedLabel {
    final colon = normalizedKey.indexOf(':');
    final body = colon < 0 ? normalizedKey : normalizedKey.substring(colon + 1);
    final hash = body.indexOf('#');
    return hash < 0 ? body : body.substring(0, hash);
  }

  /// 是否已过期。没有有效期视为长期有效。
  bool isExpiredAt(DateTime now) =>
      validUntil != null && !validUntil!.isAfter(now);

  /// 项目可见性。
  ///
  /// 当前没有项目上下文时只召回全局条目，避免把 A 项目的私有信息泄露到
  /// 通用对话中；有项目时只多召回该项目的条目。
  bool isVisibleInProject(String? projectId) =>
      this.projectId == null || this.projectId == projectId;

  /// 能否进入"长期上下文注入"或普通召回。
  bool isRecallableAt(DateTime now, {String? projectId}) =>
      !isForgotten &&
      isConfirmed &&
      isAuthorized &&
      !isExpiredAt(now) &&
      isVisibleInProject(projectId);

  /// 能否作为敏感动作的唯一对象依据。
  ///
  /// 除召回条件外，推测类来源一律不行：即使被用户确认过，它也仍是"推测"，
  /// 敏感动作必须能落到用户明确陈述或已授权资料上。
  bool canAnchorSensitiveAction(DateTime now, {String? projectId}) =>
      isRecallableAt(now, projectId: projectId) && !isSpeculative;

  /// 界面标签：来源 + 确认状态。
  ///
  /// 推测即使被用户确认过也仍然标注"推测"，只是确认状态不同——这样模型和
  /// 用户都不会把一句推断当成用户原话。
  String get provenanceLabel {
    if (!isSpeculative) return source.label;
    return isConfirmed ? '推测（已确认）' : '推测（未确认）';
  }

  PersonalContextEntity copyWith({
    String? id,
    PersonalContextEntityKind? kind,
    String? label,
    String? normalizedKey,
    String? qualifier,
    PersonalContextSource? source,
    PersonalContextConfirmation? confirmation,
    PersonalContextLifecycle? lifecycle,
    PersonalContextAuthorization? authorization,
    int? revision,
    Object? projectId = _unset,
    Object? validUntil = _unset,
    Map<String, Object?>? attributes,
    String? originRef,
    String? correctionNote,
    Object? confirmedAt = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? forgottenAt = _unset,
  }) {
    return PersonalContextEntity(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      label: label ?? this.label,
      normalizedKey: normalizedKey ?? this.normalizedKey,
      qualifier: qualifier ?? this.qualifier,
      source: source ?? this.source,
      confirmation: confirmation ?? this.confirmation,
      lifecycle: lifecycle ?? this.lifecycle,
      authorization: authorization ?? this.authorization,
      revision: revision ?? this.revision,
      projectId:
          identical(projectId, _unset) ? this.projectId : projectId as String?,
      validUntil: identical(validUntil, _unset)
          ? this.validUntil
          : validUntil as DateTime?,
      attributes: attributes ?? this.attributes,
      originRef: originRef ?? this.originRef,
      correctionNote: correctionNote ?? this.correctionNote,
      confirmedAt: identical(confirmedAt, _unset)
          ? this.confirmedAt
          : confirmedAt as DateTime?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      forgottenAt: identical(forgottenAt, _unset)
          ? this.forgottenAt
          : forgottenAt as DateTime?,
    );
  }
}

/// 实体之间的关系。遗忘实体时这些关系会一并清除，避免"已遗忘的人"仍通过
/// 关系图被间接召回。
class PersonalContextRelation {
  const PersonalContextRelation({
    required this.id,
    required this.fromEntityId,
    required this.toEntityId,
    this.relationType = 'related_to',
    this.source = PersonalContextSource.userExplicit,
    this.confirmation = PersonalContextConfirmation.confirmed,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String fromEntityId;
  final String toEntityId;
  final String relationType;
  final PersonalContextSource source;
  final PersonalContextConfirmation confirmation;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// 别名：让"王工""老王"这类称呼收敛到同一实体，但不改变实体本身的标签。
class PersonalContextAlias {
  const PersonalContextAlias({
    required this.id,
    required this.entityId,
    required this.alias,
    required this.normalizedAlias,
    required this.createdAt,
  });

  final String id;
  final String entityId;
  final String alias;
  final String normalizedAlias;
  final DateTime createdAt;
}

/// 遗忘墓碑。
///
/// 只存归一化键、项目与原因：即便原始历史被保留，后续的自动提取也不能凭
/// 同一归一化键把内容重新写回来。项目维度参与主键，避免 A 项目遗忘牵连 B
/// 项目的同名对象。
class PersonalContextTombstone {
  const PersonalContextTombstone({
    required this.normalizedKey,
    this.projectId,
    this.reason = PersonalContextTombstoneReason.forgotten,
    required this.forgottenAt,
    this.entityId = '',
  });

  final String normalizedKey;
  final String? projectId;
  final PersonalContextTombstoneReason reason;
  final DateTime forgottenAt;

  /// 原实体 id，仅供审计展示。
  final String entityId;
}

/// 更正历史快照：保留每一版的来源与时间，回答"这句话是什么时候、由谁说的"。
class PersonalContextRevision {
  const PersonalContextRevision({
    required this.id,
    required this.entityId,
    required this.revision,
    required this.label,
    required this.source,
    required this.confirmation,
    this.validUntil,
    this.attributes = const <String, Object?>{},
    required this.recordedAt,
    this.changeKind = 'corrected',
    this.correctionNote = '',
  });

  final String id;
  final String entityId;
  final int revision;
  final String label;
  final PersonalContextSource source;
  final PersonalContextConfirmation confirmation;
  final DateTime? validUntil;
  final Map<String, Object?> attributes;
  final DateTime recordedAt;
  final String changeKind;
  final String correctionNote;
}

/// 一次遗忘操作的影响范围，用于在确认对话框里如实告诉用户删了哪些东西。
class PersonalContextForgetReport {
  const PersonalContextForgetReport({
    required this.entity,
    required this.removedAliases,
    required this.removedRelations,
    required this.keptRevisions,
    required this.tombstone,
  });

  final PersonalContextEntity entity;
  final int removedAliases;
  final int removedRelations;

  /// 保留的历史版本数（原始历史保留策略下 > 0）。
  final int keptRevisions;
  final PersonalContextTombstone tombstone;

  String get scopeSummary {
    final parts = <String>[
      '已遗忘「${entity.label}」',
      '移除 $removedAliases 个别名',
      '移除 $removedRelations 条关联',
      if (keptRevisions > 0) '保留 $keptRevisions 条历史版本（不再参与召回）',
      '已写入墓碑，该条目不会被自动重新写入',
    ];
    return parts.join('；');
  }
}

/// 一次指代查询。
class PersonalContextLookup {
  const PersonalContextLookup({
    required this.reference,
    this.kindHint,
    this.qualifier,
    this.projectId,
    this.forSensitiveAction = false,
    this.includeUnconfirmed = true,
  });

  /// 用户/模型给出的原始指代，如"上次那份方案"。
  final String reference;
  final PersonalContextEntityKind? kindHint;
  final String? qualifier;
  final String? projectId;

  /// 敏感动作用：候选必须是已确认且非推测来源。
  final bool forSensitiveAction;

  /// 普通召回可先看未确认条目；注入路径则应关掉。
  final bool includeUnconfirmed;
}

/// 打分候选。
class PersonalContextCandidate {
  const PersonalContextCandidate({
    required this.entity,
    required this.score,
    required this.reasons,
  });

  final PersonalContextEntity entity;
  final int score;

  /// 命中的加分项，便于界面解释"为什么推荐它"。
  final List<String> reasons;

  /// 给界面用的可读解释。
  String get explanation => reasons.isEmpty ? '综合匹配' : reasons.join('、');
}

/// 消歧结果。
class PersonalContextResolution {
  const PersonalContextResolution({
    required this.status,
    this.entity,
    this.candidates = const <PersonalContextCandidate>[],
    this.tombstone,
    this.message = '',
  });

  const PersonalContextResolution.resolved(PersonalContextEntity entity)
      : this(status: PersonalContextResolutionStatus.resolved, entity: entity);

  const PersonalContextResolution.missing([String message = ''])
      : this(status: PersonalContextResolutionStatus.missing, message: message);

  final PersonalContextResolutionStatus status;
  final PersonalContextEntity? entity;
  final List<PersonalContextCandidate> candidates;
  final PersonalContextTombstone? tombstone;
  final String message;

  bool get isResolved =>
      status == PersonalContextResolutionStatus.resolved && entity != null;

  bool get needsChoice => status == PersonalContextResolutionStatus.ambiguous;

  /// 取出唯一实体；否则按状态抛出可区分的领域异常。
  PersonalContextEntity requireEntity() {
    switch (status) {
      case PersonalContextResolutionStatus.resolved:
        final resolved = entity;
        if (resolved == null) {
          throw const PersonalContextException(
            PersonalContextErrorCode.notFound,
            '指代没有匹配到条目',
          );
        }
        return resolved;
      case PersonalContextResolutionStatus.ambiguous:
        throw PersonalContextException(
          PersonalContextErrorCode.conflict,
          '「$message」存在多个候选，需要用户确认',
          candidates: candidates.map((candidate) => candidate.entity).toList(),
        );
      case PersonalContextResolutionStatus.expired:
        throw PersonalContextException(
          PersonalContextErrorCode.stale,
          '「$message」只匹配到已过期条目，已过期事项不参与召回',
        );
      case PersonalContextResolutionStatus.blocked:
        throw PersonalContextException(
          PersonalContextErrorCode.blocked,
          '「$message」已被遗忘，不会自动重新使用',
        );
      case PersonalContextResolutionStatus.unauthorized:
        throw PersonalContextException(
          PersonalContextErrorCode.unauthorized,
          '「$message」来源未确认或授权不足，不能作为依据',
          candidates: candidates.map((candidate) => candidate.entity).toList(),
        );
      case PersonalContextResolutionStatus.missing:
        throw PersonalContextException(
          PersonalContextErrorCode.notFound,
          '未找到「$message」',
        );
    }
  }
}

/// 消歧打分权重。
///
/// 这些数字不是审美选择，而是可解释的排序规则：限定词 > 标签精确 > 别名 >
/// 项目匹配 > 确认状态 > 来源 > 新鲜度。歧义阈值单独给出，因为"分数接近"
/// 才是必须让用户选择的信号。
abstract final class PersonalContextScoring {
  static const int labelExact = 50;
  static const int labelContains = 20;
  static const int aliasExact = 48;
  static const int qualifierExact = 60;
  static const int projectMatch = 15;
  static const int globalFallback = 5;
  static const int confirmed = 10;
  static const int sourceUserExplicit = 8;
  static const int sourceAuthorizedMaterial = 4;
  static const int recentSevenDays = 5;
  static const int recentThirtyDays = 3;

  /// 最高分与次高分差距不超过该值即视为歧义。取 10 分意味着"只差一个确认
  /// 状态"也算歧义——宁可不选，也不替用户猜。
  static const int ambiguityGap = 10;

  /// 歧义时最多返回的候选数量。
  static const int maxCandidates = 5;
}

final RegExp _personalContextWhitespace = RegExp(r'\s+', unicode: true);

final RegExp _personalContextEdgePunctuation = RegExp(
  r'^[\s,.;:!?，。；：！？、\-—_/\\]+|[\s,.;:!?，。；：！？、\-—_/\\]+$',
);

/// 归一化标签：用于匹配，不能用于展示。
///
/// 全角转半角、引号/括号统一、空白折叠、去首尾标点、转小写。这样"《方案
/// （终版）》""方案(终版)"和" 方案（终版） "会落到同一个键上。
String normalizePersonalContextLabel(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return '';
  // 零宽字符常来自复制粘贴，肉眼不可见却会让"同一个词"匹配失败。
  text = text.replaceAll('\u200b', '').replaceAll('\ufeff', '');
  // 全角 ASCII 区统一成半角（涵盖全角括号、字母、数字与部分标点）。
  text = text.replaceAllMapped(
    RegExp('[\uFF01-\uFF5E]'),
    (match) => String.fromCharCode(match.group(0)!.codeUnitAt(0) - 0xFEE0),
  );
  text = text
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .replaceAll('【', '[')
      .replaceAll('】', ']')
      .replaceAll('「', '"')
      .replaceAll('」', '"')
      .replaceAll('《', '<')
      .replaceAll('》', '>');
  text = text.replaceAll(_personalContextWhitespace, ' ');
  text = text.replaceAll(_personalContextEdgePunctuation, '');
  text = _unwrapPersonalContextWrappers(text);
  return text.toLowerCase();
}

/// 去掉整体包裹的成对符号。
///
/// 上面的映射把《》统一成 `<>`，但书名号/引号往往只是排版包裹（"《方案（终版）》"），
/// 剥掉后用户输入的"方案(终版)"才能和它落到同一个归一化键上。
String _unwrapPersonalContextWrappers(String text) {
  var current = text;
  while (current.length >= 2) {
    final first = current[0];
    final last = current[current.length - 1];
    final wraps = (first == '<' && last == '>') ||
        (first == '[' && last == ']') ||
        (first == '(' && last == ')') ||
        (first == '"' && last == '"');
    if (!wraps) break;
    current = current
        .substring(1, current.length - 1)
        .trim()
        .replaceAll(_personalContextEdgePunctuation, '');
  }
  return current;
}

/// 归一化限定词。限定词的括号只是排版，不参与比较。
String normalizePersonalContextQualifier(String? raw) {
  final normalized = normalizePersonalContextLabel(raw ?? '');
  if (normalized.isEmpty) return '';
  var stripped = normalized;
  while (stripped.length >= 2) {
    final first = stripped[0];
    final last = stripped[stripped.length - 1];
    final wraps = (first == '(' && last == ')') ||
        (first == '[' && last == ']') ||
        (first == '<' && last == '>') ||
        (first == '"' && last == '"');
    if (!wraps) break;
    stripped = stripped.substring(1, stripped.length - 1).trim();
  }
  return stripped;
}

/// 构建实体归一化键，并让同名对象靠限定词分开。
///
/// 键不含 projectId：同名文件要在两个项目里共存，隔离由实体的 projectId 列
/// 负责，键只回答"这是不是同一类对象"。
String buildPersonalContextKey({
  required PersonalContextEntityKind kind,
  required String label,
  String? qualifier,
}) {
  final buffer = StringBuffer(kind.wireName)
    ..write(':')
    ..write(normalizePersonalContextLabel(label));
  final normalizedQualifier = normalizePersonalContextQualifier(qualifier);
  if (normalizedQualifier.isNotEmpty) {
    buffer
      ..write('#')
      ..write(normalizedQualifier);
  }
  return buffer.toString();
}

/// Forget guards ignore qualifiers. A different qualifier must not silently
/// re-import a forgotten name; existing other entities are not deleted by this.
String unqualifiedPersonalContextKey(String normalizedKey) =>
    normalizedKey.split('#').first;

/// 墓碑键是否匹配某个已归一化的指代。
///
/// 指代里可能没有限定词（"王工"），而墓碑键带着限定词（"person:王工#甲方"），
/// 所以只比较 `:` 与 `#` 之间的部分。
bool tombstoneMatchesReference(
  PersonalContextTombstone tombstone,
  String normalizedReference,
) {
  // Source digests are write guards, not names for reference resolution.
  if (tombstone.normalizedKey.startsWith('source-sha256:')) return false;
  if (normalizedReference.isEmpty) return false;
  final colon = tombstone.normalizedKey.indexOf(':');
  var body = colon < 0
      ? tombstone.normalizedKey
      : tombstone.normalizedKey.substring(colon + 1);
  final hash = body.indexOf('#');
  if (hash >= 0) body = body.substring(0, hash);
  return body == normalizedReference;
}

int _personalContextRecencyScore(DateTime updatedAt, DateTime now) {
  final age = now.difference(updatedAt);
  if (age.isNegative) return PersonalContextScoring.recentSevenDays;
  if (age.inDays <= 7) return PersonalContextScoring.recentSevenDays;
  if (age.inDays <= 30) return PersonalContextScoring.recentThirtyDays;
  return 0;
}

/// 计算单个实体的匹配分。返回 null 表示完全不匹配（应剔除）。
int? _scorePersonalContextEntity(
  PersonalContextEntity entity, {
  required String normalizedReference,
  required String normalizedQualifier,
  required Set<String> aliasEntityIds,
  required String? projectId,
  required DateTime now,
  required List<String> reasons,
}) {
  var score = 0;
  var matched = false;
  final label = entity.normalizedLabel;
  if (label == normalizedReference) {
    score += PersonalContextScoring.labelExact;
    reasons.add('名称完全匹配');
    matched = true;
  } else if (normalizedReference.length >= 2 &&
      label.contains(normalizedReference)) {
    score += PersonalContextScoring.labelContains;
    reasons.add('名称包含指代');
    matched = true;
  }
  if (aliasEntityIds.contains(entity.id)) {
    // 别名精确匹配优先于"包含"，但不与名称完全匹配叠加重复计分。
    if (!matched) {
      score += PersonalContextScoring.aliasExact;
      reasons.add('命中别名');
    }
    matched = true;
  }
  if (!matched) return null;

  if (normalizedQualifier.isNotEmpty) {
    final entityQualifier = entity.qualifier;
    if (entityQualifier == normalizedQualifier) {
      score += PersonalContextScoring.qualifierExact;
      reasons.add('限定词匹配');
    } else if (entityQualifier.isNotEmpty) {
      // 指代给了限定词、实体却是另一个限定词：明确不是同一个对象。
      return null;
    }
  }

  if (projectId != null && entity.projectId == projectId) {
    score += PersonalContextScoring.projectMatch;
    reasons.add('同一项目');
  } else if (entity.projectId == null) {
    score += PersonalContextScoring.globalFallback;
  }

  if (entity.isConfirmed) {
    score += PersonalContextScoring.confirmed;
    reasons.add('已确认');
  }
  score += switch (entity.source) {
    PersonalContextSource.userExplicit =>
      PersonalContextScoring.sourceUserExplicit,
    PersonalContextSource.authorizedMaterial =>
      PersonalContextScoring.sourceAuthorizedMaterial,
    PersonalContextSource.inferred => 0,
  };
  final recency = _personalContextRecencyScore(entity.updatedAt, now);
  if (recency > 0) {
    score += recency;
    reasons.add('近期更新');
  }
  return score;
}

/// 跨任务/跨会话的指代消歧。
///
/// 规则（也是验收标准）：
/// - 同名人物/文件必须靠限定词与项目区分，无法区分时返回候选而不是替用户选；
/// - 过期条目不算命中，单独返回 expired；
/// - 已遗忘条目不算命中，命中墓碑返回 blocked；
/// - 未确认/授权收回的条目不进入召回；敏感动作连"推测"也不接受。
PersonalContextResolution resolvePersonalContextReference({
  required String reference,
  required Iterable<PersonalContextEntity> entities,
  Iterable<PersonalContextAlias> aliases = const <PersonalContextAlias>[],
  Iterable<PersonalContextTombstone> tombstones =
      const <PersonalContextTombstone>[],
  PersonalContextEntityKind? kindHint,
  String? qualifier,
  String? projectId,
  DateTime? now,
  bool forSensitiveAction = false,
  bool includeUnconfirmed = true,
}) {
  final at = now ?? DateTime.now().toUtc();
  final normalizedReference = normalizePersonalContextLabel(reference);
  if (normalizedReference.isEmpty) {
    return const PersonalContextResolution.missing('指代内容为空');
  }
  final normalizedQualifier = normalizePersonalContextQualifier(qualifier);

  final aliasEntityIds = <String>{};
  for (final alias in aliases) {
    if (alias.normalizedAlias == normalizedReference) {
      aliasEntityIds.add(alias.entityId);
    }
  }

  final scored = <PersonalContextCandidate>[];
  final expired = <PersonalContextCandidate>[];
  final unauthorized = <PersonalContextCandidate>[];
  for (final entity in entities) {
    if (entity.isForgotten) continue;
    if (kindHint != null && entity.kind != kindHint) continue;
    if (!entity.isVisibleInProject(projectId)) continue;
    if (!entity.isAuthorized) continue;
    if (!includeUnconfirmed &&
        entity.confirmation != PersonalContextConfirmation.confirmed) {
      continue;
    }
    final reasons = <String>[];
    final score = _scorePersonalContextEntity(
      entity,
      normalizedReference: normalizedReference,
      normalizedQualifier: normalizedQualifier,
      aliasEntityIds: aliasEntityIds,
      projectId: projectId,
      now: at,
      reasons: reasons,
    );
    if (score == null) continue;
    final candidate = PersonalContextCandidate(
        entity: entity, score: score, reasons: reasons);
    if (entity.isExpiredAt(at)) {
      expired.add(candidate);
      continue;
    }
    if (forSensitiveAction) {
      // 敏感动作：未确认或推测来源都不能作为唯一依据。
      final anchorable =
          entity.isConfirmed && entity.source != PersonalContextSource.inferred;
      if (!anchorable) {
        unauthorized.add(candidate);
        continue;
      }
    }
    scored.add(candidate);
  }

  if (scored.isEmpty) {
    if (expired.isNotEmpty) {
      return PersonalContextResolution(
        status: PersonalContextResolutionStatus.expired,
        candidates: _sortedCandidates(expired),
        message: reference,
      );
    }
    if (unauthorized.isNotEmpty) {
      return PersonalContextResolution(
        status: PersonalContextResolutionStatus.unauthorized,
        candidates: _sortedCandidates(unauthorized),
        message: reference,
      );
    }
    for (final tombstone in tombstones) {
      if (!tombstoneMatchesReference(tombstone, normalizedReference)) continue;
      if (tombstone.projectId != null && tombstone.projectId != projectId) {
        continue;
      }
      return PersonalContextResolution(
        status: PersonalContextResolutionStatus.blocked,
        tombstone: tombstone,
        message: reference,
      );
    }
    return PersonalContextResolution.missing(reference);
  }

  final sorted = _sortedCandidates(scored);
  if (sorted.length > 1) {
    final gap = sorted[0].score - sorted[1].score;
    if (gap <= PersonalContextScoring.ambiguityGap) {
      return PersonalContextResolution(
        status: PersonalContextResolutionStatus.ambiguous,
        candidates: sorted
            .take(PersonalContextScoring.maxCandidates)
            .toList(growable: false),
        message: reference,
      );
    }
  }
  return PersonalContextResolution(
    status: PersonalContextResolutionStatus.resolved,
    entity: sorted.first.entity,
    candidates: sorted
        .take(PersonalContextScoring.maxCandidates)
        .toList(growable: false),
  );
}

List<PersonalContextCandidate> _sortedCandidates(
  List<PersonalContextCandidate> candidates,
) {
  final sorted = List<PersonalContextCandidate>.from(candidates);
  sorted.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byUpdated = b.entity.updatedAt.compareTo(a.entity.updatedAt);
    if (byUpdated != 0) return byUpdated;
    return a.entity.id.compareTo(b.entity.id);
  });
  return sorted;
}

/// 注入前最后一道过滤，与 `PersonalContextEntity.isRecallableAt` 同义，
/// 放在顶层是为了让服务与调试用例用完全相同的一行判断。
bool isPersonalContextRecallable(
  PersonalContextEntity entity, {
  required DateTime now,
  String? projectId,
}) =>
    entity.isRecallableAt(now, projectId: projectId);
