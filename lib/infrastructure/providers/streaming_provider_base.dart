import 'package:dio/dio.dart';

import '../../domain/models.dart';
import 'llm_provider.dart';
import 'sse_decoder.dart';

/// 三个流式 Provider 的同构骨架（B-3）：
/// 发起 `ResponseType.stream` 请求 → 驱动 [SseDecoder]（含 close flush）→
/// 每行 SSE 数据交给 [runStreaming.onFrame] 解析并产出协议相关事件 → 流结束后由
/// [runStreaming.finalize] 产出收尾事件（工具调用 / 用量 / 完成态）。
///
/// 协议差异刻意保留在各子类：OpenAI 的 `reasoning_content` 与 finish_reason
/// 逐帧记录、Anthropic 的 `thinking` 分帧与 usage 合成、Gemini 的 `thought`
/// part 与 finishReason 枚举 —— 分帧解析绝不上提到基类。
///
/// 错误边界（DioException / catch-all）同样不上提：三家现有的错误文案不同
/// （OpenAI 带 `HTTP <status>` 与响应体摘要，Anthropic/Gemini 用
/// `data.toString()`），由各子类 stream() 自行 try/catch 保持现状。
abstract class StreamingProviderBase implements LlmProvider {
  StreamingProviderBase(this.dio);

  final Dio dio;

  /// 统一 SSE 驱动。抛出的异常交给调用方的错误边界处理（与旧实现一致）。
  Stream<UnifiedEvent> runStreaming({
    required String url,
    required Map<String, dynamic> payload,
    required Map<String, dynamic> headers,
    required CancelToken? cancelToken,
    required List<UnifiedEvent> Function(String data) onFrame,
    required List<UnifiedEvent> Function() finalize,
  }) async* {
    final response = await dio.post<ResponseBody>(
      url,
      data: payload,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: headers,
      ),
    );
    final stream = response.data?.stream;
    if (stream == null) {
      yield const ProviderErrorEvent(
        'Provider 返回了空响应',
        failureKind: 'protocol',
      );
      return;
    }

    final sse = SseDecoder();
    await for (final chunk in stream) {
      for (final event in _consume(sse.add(chunk), onFrame)) {
        yield event;
      }
    }
    // 未终止记录 flush（正确性依赖 SseDecoder 的行缓冲语义）。
    for (final event in _consume(sse.close(), onFrame)) {
      yield event;
    }
    for (final event in finalize()) {
      yield event;
    }
  }

  static Iterable<UnifiedEvent> _consume(
    Iterable<String> frames,
    List<UnifiedEvent> Function(String data) onFrame,
  ) sync* {
    for (final data in frames) {
      yield* onFrame(data);
    }
  }
}
