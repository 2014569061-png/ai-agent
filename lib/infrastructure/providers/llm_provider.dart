import 'package:dio/dio.dart' show CancelToken;

import '../../domain/models.dart';

abstract interface class LlmProvider {
  /// 流式请求模型。传入 [cancelToken] 时，调用方可真正中止底层 HTTP 流
  /// （Provider 收到取消后应静默结束，不产出错误事件）。
  Stream<UnifiedEvent> stream(UnifiedRequest request, {CancelToken? cancelToken});
}

class DemoProvider implements LlmProvider {
  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request, {CancelToken? cancelToken}) async* {
    const response = '这是演示响应。配置真实 Provider 后，这里将替换为模型的流式输出。';
    for (final character in response.split('')) {
      if (cancelToken?.isCancelled ?? false) return;
      await Future<void>.delayed(const Duration(milliseconds: 12));
      yield TextDeltaEvent(character);
    }
    yield const CompletedEvent();
  }
}
