import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../../domain/models.dart';
import '../../../domain/history_load_result.dart';
import '../../motion/motion_preferences.dart';
import '../../motion/nexus_motion.dart';
import '../../widgets/speaking_wave.dart';
import 'message_bubble.dart';
import '../../motion/send_flight.dart';

/// 长会话消息列表：完整消息仍由上层持有，列表只按窗口构建可见消息。
class ChatMessageList extends StatefulWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.controller,
    required this.running,
    this.runProgress,
    required this.onLongPress,
    required this.onRegenerate,
    this.onStop,
    this.onEditPrompt,
    this.onSwitchModel,
    this.onResumeRun,
    this.onSpeak,
    this.speakingListenable,
    this.speakingIndexListenable,
    this.selectionIndex,
    this.onExitSelection,
    this.trailingWidgets = const [],
    this.sessionKey,
    this.liveReply,
    this.onLoadOlder,
    this.onLoadHistory,
    this.padding,
  });

  final List<ChatMessage> messages;
  final ScrollController controller;
  final bool running;
  final ChatRunProgress? runProgress;
  final ValueChanged<int> onLongPress;
  final VoidCallback onRegenerate;
  final VoidCallback? onStop;
  final VoidCallback? onEditPrompt;
  final VoidCallback? onSwitchModel;

  /// 暂停提示卡上的「继续执行」（从断点续跑）。
  final VoidCallback? onResumeRun;

  /// 长按朗读（G1）：仅助手消息、且平台支持 TTS 时非空。
  final ValueChanged<int>? onSpeak;
  final ValueListenable<bool>? speakingListenable;

  /// M10：正在朗读的消息索引（null = 未朗读）。提供时每条气泡只在
  /// 自己被朗读时显示「停止朗读」和声波条；未提供时退回 [speakingListenable]。
  final ValueListenable<int?>? speakingIndexListenable;

  /// 处于「文本选择模式」的消息索引（null = 无）。见 MessageBubble.selecting。
  final int? selectionIndex;
  final VoidCallback? onExitSelection;
  final List<Widget> trailingWidgets;
  final String? sessionKey;
  final LiveReply? liveReply;

  /// 内存窗口耗尽（_start 到 0）后向 DB 拉更早一页的回调（B-2 键集分页）。
  /// 返回 true 表示有新页已前插进 [messages]；null/false 表示无更早或未接线。
  final Future<bool> Function()? onLoadOlder;
  final Future<HistoryLoadResult> Function()? onLoadHistory;

  final EdgeInsetsGeometry? padding;

  @override
  State<ChatMessageList> createState() => ChatMessageListState();
}

class ChatMessageListState extends State<ChatMessageList> {
  static const _initialWindow = 40;
  static const _pageSize = 20;
  late int _start;
  bool _loadingOlder = false;
  int _loadEpoch = 0;
  final Set<int> _enteringMessageIndices = <int>{};

