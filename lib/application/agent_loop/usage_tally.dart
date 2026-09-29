import '../../domain/models.dart';
import '../agent_executor.dart' show AgentUsageEvent;

/// 运行级与步级 token 用量累计（原先是 run() 里的 14 个局部变量）。
class UsageTally {
  var _prompt = 0;
  var _completion = 0;
  var _cached = 0;
  var _cacheWrite = 0;
  var _reasoning = 0;
  var _sawUsage = false;
  var _sawCache = false;

  var _stepPrompt = 0;
  var _stepCompletion = 0;
  var _stepCached = 0;
  var _stepCacheWrite = 0;
  var _stepReasoning = 0;
  var _stepUsageReported = false;
  var _stepCacheReported = false;

  /// 新一步开始：清零步级计数（运行级累计保留）。
  void beginStep() {
    _stepPrompt = 0;
    _stepCompletion = 0;
    _stepCached = 0;
    _stepCacheWrite = 0;
    _stepReasoning = 0;
    _stepUsageReported = false;
    _stepCacheReported = false;
  }

  void add(UsageEvent event) {
    _prompt += event.promptTokens;
    _completion += event.completionTokens;
    _cached += event.cachedTokens;
    _cacheWrite += event.cacheWriteTokens;
    _reasoning += event.reasoningTokens;
    _stepPrompt += event.promptTokens;
    _stepCompletion += event.completionTokens;
    _stepCached += event.cachedTokens;
    _stepCacheWrite += event.cacheWriteTokens;
    _stepReasoning += event.reasoningTokens;
    _sawUsage = _sawUsage || event.usageReported;
    _stepUsageReported = _stepUsageReported || event.usageReported;
    if (event.usageReported && event.cacheStatsReported) {
      _sawCache = true;
      _stepCacheReported = true;
    }
  }

  Usage get stepUsage => Usage(
        promptTokens: _stepPrompt,
        completionTokens: _stepCompletion,
        cachedTokens: _stepCached,
        cacheWriteTokens: _stepCacheWrite,
        reasoningTokens: _stepReasoning,
        usageReported: _stepUsageReported,
        cacheStatsReported: _stepCacheReported,
      );

  AgentUsageEvent get totalEvent => AgentUsageEvent(
        promptTokens: _prompt,
        completionTokens: _completion,
        cachedTokens: _cached,
        cacheWriteTokens: _cacheWrite,
        reasoningTokens: _reasoning,
        usageReported: _sawUsage,
        cacheStatsReported: _sawCache,
      );
}
