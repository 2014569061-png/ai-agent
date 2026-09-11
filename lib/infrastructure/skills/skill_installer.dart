/// GitHub Skill 安装器：解析地址、下载 tar.gz、校验、安装到本地 skill 库。
/// 安全边界：只允许 GitHub 公开仓库；只保留纯指令 + 静态资源文件。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../../domain/tool_codes.dart';
import 'skill_parser.dart';

/// 解析后的 GitHub Skill 来源引用。
class GithubSkillRef {
  GithubSkillRef({
    required this.original,
    required this.owner,
    required this.repo,
    required this.ref,
    required this.subPath,
  });

  final String original;
  final String owner;
  final String repo;
  final String ref;
  final String? subPath;

  bool get isLocalArchive => owner == 'local';

  String get fullRepo => '$owner/$repo';

  String get label => isLocalArchive
      ? original
      : subPath == null || subPath!.isEmpty
          ? 'github.com/$fullRepo'
          : 'github.com/$fullRepo/tree/$ref/$subPath';

  factory GithubSkillRef.localArchive(String filename) => GithubSkillRef(
        original: '本地压缩包：$filename',
        owner: 'local',
        repo: p.basenameWithoutExtension(filename),
        ref: 'local',
        subPath: null,
      );
}

/// 安装前预览结果（尚未写盘 / 未入库）。
class SkillPackPreview {
  const SkillPackPreview({
    required this.source,
    required this.metadata,
    required this.fileContents,
    required this.totalBytes,
    required this.sha256Hex,
  });

  final GithubSkillRef source;
  final SkillMetadata metadata;

  /// 相对文件路径 -> 内容字节（仅白名单内的静态资源与 SKILL.md）。
  final Map<String, Uint8List> fileContents;
  final int totalBytes;
  final String sha256Hex;

  List<String> get fileList => fileContents.keys.toList()..sort();
}

/// 安装阶段发生写盘/替换不确定时的显式错误。
///
/// 调用方必须把它作为 NEXT_TURN_REQUIRED 回灌，当前回合不得继续读取这棵
/// Skill 目录；目录会留下冻结标记，直到下一次明确的安装/更新动作处理它。
class SkillInstallException implements Exception {
  const SkillInstallException(this.message,
      {this.code = ToolCodes.nextTurnRequired});

  final String message;
  final String code;

  @override
  String toString() => message;
}