  @override
  void initState() {
    super.initState();
    _resetWindow();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sessionChanged = widget.sessionKey != oldWidget.sessionKey;
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
      if (!sessionChanged) _loadEpoch++;
      _loadingOlder = false;
    }
    if (sessionChanged) {
      _loadEpoch++;
      _loadingOlder = false;
      _dbExhausted = false;
      _messageKeys.clear();
    } else if (!identical(widget.messages, oldWidget.messages)) {
      final retainedIds = widget.messages.map((message) => message.id).toSet();
      _messageKeys.removeWhere((id, _) => !retainedIds.contains(id));
    }
    final countDecreased = widget.messages.length < oldWidget.messages.length;
    // DB「加载更早」会把新页前插：窗口起点同步前移，才能保持同一条消息的
    // 全局索引（= ValueKey）恒定、Element 继续复用。用 identical 识别前插，
    // 与「运行中向尾部追加新消息」区分开。
    final delta = widget.messages.length - oldWidget.messages.length;
    final prepended = delta > 0 &&
        oldWidget.messages.isNotEmpty &&
        widget.messages.length > delta &&
        identical(widget.messages[delta], oldWidget.messages[0]);
    if (sessionChanged || countDecreased) {
      _enteringMessageIndices.clear();
      _resetWindow();
    } else if (prepended) {
      _start += delta;
    } else if (delta > 0 &&
        (widget.running || oldWidget.running) &&
        delta <= 2) {
      // 仅给本轮运行中新追加的消息播放一次。历史加载、分页前插和流式
      // 文本更新均不进这里，避免用户阅读中的内容反复闪动。
      for (var index = oldWidget.messages.length;
          index < widget.messages.length;
          index++) {
        _enteringMessageIndices.add(index);
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _resetWindow() {
    _start = (widget.messages.length - _initialWindow)
        .clamp(0, widget.messages.length);
  }

  bool _dbExhausted = false;
  final Map<String, GlobalKey> _messageKeys = {};

  void scrollToMessageId(String? messageId) {
    if (messageId == null) {
      if (widget.controller.hasClients) {
        final duration = MotionPreferences.adjustDuration(
            context, NexusMotion.base,
            listen: false);
        final target = widget.controller.position.maxScrollExtent;
        if (duration == Duration.zero) {
          widget.controller.jumpTo(target);
        } else {
          widget.controller.animateTo(target,
              duration: duration, curve: NexusMotion.curveStandard);
        }
      }
      return;
    }
    final index =
        widget.messages.indexWhere((message) => message.id == messageId);
    if (index < 0) {
      scrollToMessageId(null);
      return;
    }
    if (index < _start) setState(() => _start = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _messageKeys[messageId]?.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          duration: MotionPreferences.adjustDuration(context, NexusMotion.base,
              listen: false),
          curve: NexusMotion.curveStandard,
          alignment: 0.15,
        );
      }
    });
  }

  void _onScroll() {
    if (!widget.controller.hasClients ||
        widget.controller.position.pixels > 80 ||
        _loadingOlder) {
      return;
    }
    if (_start == 0) {
      // 内存窗口已全部展示：转 DB 键集翻页（未接线或已到底则静默停止）。
      if ((widget.onLoadOlder == null && widget.onLoadHistory == null) ||
          _dbExhausted) {
        return;
      }
      _fetchOlderFromDb();
      return;
    }
    _loadingOlder = true;
    final epoch = _loadEpoch;
    final controller = widget.controller;
    final oldStart = _start;
    final oldExtent = widget.controller.position.maxScrollExtent;
    final oldPixels = widget.controller.position.pixels;
    setState(() {
      _start = (oldStart - _pageSize).clamp(0, oldStart);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _loadEpoch || controller != widget.controller) {
        return;
      }
      if (controller.hasClients) {
        final newExtent = widget.controller.position.maxScrollExtent;
        final delta = newExtent - oldExtent;
        if (delta > 0) {
          widget.controller.jumpTo((oldPixels + delta)
              .clamp(0.0, widget.controller.position.maxScrollExtent));
        }
      }
      if (mounted) _loadingOlder = false;
    });
  }

  Future<void> _fetchOlderFromDb() async {
    _loadingOlder = true;
    final epoch = _loadEpoch;
    final controller = widget.controller;
    final oldExtent =
        controller.hasClients ? controller.position.maxScrollExtent : 0.0;
    final oldPixels = controller.hasClients ? controller.position.pixels : 0.0;
    try {
      final result = widget.onLoadHistory != null
          ? await widget.onLoadHistory!()
          : (await widget.onLoadOlder!()
              ? HistoryLoadResult.loaded
              : HistoryLoadResult.exhausted);
      if (!mounted || epoch != _loadEpoch || controller != widget.controller) {
        return;
      }
      if (result == HistoryLoadResult.exhausted) {
        setState(() => _dbExhausted = true);
      }
      if (result != HistoryLoadResult.loaded) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            epoch != _loadEpoch ||
            controller != widget.controller ||
            !controller.hasClients) {
          return;
        }
        final delta = controller.position.maxScrollExtent - oldExtent;
        if (delta > 0) {
          controller.jumpTo((oldPixels + delta)
              .clamp(0.0, controller.position.maxScrollExtent));
        }
      });
    } catch (_) {
      // A load failure is retryable; it must never mark the database exhausted.
    } finally {
      if (mounted && epoch == _loadEpoch) _loadingOlder = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.messages.length - _start;
    final totalCount = count + widget.trailingWidgets.length;
    return ListView.builder(
      controller: widget.controller,
      padding: widget.padding ?? const EdgeInsets.fromLTRB(16, 0, 16, 10),
      itemCount: totalCount,
      // F-4：预渲染视口外 400px，快速滚动时不露白；消息气泡自带独立状态，
      // 关闭自动 KeepAlive 省下不可见子树的存活开销。
      scrollCacheExtent: const ScrollCacheExtent.pixels(400),
      addAutomaticKeepAlives: false,
      itemBuilder: (context, localIndex) {
        if (localIndex >= count) {
          return widget.trailingWidgets[localIndex - count];
        }
        final index = _start + localIndex;
        final storedMessage = widget.messages[index];
        final live = widget.liveReply;
        final message = live != null && live.messageIndex == index
            ? ChatMessage(
                role: storedMessage.role,
                parts: [MessagePart.text(live.text)],
                toolCallId: storedMessage.toolCallId,
                toolCalls: storedMessage.toolCalls,
                modelName: storedMessage.modelName,
                usage: storedMessage.usage,
                elapsed: storedMessage.elapsed,
                ttft: storedMessage.ttft,
                reasoning: live.reasoning,
                reasoningDuration: storedMessage.reasoningDuration,
              )
            : storedMessage;
        final shouldAnimate = _enteringMessageIndices.contains(index);
        final isLast = index == widget.messages.length - 1;
        // S7 节奏：同一轮内气泡间距 12（气泡自带），新一轮用户消息前再加 12，
        // 让「一问一答」成组。始终包 Padding、只改数值，避免切换结构重建子树。
        final beforeNewTurn = !isLast &&
            widget.messages[index + 1].role == MessageRole.user &&
            message.role != MessageRole.user;
        final selecting = widget.selectionIndex == index;
        final bubble = MessageBubble(
          message: message,
          isLast: isLast,
          running: widget.running,
          runProgress: widget.runProgress,
          onLongPress: () => widget.onLongPress(index),
          // Cached bubbles must dispatch to the current parent callbacks.
          onRegenerate: () => widget.onRegenerate(),
          onStop: widget.onStop == null ? null : () => widget.onStop?.call(),
          onEditPrompt: widget.onEditPrompt == null
              ? null
              : () => widget.onEditPrompt?.call(),
          onSwitchModel: widget.onSwitchModel == null
              ? null
              : () => widget.onSwitchModel?.call(),
          onResumeRun: widget.onResumeRun == null
              ? null
              : () => widget.onResumeRun?.call(),
          // 朗读只对助手正文开放（工具气泡与用户消息不提供该读屏动作）。
          onSpeak:
              message.role == MessageRole.assistant && widget.onSpeak != null
                  ? () => widget.onSpeak?.call(index)
                  : null,
          speakingListenable: widget.speakingIndexListenable == null
              ? widget.speakingListenable
              : SpeakingAtIndex(widget.speakingIndexListenable!, index),
          selecting: selecting,
          onExitSelection: widget.onExitSelection == null
              ? null
              : () => widget.onExitSelection?.call(),
        );
        final liveIndex = live?.messageIndex;
        final child = liveIndex == index
            ? bubble
            : _StableHistoryBubble(
                signature: (
                  // ChatMessage is replaced via copyWith when content/metadata
                  // changes. Identity covers attachments, tool arguments and
                  // usage too, without rescanning historical Markdown each frame.
                  storedMessage,
                  widget.sessionKey,
                  index,
                  isLast,
                  selecting,
                  widget.running,
                  isLast ? widget.runProgress : null,
                  widget.onStop != null,
                  widget.onEditPrompt != null,
                  widget.onSwitchModel != null,
                  widget.onResumeRun != null,
                  widget.onSpeak != null,
                  widget.onExitSelection != null,
                  widget.speakingIndexListenable ?? widget.speakingListenable,
                  Theme.of(context),
                  MediaQuery.textScalerOf(context),
                ),
                child: bubble,
              );
        return _MessageEntrance(
          key: message.id == null
              ? ValueKey<int>(index)
              : _messageKeys.putIfAbsent(message.id!, GlobalKey.new),
          animate: shouldAnimate,
          isUser: message.role == MessageRole.user,
          onCompleted: shouldAnimate
              ? () {
                  if (mounted) {
                    setState(() => _enteringMessageIndices.remove(index));
                  }
                }
              : null,
          child: Padding(
            padding: EdgeInsets.only(bottom: beforeNewTurn ? 12 : 0),
            child: child,
          ),
        );
      },
    );
  }
}

