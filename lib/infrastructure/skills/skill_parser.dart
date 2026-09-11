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
  for (final raw in header.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final idx = line.indexOf(':');
    if (idx > 0) {
      final key = line.substring(0, idx).trim().toLowerCase();
      if (_allowedKeys.contains(key)) {
        var value = line.substring(idx + 1).trim();
        if (key == 'tags') {
          value = value.replaceFirst(RegExp(r'^\['), '');
          value = value.replaceFirst(RegExp(r'\]$'), '');
        }
        map[key] = value;
      }
    } else if (line.startsWith('-') && map.containsKey('tags')) {
      final tag = line.substring(1).trim();
      if (tag.isNotEmpty) {
        map['tags'] = map['tags']!.isEmpty ? tag : '${map['tags']},$tag';
      }
    }
  }

  final name = (map['name'] ?? '').trim();
  final description = (map['description'] ?? '').trim();
  if (!RegExp(r'^[a-z0-9_-]{1,64}$').hasMatch(name)) {
    throw SkillValidationException('name 必须为 1~64 位小写字母/数字/下划线/连字符');
  }
  if (description.isEmpty || description.length > 200) {
    throw SkillValidationException('description 必填且长度不超过 200 字符');
  }
  final author = map['author']?.trim();
  if (author != null && author.length > 100) {
    throw SkillValidationException('author 长度不能超过 100 字符');
  }
  final version = map['version']?.trim() ?? '0.0.1';
  if (version.length > 32) {
    throw SkillValidationException('version 长度不能超过 32 字符');
  }
  final tags = (map['tags'] ?? '')
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
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

List<String> _splitList(String? value) => (value ?? '')
    .split(',')
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .take(12)
    .toList(growable: false);
