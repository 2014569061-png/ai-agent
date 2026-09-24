import 'dart:typed_data';

/// 会话附件的值对象：**本项目自己的类型**，不依赖任何插件。
///
/// 为什么必须有这一层：`file_picker` 13 把 `PlatformFile` 从「数据容器」改成了
/// 「不可构造的平台句柄」（抽象基类 + `readAsBytes()` 异步读盘）。而本项目一直在
/// 拿它当数据容器用——自己 `PlatformFile(name: ..., bytes: ...)` 构造、直接读
/// `file.bytes` / `file.size`、还把实例塞进草稿与附件条。插件一升版，这种用法就
/// 全面编译失败。
///
/// 因此把附件收敛成自己的值对象：插件只负责「选文件」，选完之后立刻转成
/// [AttachmentFile]，后面所有链路——体检、渲染缩略图、发送、草稿——都只认这个类型。
/// 以后再换选择器实现，这里不需要动。
///
/// 注意：这里**故意不提供** `isImage`。图片判定必须走
/// `attachment_policy.dart` 的 `isImageAttachmentFileName`，否则又会多出第二份
/// 扩展名名单——上一轮修掉的「gif 能发却不显示缩略图」正是这种重复名单造成的。
class AttachmentFile {
  const AttachmentFile({
    required this.name,
    this.bytes,
    this.path,
  });

  /// 文件名，含扩展名。
  final String name;

  /// 文件字节，或 `null` 表示「此刻还没有字节」。
  ///
  /// `null` 是真实存在的状态而非占位：从草稿恢复的附件只有名字与路径，字节要等到
  /// 真正发送时才需要。保留这个可空性可以避免为了「恢复草稿」就把文件全读进内存，
  /// 也能让上层区分「没有字节」与「字节为空」这两种不同情况。
  ///
  /// 附件字节一旦读入会常驻内存直到发送，因此限额体检要尽量在读取之前完成。
  final Uint8List? bytes;

  /// 本地路径，没有则为 `null`（内存来源，如相册、分享）。
  final String? path;

  /// 扩展名（不含点），取自 [name] 的最后一个点，没有则为 `null`。
  String? get extension {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return null;
    final ext = name.substring(dot + 1).toLowerCase();
    return ext.isEmpty ? null : ext;
  }

  /// 字节数；没有字节时为 `0`。
  int get size => bytes?.length ?? 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttachmentFile &&
          other.name == name &&
          other.path == path &&
          identical(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(name, path, bytes);

  @override
  String toString() => 'AttachmentFile(name: $name, size: $size, path: $path)';
}