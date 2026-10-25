part of 'chat_page.dart';

/// 附件：文件与图片选择、分享图片解码。
extension _ChatAttachments on _ChatPageState {
  Future<void> _attachDesktopPaths(List<String> paths) async {
    final candidates = <_PickedAttachment>[];
    for (final path in paths) {
      final file = File(path);
      try {
        if (!await file.exists()) continue;
        candidates.add(_PickedAttachment(
            name: p.basename(path),
            knownSize: await file.length(),
            readBytes: file.readAsBytes));
      } catch (error) {
        if (mounted) {
          FloatingToast.error(context, '无法读取拖入文件', rawDetail: '$error');
        }
      }
    }
    await _attachPickedFiles(candidates);
  }

  /// 解码分享进来的 `data:image/...;base64,...`。
  ///
  /// 单张解码失败（base64 被截断等）只提示并丢弃该张，不影响同批其他内容。
  AttachmentFile? _decodeSharedImage(String dataUri) {
    try {
      final comma = dataUri.indexOf(',');
      if (comma < 0) throw const FormatException('缺少 base64 分隔符');
      final bytes = base64Decode(dataUri.substring(comma + 1));
      final mime = dataUri.substring('data:'.length, comma).split(';').first;
      final extension = mime.contains('/') ? mime.split('/').last : 'jpg';
      return AttachmentFile(
        name: '分享图片.$extension',
        bytes: bytes,
      );
    } catch (error) {
      if (mounted) {
        FloatingToast.error(context, '图片分享解析失败', rawDetail: error.toString());
      }
      return null;
    }
  }

  // --- 操作 ---