/// 下载 / 校验 / 安装 Skill。
class SkillInstaller {
  SkillInstaller({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const int _maxRawArchiveBytes = 10 * 1024 * 1024;

  /// 解析用户输入为 GitHub 源。仅允许 github.com，拒绝其它任意 URL。
  GithubSkillRef parseInput(String input) {
    final raw = input.trim().replaceAll(RegExp(r'\s+'), '');
    if (raw.isEmpty) {
      throw SkillValidationException('请输入 GitHub 仓库地址或 owner/repo');
    }
    // owner/repo 简写
    final shorthand =
        RegExp(r'^([A-Za-z0-9-]+)/([A-Za-z0-9._-]+)$').firstMatch(raw);
    if (shorthand != null) {
      return GithubSkillRef(
        original: raw,
        owner: shorthand.group(1)!,
        repo: shorthand.group(2)!,
        ref: 'HEAD',
        subPath: null,
      );
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        (uri.host != 'github.com' && uri.host != 'www.github.com')) {
      throw SkillValidationException('仅支持 GitHub 公开仓库地址或 owner/repo 简写');
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) {
      throw SkillValidationException('GitHub 地址至少需要 owner/repo');
    }
    final owner = segments[0];
    var repo = segments[1].replaceAll(RegExp(r'\.git$'), '');
    var ref = 'HEAD';
    String? subPath;
    if (segments.length >= 3) {
      if (segments[2] == 'tree') {
        ref = segments.length > 3 ? segments[3] : 'HEAD';
        if (segments.length > 4) {
          subPath = segments.sublist(4).join('/');
          if (subPath.split('/').contains('..')) {
            throw SkillValidationException('Skill 子目录包含非法路径');
          }
        }
      } else {
        // 其它形式如 /archive/xxx 暂不支持
        throw SkillValidationException(
            '当前仅支持仓库根目录或 /tree/{branch}/{子目录} 形式的地址');
      }
    }
    return GithubSkillRef(
      original: raw,
      owner: owner,
      repo: repo,
      ref: ref,
      subPath: subPath,
    );
  }

  /// 解析输入 -> 下载 -> 解压 -> 校验 -> 返回预览。
  Future<SkillPackPreview> fetchPreview(String input) async {
    final source = parseInput(input);
    final resolved = await _resolveRef(source);
    final bytes = await _downloadArchive(resolved);
    return previewFromArchiveBytes(bytes, resolved);
  }

  /// 从归档字节构建预览（解压 -> 校验，不含下载步骤），便于测试恶意包场景。
  Future<SkillPackPreview> previewFromArchiveBytes(
      Uint8List bytes, GithubSkillRef source) async {
    if (bytes.length > _maxRawArchiveBytes) {
      throw SkillValidationException('压缩包超过 10MB 上限');
    }
    final archive = _decodeArchive(bytes);
    final files = _extractAllowedFiles(archive, source.subPath);
    if (files.isEmpty) {
      throw SkillValidationException('未找到可安装的 SKILL.md 或白名单资源');
    }
    // _extractAllowedFiles 已经剥离了仓库根目录和目标子目录，预览文件统一使用相对路径。
    const skillPath = 'SKILL.md';
    final skillBytes = files[skillPath];
    if (skillBytes == null) {
      throw SkillValidationException(
          '缺少 SKILL.md（目标目录：${source.subPath ?? '/'}）');
    }
    final parsed = parseSkillMarkdown(utf8.decode(skillBytes));
    final totalBytes = files.values.fold<int>(0, (sum, b) => sum + b.length);
    if (totalBytes > kSkillMaxBytes) {
      throw SkillValidationException('Skill 包超过 5MB 限制');
    }
    if (files.length > kSkillMaxFiles) {
      throw SkillValidationException('Skill 包含超过 200 个文件');
    }
    // 校验不保留非法扩展名后的最终清单
    final result = <String, Uint8List>{};
    files.forEach((key, value) {
      if (_isAllowedPath(key)) result[key] = value;
    });
    if (!result.containsKey(skillPath)) {
      throw SkillValidationException('SKILL.md 路径不在白名单内');
    }
    final hashInput = <int>[];
    result.forEach((key, value) {
      hashInput.addAll(utf8.encode(key));
      hashInput.addAll(value);
    });
    final checksum = sha256.convert(hashInput).toString();
    return SkillPackPreview(
      source: source,
      metadata: parsed.metadata,
      fileContents: result,
      totalBytes: totalBytes,
      sha256Hex: checksum,
    );
  }

  /// 安装预览：写盘 + 写入 SkillPacks 表。
  Future<SkillPack> install(AppDatabase db, SkillPackPreview preview) async {
    final dir = await getApplicationDocumentsDirectory();
    final installRoot = p.join(dir.path, 'skills', preview.metadata.name);
    final rootDir = Directory(installRoot);
    final parent = Directory(p.dirname(installRoot));
    await parent.create(recursive: true);
    final stagingRoot = p.join(parent.path,
        '.${preview.metadata.name}.staging-${DateTime.now().microsecondsSinceEpoch}');
    final stagingDir = Directory(stagingRoot);
    Directory? backupDir;
    var committed = false;
    final now = DateTime.now();
    final fileList = <String>[];
    try {
      await stagingDir.create(recursive: true);
      for (final entry in preview.fileContents.entries) {
        final target = p.join(stagingRoot, entry.key);
        final normalized = p.normalize(target);
        if (!normalized.startsWith(p.normalize(stagingRoot) + p.separator) &&
            normalized != p.normalize(stagingRoot)) {
          throw SkillValidationException('非法路径：${entry.key}');
        }
        final file = File(normalized);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.value, flush: true);
        fileList.add(entry.key);
      }

      // 同一父目录内 rename 是原子替换边界：模型不会看到“半棵新 Skill”。
      if (rootDir.existsSync()) {
        backupDir =
            Directory('$installRoot.previous-${now.microsecondsSinceEpoch}');
        await rootDir.rename(backupDir.path);
      }
      await stagingDir.rename(installRoot);
      committed = true;

      final existing = await db.findSkillPackByName(preview.metadata.name);
      final pack = SkillPack(
        id: existing?.id ?? 'skill-${now.microsecondsSinceEpoch}',
        name: preview.metadata.name,
        description: preview.metadata.description,
        author: preview.metadata.author,
        version: preview.metadata.version,
        source: preview.source.isLocalArchive
            ? preview.source.original
            : 'https://${preview.source.label}',
        repo: preview.source.fullRepo,
        ref: preview.source.ref,
        subPath: preview.source.subPath,
        installRoot: installRoot,
        fileListJson: jsonEncode(fileList),
        enabled: true,
        installedAt: existing?.installedAt ?? now,
        updatedAt: now,
        sha256: preview.sha256Hex,
      );
      try {
        await db.saveSkillPack(pack);
      } catch (error) {
        throw SkillInstallException('Skill 文件已替换但安装记录写入失败：$error');
      }
      if (backupDir?.existsSync() == true) {
        await backupDir!.delete(recursive: true);
      }
      return pack;
    } catch (error) {
      // 解析/校验错误不会触及旧目录，不需要冻结；写盘、rename 或 DB 提交
      // 进入不确定状态后必须冻结整棵目录，避免本回合继续读取混合版本。
      if (error is SkillValidationException) {
        rethrow;
      }
      if (backupDir?.existsSync() == true) {
        try {
          final current = Directory(installRoot);
          if (current.existsSync()) await current.delete(recursive: true);
          await backupDir!.rename(installRoot);
        } catch (_) {
          // 回滚失败时仍保留冻结标记，宁可停用也不让模型猜测状态。
        }
      }
      await _freezeDirectory(rootDir, '$error');
      if (error is SkillInstallException) rethrow;
      throw SkillInstallException('Skill 安装状态无法确认：$error');
    } finally {
      if (stagingDir.existsSync()) {
        try {
          await stagingDir.delete(recursive: true);
        } catch (_) {}
      }
      // 成功提交后旧目录已不再需要；失败路径若回滚成功则 backup 已被 rename。
      if (backupDir?.existsSync() == true && committed) {
        try {
          await backupDir!.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<void> _freezeDirectory(Directory root, String reason) async {
    try {
      await root.create(recursive: true);
      await File(p.join(root.path, '.nexus-frozen')).writeAsString(
        'code=${ToolCodes.nextTurnRequired}\n$reason\n',
        flush: true,
      );
    } catch (_) {
      // 冻结标记本身失败时无法进一步保证状态，错误仍由调用方回灌。
    }
  }

  Future<GithubSkillRef> _resolveRef(GithubSkillRef source) async {
    if (source.ref != 'HEAD') return source;
    try {
      final resp = await _dio.get<dynamic>(
        'https://api.github.com/repos/${source.fullRepo}',
        options: Options(
          headers: {'Accept': 'application/vnd.github+json'},
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final data = resp.data;
      final defaultBranch = (data is Map) ? data['default_branch'] : null;
      if (defaultBranch is String && defaultBranch.isNotEmpty) {
        return GithubSkillRef(
          original: source.original,
          owner: source.owner,
          repo: source.repo,
          ref: defaultBranch,
          subPath: source.subPath,
        );
      }
    } catch (_) {
      // 解析默认分支失败时以 main 兜底，下载失败再由用户看到错误。
    }
    return GithubSkillRef(
      original: source.original,
      owner: source.owner,
      repo: source.repo,
      ref: 'main',
      subPath: source.subPath,
    );
  }

  Future<Uint8List> _downloadArchive(GithubSkillRef source) async {
    final url =
        'https://codeload.github.com/${source.fullRepo}/tar.gz/refs/heads/${Uri.encodeComponent(source.ref)}';
    final resp = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    final data = resp.data;
    if (data == null || data.isEmpty) {
      throw SkillValidationException('GitHub 返回空内容');
    }
    if (data.length > _maxRawArchiveBytes) {
      throw SkillValidationException('下载包超过 10MB 上限');
    }
    return Uint8List.fromList(data);
  }

  Archive _decodeArchive(Uint8List bytes) {
    try {
      if (bytes.length >= 4 &&
          bytes[0] == 0x50 &&
          bytes[1] == 0x4b &&
          (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07)) {
        return ZipDecoder().decodeBytes(bytes);
      }
      final gz = const GZipDecoder().decodeBytes(bytes);
      return TarDecoder().decodeBytes(gz);
    } catch (_) {
      throw SkillValidationException('仅支持 ZIP 或 tar.gz 格式的 Skill 压缩包');
    }
  }

  /// 提取白名单内的文件，并统一剥离 tar 根目录第一层。
  Map<String, Uint8List> _extractAllowedFiles(
      Archive archive, String? subPath) {
    // codeload 的 tar 顶层通常是 {repo}-{branch}。
    final rootPrefix = _findRootPrefix(archive);
    final result = <String, Uint8List>{};
    var fileCount = 0;
    for (final file in archive) {
      var rel = file.name;
      if (rootPrefix.isNotEmpty && rel.startsWith(rootPrefix)) {
        rel = rel.substring(rootPrefix.length);
      }
      rel = rel.replaceAll('\\', '/');
      if (rel.startsWith('/')) rel = rel.substring(1);
      if (rel.isEmpty) continue;
      if (rel.split('/').contains('..')) {
        throw SkillValidationException('Skill 包包含路径穿越：$rel');
      }
      // 只关心 subPath 目录下（无 subPath 时看根目录）
      if (subPath != null && subPath.isNotEmpty) {
        if (rel.startsWith('$subPath/')) {
          rel = rel.substring(subPath.length + 1);
        } else {
          continue;
        }
      }
      if (file.isSymbolicLink) {
        throw SkillValidationException('Skill 包不允许符号链接：$rel');
      }
      if (file.isDirectory) continue;
      if (!file.isFile) {
        throw SkillValidationException('Skill 包包含不支持的文件类型：$rel');
      }
      fileCount++;
      if (fileCount > kSkillMaxFiles) {
        throw SkillValidationException('Skill 包含超过 200 个文件');
      }
      if (!_isAllowedPath(rel)) {
        throw SkillValidationException('Skill 包含不允许的文件：$rel');
      }
      final data = file.readBytes();
      if (data == null ||
          data.isEmpty && !rel.endsWith('.md') && !rel.endsWith('.txt')) {
        if (data == null) continue;
      }
      result[rel] = data;
    }
    return result;
  }

  String _findRootPrefix(Archive archive) {
    final names = archive
        .where((file) => file.name.isNotEmpty)
        .map((file) => file.name.replaceAll('\\', '/'))
        .toList(growable: false);
    if (names.isEmpty || names.any((name) => !name.contains('/'))) return '';
    final prefix = names.first.split('/').first;
    return names.every((name) => name.startsWith('$prefix/')) ? '$prefix/' : '';
  }

  bool _isAllowedPath(String rel) {
    final lower = rel.toLowerCase();
    if (!kSkillAllowedExtensions.any((ext) => lower.endsWith(ext))) {
      return false;
    }
    // 仅 assets/ 下允许图片与模板；md/txt 可在任意位置。
    final ext = p.extension(lower);
    if (const {'.png', '.jpg', '.jpeg', '.webp', '.template'}.contains(ext)) {
      return lower.startsWith('assets/');
    }
    return const {'.md', '.txt'}.contains(ext);
  }
}
