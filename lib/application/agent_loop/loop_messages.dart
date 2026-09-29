import '../../domain/models.dart';

/// 执行循环自行注入给模型的消息（原先散落在 AgentExecutor.run 中）。
///
/// 这些消息都是模型可见的，因此全部集中在这里，文本变更一目了然；会话日志
/// 通过 onRequest 快照记录它们。修改任何文本都会改变模型输入与前缀缓存。
abstract final class LoopMessages {
  static ChatMessage steering(String instruction) => ChatMessage(
        role: MessageRole.user,
        parts: [
          MessagePart.text(
            '用户补充指令：$instruction\n请继续执行，不要从头重复已完成的步骤。',
          ),
        ],
      );

  static String repeatedFailureHint(String toolName, int count) =>
      '[系统提示] 工具 $toolName 以完全相同的参数已经失败 $count 次。不要再原样'
      '重试：先分析失败原因（权限、路径、依赖是否存在）并换一种方法；如果需要'
      '用户授权或补充信息，请直接向用户说明。';

  static ChatMessage failureHints(List<String> hints) => ChatMessage(
        role: MessageRole.user,
        parts: [MessagePart.text(hints.join('\n'))],
      );

  static ChatMessage planConfirmed() => ChatMessage(
        role: MessageRole.user,
        parts: const [
          MessagePart.text(
            '[计划已确认] 用户已批准执行以上计划。请继续按照计划执行剩余步骤；需要工具时直接调用工具，不要只输出计划或提前结束。完成全部步骤后再总结结果。',
          )
        ],
      );

  static ChatMessage pauseInterrupted() => ChatMessage(
        role: MessageRole.user,
        parts: const [
          MessagePart.text(
            '[系统提示] 上一段回复因用户暂停被中断。继续时请从中断处接着完成，'
            '不要重复已经输出的内容。',
          ),
        ],
      );

  static const String truncatedToolCallMessage =
      '模型输出达到长度上限，工具参数可能不完整，本次未执行';
  static const String unexpectedToolCallMessage = '模型停因不是工具调用，本次夹带的工具调用未执行';
}