  Future<void> _pickFiles() async {
    // 选择器只负责「选」：file_picker 13 起 `withData` 已移除，`pickFiles` 也不再
    // 返回 null（取消时是空列表）。字节一律在体检通过后再自己读，避免用户点确定
    // 的瞬间把所有选中文件全读进内存，选 5 个视频就是几百 MB 的峰值，而它们可能
    // 一个都超限、根本用不上。
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      // 名单来自 attachment_policy.dart，与发送端的类型闸门是同一份，因此选择器
      // 里不会出现「能选、但发送时被丢弃」的扩展名。
      allowedExtensions: acceptedAttachmentExtensions,
    );
    if (!mounted) return;
    await _attachPickedFiles([
      for (final file in picked)
        _PickedAttachment(
          name: file.name,
          // 原生上报的大小可以免 I/O 拿到；拿不到时体检阶段会再退回读盘。
          knownSize: file.lengthSync(),
          // 走插件自己的 readAsBytes()：Android 的 SAF content:// 结果没有本地
          // 路径，只有插件能读它的字节。
          readBytes: () async {
            try {
              return await file.readAsBytes();
            } catch (_) {
              return null;
            }
          },
        ),
    ]);
  }

  /// 把选中的文件加入附件区，并做数量 / 单文件 / 总量三重体检。
  ///
  /// 三重判断都尽量发生在**读取字节之前**：附件字节会常驻内存直到发送，先读再丢
  /// 等于把内存峰值白白打满一次。被跳过的文件按原因汇总成一条提示，而不是静默
  /// 丢弃——用户挑了文件却什么都没发生，只会以为应用坏了。
  ///
  /// 参数是本项目自己的候选类型，因此相册、拍照、分享等来源都能复用同一套体检与
  /// 提示，不必都伪装成插件的 `PlatformFile`。
  Future<void> _attachPickedFiles(List<_PickedAttachment> picked) async {
    if (!mounted || picked.isEmpty) return;
    final accepted = <AttachmentFile>[];
    var usedBytes = _attachments.fold<int>(0, (sum, file) => sum + file.size);
    var rejectedSize = 0;
    var rejectedCount = 0;
    var rejectedRead = 0;

    for (final file in picked) {
      if (_attachments.length + accepted.length >=
          _ChatPageState._maxAttachmentCount) {
        rejectedCount++;
        continue;
      }
      var bytes = file.knownBytes;
      // 免 I/O 的大小优先（Android 原生上报）；未知时先不判定，等读到字节再算。
      final size = file.sizeIfKnown;
      if (size != null &&
          (size <= 0 ||
              size > _ChatPageState._maxAttachmentBytes ||
              !fitsIntoBudget(size: size, usedBytes: usedBytes))) {
        rejectedSize++;
        continue;
      }
      if (bytes == null) {
        bytes = await file.readBytes?.call();
        if (bytes == null) {
          rejectedRead++;
          continue;
        }
        // 之前拿不到大小，现在读到了，补做一次限额判定。
        if (size == null &&
            (bytes.isEmpty ||
                bytes.length > _ChatPageState._maxAttachmentBytes ||
                !fitsIntoBudget(size: bytes.length, usedBytes: usedBytes))) {
          rejectedSize++;
          continue;
        }
      }
      if (bytes.isEmpty) {
        rejectedRead++;
        continue;
      }
      usedBytes += bytes.length;
      accepted.add(AttachmentFile(name: file.name, bytes: bytes));
    }

    if (accepted.isNotEmpty) {
      _attachments.addAll(accepted);
      _notifyAttachmentsChanged();
    }
    if (!mounted) return;
    final perFileMb = _ChatPageState._maxAttachmentBytes ~/ (1024 * 1024);
    final totalMb = _ChatPageState._maxAttachmentTotalBytes ~/ (1024 * 1024);
    final problems = <String>[
      if (rejectedSize > 0)
        '$rejectedSize 个超过单文件 $perFileMb MB 或总预算 $totalMb MB',
      if (rejectedCount > 0)
        '$rejectedCount 个超过 $_ChatPageState._maxAttachmentCount 个上限',
      if (rejectedRead > 0) '$rejectedRead 个无法读取',
    ];
    if (problems.isNotEmpty) {
      FloatingToast.show(
        context,
        '已添加 ${accepted.length} 个附件；${problems.join('，')}已跳过',
        tone: ToastTone.warning,
      );
    }
  }

  /// 相册多选图片（A6：多图一次性发送）。
  Future<void> _pickMultiImage() async {
    try {
      final files = await _picker.pickMultiImage(
          maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
      if (files.isEmpty || !mounted) return;
      // 先按剩余配额截断再读字节：多选 50 张时不该先把 50 张全解码进内存。
      final remaining =
          _ChatPageState._maxAttachmentCount - _attachments.length;
      if (remaining <= 0) {
        FloatingToast.show(
            context, '最多添加 $_ChatPageState._maxAttachmentCount 个附件',
            tone: ToastTone.warning);
        return;
      }
      final selected =
          files.length > remaining ? files.sublist(0, remaining) : files;
      final attachments = <_PickedAttachment>[];
      for (final xfile in selected) {
        final bytes = await xfile.readAsBytes();
        attachments.add(
            _PickedAttachment.inMemory(name: xfile.name, knownBytes: bytes));
      }
      await _attachPickedFiles(attachments);
    } catch (e) {
      if (mounted) {
        FloatingToast.error(context, '无法获取图片', rawDetail: e.toString());
      }
    }
  }

  /// 拍照/相册：压缩到 1280px / 80% 质量，控制 base64 体积，复用现有附件管线。
  Future<void> _pickImage(ImageSource source) async {
    try {
      final xfile = await _picker.pickImage(
          source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
      if (xfile == null || !mounted) return;
      final bytes = await xfile.readAsBytes();
      if (!mounted) return;
      await _attachPickedFiles([
        _PickedAttachment.inMemory(name: xfile.name, knownBytes: bytes),
      ]);
    } catch (e) {
      if (mounted) {
        FloatingToast.error(context, '无法获取图片', rawDetail: e.toString());
      }
    }
  }
}