/// 历史气泡在 liveReply 刷新时保持同一个 child。
/// 签名不变就跳过 Markdown 重建；正在流式输出的那一条不走这里。
class _StableHistoryBubble extends StatefulWidget {
  const _StableHistoryBubble({
    required this.signature,
    required this.child,
  });

  final Object signature;
  final Widget child;

  @override
  State<_StableHistoryBubble> createState() => _StableHistoryBubbleState();
}

class _StableHistoryBubbleState extends State<_StableHistoryBubble> {
  late Widget _child;
  late Object _signature;

  @override
  void initState() {
    super.initState();
    _child = widget.child;
    _signature = widget.signature;
  }

  @override
  void didUpdateWidget(covariant _StableHistoryBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.signature != _signature) {
      _signature = widget.signature;
      _child = widget.child;
    }
  }

  @override
  Widget build(BuildContext context) => _child;
}

/// A one-shot entrance for a newly appended live message. It deliberately owns
/// no list layout state, so pagination and streaming updates do not replay it.
class _MessageEntrance extends StatefulWidget {
  const _MessageEntrance({
    super.key,
    required this.animate,
    required this.child,
    this.onCompleted,
    this.isUser = false,
  });

  final bool animate;
  final Widget child;
  final VoidCallback? onCompleted;

