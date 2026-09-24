/// 附件准入策略：附件数量、单文件与总字节预算的**单一来源**。
///
/// 为什么需要抽出来：这三条限额此前分散在 `ChatPage`（选择阶段）与
/// `ChatController`（发送阶段）两处，各自写了一遍 `8 * 1024 * 1024`，并在注释里
/// 要求对方「保持一致」。这种靠注释维持的一致性会漂移 —— 只要有一侧改了数，
/// 用户就会看到「选的时候能加、点发送却被静默跳过」这类难以复现的怪象。
///
/// 这里只放纯计算，不依赖 Flutter，便于单测直接覆盖边界。
library;

/// 单条消息可携带的附件数量上限。
///
/// 附件字节会常驻内存直到发送（发送时再内联进请求内容），因此除了单文件上限
/// 还需要一道数量闸门，否则一次选中几十个文件就足以让低端机 OOM。
const int maxAttachmentCount = 10;

/// 单个附件的字节上限（8MB）。
const int maxAttachmentBytes = 8 * 1024 * 1024;

/// 全部附件的总字节预算（24MB）。
///
/// 单文件合规不等于总量安全：10 个 8MB 文件依然能吃掉 80MB 常驻内存。
const int maxAttachmentTotalBytes = 24 * 1024 * 1024;

/// 以 MB 为单位展示单文件上限（用于用户提示）。
int get maxAttachmentMegabytes => maxAttachmentBytes ~/ (1024 * 1024);

/// 以 MB 为单位展示总预算（用于用户提示）。
int get maxAttachmentTotalMegabytes => maxAttachmentTotalBytes ~/ (1024 * 1024);

/// 已用字节为 [usedBytes] 时，还能再容纳的附件数量。
///
/// 只按数量计算；字节预算由 [fitsIntoBudget] 单独判断，因为调用方通常先按数量
/// 截断再逐个体检（避免把超量文件先读进内存）。
int remainingAttachmentSlots(int currentCount) {
  final remaining = maxAttachmentCount - currentCount;
  return remaining < 0 ? 0 : remaining;
}

/// 单个附件是否可接受：大小为正值、不超过单文件上限，且不撑爆总预算。
bool fitsIntoBudget({
  required int size,
  required int usedBytes,
}) {
  if (size <= 0) return false;
  if (size > maxAttachmentBytes) return false;
  return usedBytes + size <= maxAttachmentTotalBytes;
}

/// 可作为图片附件发送的扩展名 → MIME。
///
/// 发送端把它们内联为 `image_url`/`inline_data`，三个 Provider 都是**通用 MIME
/// 透传**（openai:331、gemini:265、anthropic:304），因此这里只需给出正确的 MIME。
/// 这四种都是主流多模态接口支持的图片格式。
const Map<String, String> imageAttachmentMimeByExtension = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'webp': 'image/webp',
  'gif': 'image/gif',
};

/// 可内联为文本内容的扩展名（发送端会抽取其文本）。
const Set<String> textAttachmentExtensions = {
  'txt',
  'md',
  'csv',
  'json',
};

/// 文件选择器**应当开放**的扩展名，按字母序排列。
///
/// 这份名单必须与发送端的真实能力一致，因此它由上面两组推导而来，而不是手写：
/// 此前选择器单独列了 18 种（含 webp、gif 与全部音视频），而发送端只认 7 种，
/// 于是 11 种扩展名「能选不能发」—— 用户把文件选进来、被读进内存，发送时却被
/// 丢弃。这与原先散落的 8MB 上限是同一类漂移，现在收敛到单一来源。
///
/// webp/gif 保留：它们的 MIME 会被透传给 Provider，端到端可用，此前只是发送端
/// 的 MIME 映射漏写。
///
/// 音视频（mp3/wav/mp4 等）**不在**名单内。Provider 层虽有
/// `input_audio`/`video_url` 分支，但 `_audioFormat` 只区分 wav/mp3、会把其它格式
/// 错标成 mp3，且只有 OpenAI 兼容 Provider 实现了它们，不具备可靠的端到端支持。
/// 将来真正打通后，把新扩展名加进名单即可，选择器会自动跟随。
List<String> get acceptedAttachmentExtensions {
  final extensions = <String>{
    ...imageAttachmentMimeByExtension.keys,
    ...textAttachmentExtensions,
  }.toList()
    ..sort();
  return List<String>.unmodifiable(extensions);
}

/// 该扩展名对应的图片 MIME；不是可发送的图片时返回 null。
///
/// 大小写不敏感：选择器给的扩展名是小写，但用户手上的文件实际可能是 `IMG.PNG`。
String? imageMimeForExtension(String? extension) {
  if (extension == null) return null;
  return imageAttachmentMimeByExtension[extension.toLowerCase()];
}

/// 该扩展名是否可作为文本附件内联。
bool isTextAttachmentExtension(String? extension) {
  if (extension == null) return false;
  return textAttachmentExtensions.contains(extension.toLowerCase());
}

/// 该**文件名**是否为可发送的图片（按最后一个 `.` 取扩展名）。
///
/// 供缩略图渲染使用：此前那里硬编码了 jpg/png/jpeg/webp 四个后缀，漏掉了 gif，
/// 于是 gif 加入可发送名单后能发、却不显示缩略图。现在与发送端共用同一映射。
bool isImageAttachmentFileName(String fileName) =>
    imageMimeForFileName(fileName) != null;

/// 该文件名对应的图片 MIME；不是可发送的图片时返回 null。
String? imageMimeForFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return null;
  return imageMimeForExtension(fileName.substring(dot + 1));
}
