import 'dart:io';

import 'bounded_text_reader.dart';

/// 工作区条目的类型。符号链接按目标类型报告（与 `File.exists` 语义一致）。
enum WorkspaceEntryKind { file, directory, notFound }

/// [WorkspaceFs.list] 的结果。[isLink] 为 true 时不跟随链接。
class WorkspaceEntry {
  const WorkspaceEntry(this.path,
      {required this.isDirectory, this.isLink = false});

  final String path;
  final bool isDirectory;
  final bool isLink;

  bool get isFile => !isDirectory && !isLink;
}

/// 工作区文件访问的能力 seam（Harness 的 capability 定义对应物）。
///
/// 模型可调用的文件工具只通过它访问文件，将来可换成远端实现（例如经配对的桌面端）。
///
/// 约定：
/// - 所有路径都是已由 `WorkspaceSandbox.resolvePath` 校验过的绝对路径。
///   沙盒校验目前在本地进行，远端实现必须在自己一侧再次限制在工作区内。
/// - 文本读取有上限，超过时抛 [TextFileTooLarge]，无法解码时抛 [FormatException]，
///   与 [BoundedTextReader] 一致。
/// - 其他失败直接抛出，由工具按「是否已产生副作用」上报。
abstract interface class WorkspaceFs {
  /// 实现标识，写入诊断信息，例如 `local`。
  String get id;

  Future<WorkspaceEntryKind> kindOf(String path);

  Future<String> readText(String path,
      {int maxBytes = BoundedTextReader.maxReadBytes});

  /// 覆写文件；父目录不存在时一并创建。
  Future<void> writeText(String path, String content);

  /// 列出目录，不跟随符号链接。
  Stream<WorkspaceEntry> list(String directory, {bool recursive = false});

  Future<void> ensureDirectory(String path);

  Future<void> deleteFile(String path);

  /// 只删除空目录。
  Future<void> deleteEmptyDirectory(String path);

  /// 同一文件系统内改名（文件或目录）；目标已存在时行为由实现决定，调用方须先检查。
  Future<void> rename(String from, String to);
}

/// 基于 `dart:io` 的本地实现。
class LocalWorkspaceFs implements WorkspaceFs {
  const LocalWorkspaceFs();

  /// Used to seed a staged replacement from the original, retaining the
  /// platform's copy semantics for file permissions before rewriting content.
  Future<void> copyFile(String from, String to) async {
    await File(from).copy(to);
  }

  @override
  String get id => 'local';

  @override
  Future<WorkspaceEntryKind> kindOf(String path) async =>
      switch (await FileSystemEntity.type(path)) {
        FileSystemEntityType.file => WorkspaceEntryKind.file,
        FileSystemEntityType.directory => WorkspaceEntryKind.directory,
        _ => WorkspaceEntryKind.notFound,
      };

  @override
  Future<String> readText(String path,
          {int maxBytes = BoundedTextReader.maxReadBytes}) =>
      BoundedTextReader.read(File(path), maxBytes: maxBytes);

  @override
  Future<void> writeText(String path, String content) async {
    final file = File(path);
    final parent = file.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
  }

  @override
  Stream<WorkspaceEntry> list(String directory, {bool recursive = false}) =>
      Directory(directory)
          .list(recursive: recursive, followLinks: false)
          .map((entity) => WorkspaceEntry(
                entity.path,
                isDirectory: entity is Directory,
                isLink: entity is Link,
              ));

  @override
  Future<void> ensureDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
  }

  @override
  Future<void> deleteFile(String path) => File(path).delete();

  @override
  Future<void> deleteEmptyDirectory(String path) => Directory(path).delete();

  @override
  Future<void> rename(String from, String to) async {
    if (await FileSystemEntity.isDirectory(from)) {
      await Directory(from).rename(to);
    } else {
      await File(from).rename(to);
    }
  }
}