  /// 用户气泡（M5）：从右下角弹簧升起。为 false 时保持原有淡入 + 上移。
  final bool isUser;

  /// 用户气泡升起的起始位移与起始缩放。
  static const double userRiseOffset = 16;
  static const double userRiseScale = 0.96;

  @override
  State<_MessageEntrance> createState() => _MessageEntranceState();
}

class _MessageEntranceState extends State<_MessageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// L2：用户刚从输入框发送的气泡认领一次「飞出」，从输入框位置飞入。
  SendFlight? _flight;
  bool _claimed = false;

  Duration get _baseDuration =>
      widget.isUser ? NexusMotion.bubbleRise : NexusMotion.base;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _baseDuration,
    );
    _controller.value = widget.animate ? 0.0 : 1.0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_claimed) {
      _claimed = true;
      if (widget.animate &&
          widget.isUser &&
          !MotionPreferences.shouldReduceMotion(context)) {
        _flight = SendFlightBus.claim();
      }
    }
    if (_flight != null) {
      _controller
        ..stop()
        ..value = 1.0;
      return;
    }
    _controller.duration = MotionPreferences.adjustDuration(
      context,
      _baseDuration,
    );
    if (!widget.animate || MotionPreferences.shouldReduceMotion(context)) {
      _controller
        ..stop()
        ..value = 1.0;
    } else if (_controller.value == 0.0 && !_controller.isAnimating) {
      _controller.forward().whenComplete(widget.onCompleted ?? () {});
    }
  }

  @override
  void didUpdateWidget(covariant _MessageEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.animate) {
      _controller
        ..stop()
        ..value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return widget.child;
    }
    if (widget.isUser) {
      final flight = _flight;
      if (flight != null) {
        return SendFlightLanding(
          flight: flight,
          onLanded: widget.onCompleted,
          child: widget.child,
        );
      }
      return _buildUserRise();
    }
    final curve = CurvedAnimation(
      parent: _controller,
      curve: NexusMotion.curveEnter,
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.025),
          end: Offset.zero,
        ).animate(curve),
        child: widget.child,
      ),
    );
  }

  /// 位移与缩放跟随离手弹簧；透明度在前 50% 时长内完成，避免拖尾。
  Widget _buildUserRise() {
    final opacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.5, curve: NexusMotion.curveEnter),
    );
    return FadeTransition(
      opacity: opacity,
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final v = NexusMotion.curveBubbleRise.transform(_controller.value);
          final scale = _MessageEntrance.userRiseScale +
              (1 - _MessageEntrance.userRiseScale) * v;
          return Transform.translate(
            offset: Offset(0, _MessageEntrance.userRiseOffset * (1 - v)),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.bottomRight,
              child: child,
            ),
          );
        },
      ),
    );
  }
}
