/// Skill 包解析与校验（裁剪版 Codex SKILL.md）。
/// 安全边界：只允许纯指令 + 静态资源，不含可执行代码。
library;

/// frontmatter 中允许出现的字段。
const Set<String> _allowedKeys = {
  'name',
  'description',
  'author',
  'version',
  'tags',
  'triggers',
  'examples'
};

/// 安装后允许保留的文件扩展名白名单。
const Set<String> kSkillAllowedExtensions = {
  '.md',
  '.txt',
  '.png',
  '.jpg',
  '.jpeg',
  '.webp',
  '.template',
};

/// 解压后总字节上限（5MB）。
const int kSkillMaxBytes = 5 * 1024 * 1024;

/// 最大文件数。
const int kSkillMaxFiles = 200;

/// 外部 Skill 的描述可能使用 YAML 折叠多行文本。
const int kSkillMaxDescriptionChars = 1024;

class SkillMetadata {
  const SkillMetadata({
    required this.name,
    required this.description,
    this.author,
    this.version = '0.0.1',
    this.tags = const [],
    this.triggers = const [],
    this.examples = const [],
  });

  final String name;
  final String description;
  final String? author;
  final String version;
  final List<String> tags;
  final List<String> triggers;
  final List<String> examples;

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'author': author,
        'version': version,
        'tags': tags,
        'triggers': triggers,
        'examples': examples,
      };
}

class SkillParseResult {
  const SkillParseResult({required this.metadata, required this.body});
  final SkillMetadata metadata;
  final String body;
}

class SkillValidationException implements Exception {
  SkillValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 解析 SKILL.md 文本并校验 frontmatter。
SkillParseResult parseSkillMarkdown(String text) {
  final normalized = text.replaceAll('\r\n', '\n');
  if (!normalized.startsWith('---\n')) {
    throw SkillValidationException('SKILL.md 开头缺少 frontmatter 起始标记 `---`');
  }
  final end = normalized.indexOf('\n---', 4);
  if (end < 0) {
    throw SkillValidationException('缺少 frontmatter 结束标记 `---`');
  }
  final header = normalized.substring(4, end);
  final body = normalized.substring(end + 4).trim();
  final map = <String, String>{};
  final listKeys = const {'tags', 'triggers', 'examples'};
  String? activeListKey;
  final headerLines = header.split('\n');
  for (var index = 0; index < headerLines.length; index++) {
    final raw = headerLines[index];
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('-') && activeListKey != null) {
      final item = line.substring(1).trim();
      if (item.isNotEmpty) {
        final key = activeListKey;
        final current = map[key] ?? '';
        map[key] = current.isEmpty ? item : '$current,$item';
      }
      continue;
    }
    final idx = line.indexOf(':');
    if (idx <= 0) {
      activeListKey = null;
      continue;
    }
    final key = line.substring(0, idx).trim().toLowerCase();
    if (!_allowedKeys.contains(key)) {
      activeListKey = null;
      continue;
    }
    var value = line.substring(idx + 1).trim();
    if (key == 'description' &&
        (value.startsWith('>') || value.startsWith('|'))) {
      final continuation = <String>[];
      var nextIndex = index + 1;
      while (nextIndex < headerLines.length) {
        final next = headerLines[nextIndex];
        if (next.trim().isEmpty) {
          continuation.add('');
          nextIndex++;
          continue;
        }
        if (!next.startsWith(' ') && !next.startsWith('\t')) break;
        continuation.add(next.trim());
        nextIndex++;
      }
      value = value.startsWith('>')
          ? continuation.where((line) => line.isNotEmpty).join(' ')
          : continuation.join('\n').trim();
      index = nextIndex - 1;
    }
    map[key] = value;
    activeListKey = listKeys.contains(key) ? key : null;
  }

  final name = _unquote((map['name'] ?? '').trim());
  final description = _unquote((map['description'] ?? '').trim());
  if (!RegExp(r'^[a-z0-9_-]{1,64}$').hasMatch(name)) {
    throw SkillValidationException('name 必须为 1~64 位小写字母/数字/下划线/连字符');
  }
  if (description.isEmpty || description.length > kSkillMaxDescriptionChars) {
    throw SkillValidationException(
        'description 必填且长度不超过 $kSkillMaxDescriptionChars 字符');
  }
  final author = map['author'] == null
      ? null
      : _unquote(map['author']!.trim());
  if (author != null && author.length > 100) {
    throw SkillValidationException('author 长度不能超过 100 字符');
  }
  final version = _unquote(map['version']?.trim() ?? '0.0.1');
  if (version.length > 32) {
    throw SkillValidationException('version 长度不能超过 32 字符');
  }
  final tags = _splitList(map['tags']);
  final triggers = _splitList(map['triggers']);
  final examples = _splitList(map['examples']);
  if (tags.length > 5) {
    throw SkillValidationException('tags 最多 5 个');
  }

  return SkillParseResult(
    metadata: SkillMetadata(
      name: name,
      description: description,
      author: author,
      version: version,
      tags: tags,
      triggers: triggers,
      examples: examples,
    ),
    body: body,
  );
}

List<String> _splitList(String? value) {
  var raw = (value ?? '').trim();
  if (raw.startsWith('[') && raw.endsWith(']')) {
    raw = raw.substring(1, raw.length - 1).trim();
  }
  if (raw.isEmpty) return const [];

  // Split comma-separated YAML-ish values while preserving commas inside a
  // quoted example. This is intentionally small, but handles the common
  // Codex frontmatter forms without treating the whole bracket expression as
  // one trigger.
  final items = <String>[];
  final current = StringBuffer();
  String? quote;
  for (var i = 0; i < raw.length; i++) {
    final char = raw[i];
    if ((char == '"' || char == "'") &&
        (i == 0 || raw[i - 1] != '\\')) {
      if (quote == null) {
        quote = char;
      } else if (quote == char) {
        quote = null;
      } else {
        current.write(char);
      }
      continue;
    }
    if (char == ',' && quote == null) {
      final item = _unquote(current.toString().trim());
      if (item.isNotEmpty) items.add(item);
      current.clear();
      if (items.length >= 12) break;
      continue;
    }
    current.write(char);
  }
  if (items.length < 12) {
    final item = _unquote(current.toString().trim());
    if (item.isNotEmpty) items.add(item);
  }
  return items.take(12).toList(growable: false);
}

String _unquote(String value) {
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")))) {
    return value.substring(1, value.length - 1).trim();
  }
  return value;
}
