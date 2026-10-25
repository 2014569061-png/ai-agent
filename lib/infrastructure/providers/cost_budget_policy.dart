import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CostBudgetPolicy {
  const CostBudgetPolicy({
    required this.dailyLimitCents,
    required this.monthlyLimitCents,
    required this.hardStopEnabled,
    this.currencyCode = 'CNY',
  });

  final int dailyLimitCents;
  final int monthlyLimitCents;
  final bool hardStopEnabled;
  final String currencyCode;
}

class CostBudgetEvaluation {
  const CostBudgetEvaluation({
    required this.allowed,
    this.errorCode,
    required this.dailySpentCents,
    required this.monthlySpentCents,
    required this.dailyLimitCents,
    required this.monthlyLimitCents,
    required this.hardStopEnabled,
    required this.reason,
    this.dailyReservedCents = 0,
    this.monthlyReservedCents = 0,
    this.unpricedPendingRequests = 0,
  });

  final bool allowed;
  final String? errorCode;
  final int dailySpentCents;
  final int monthlySpentCents;
  final int dailyLimitCents;
  final int monthlyLimitCents;
  final bool hardStopEnabled;
  final String reason;

  /// Included in spent totals, but not confirmed provider charges.
  final int dailyReservedCents;
  final int monthlyReservedCents;
  final int unpricedPendingRequests;
  int get dailySettledCents => dailySpentCents - dailyReservedCents;
  int get monthlySettledCents => monthlySpentCents - monthlyReservedCents;

  int get remainingDailyCents =>
      (dailyLimitCents - dailySpentCents).clamp(0, dailyLimitCents);

  int get remainingMonthlyCents =>
      (monthlyLimitCents - monthlySpentCents).clamp(0, monthlyLimitCents);
}

class CostBudgetService {
  const CostBudgetService();

  static const String _dailyKey = 'nexus.cost_budget.daily_cents';
  static const String _monthlyKey = 'nexus.cost_budget.monthly_cents';
  static const String _hardStopKey = 'nexus.cost_budget.hard_stop';
  static const String _policyKey = 'nexus.cost_budget.policy_v1';

  Future<CostBudgetPolicy> loadPolicy() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_policyKey);
    if (encoded != null) {
      final data = jsonDecode(encoded) as Map<String, dynamic>;
      return CostBudgetPolicy(
          dailyLimitCents: data['daily'] as int,
          monthlyLimitCents: data['monthly'] as int,
          hardStopEnabled: data['hardStop'] as bool);
    }
    return CostBudgetPolicy(
      dailyLimitCents: prefs.getInt(_dailyKey) ?? 2000, // 默认 ¥20.00 / 日
      monthlyLimitCents: prefs.getInt(_monthlyKey) ?? 30000, // 默认 ¥300.00 / 月
      hardStopEnabled: prefs.getBool(_hardStopKey) ?? true,
    );
  }

  Future<CostBudgetPolicy> savePolicy({
    required int dailyLimitCents,
    required int monthlyLimitCents,
    required bool hardStopEnabled,
  }) async {
    if (dailyLimitCents <= 0 || monthlyLimitCents <= 0) {
      throw const FormatException('日预算与月预算必须大于 0 分');
    }
    if (dailyLimitCents > monthlyLimitCents) {
      throw const FormatException('日预算不能高于月预算');
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
        _policyKey,
        jsonEncode({
          'daily': dailyLimitCents,
          'monthly': monthlyLimitCents,
          'hardStop': hardStopEnabled,
        }))) {
      throw StateError('费用预算未能保存');
    }
    return CostBudgetPolicy(
      dailyLimitCents: dailyLimitCents,
      monthlyLimitCents: monthlyLimitCents,
      hardStopEnabled: hardStopEnabled,
    );
  }

  static CostBudgetEvaluation evaluatePolicy({
    required CostBudgetPolicy policy,
    required int dailySpentCents,
    required int monthlySpentCents,
    int estimatedNextCallCents = 0,
    int dailyReservedCents = 0,
    int monthlyReservedCents = 0,
    int unpricedPendingRequests = 0,
  }) {
    if (policy.dailyLimitCents <= 0 ||
        policy.monthlyLimitCents <= 0 ||
        unpricedPendingRequests < 0 ||
        dailySpentCents < 0 ||
        monthlySpentCents < 0 ||
        estimatedNextCallCents < 0 ||
        dailyReservedCents < 0 ||
        dailyReservedCents > dailySpentCents ||
        monthlyReservedCents < 0 ||
        monthlyReservedCents > monthlySpentCents) {
      throw const FormatException('费用预算与花费必须是有效的非负金额');
    }
    if (policy.hardStopEnabled && unpricedPendingRequests > 0) {
      return CostBudgetEvaluation(
          allowed: false,
          errorCode: 'COST_PRICING_UNAVAILABLE',
          dailySpentCents: dailySpentCents,
          monthlySpentCents: monthlySpentCents,
          dailyLimitCents: policy.dailyLimitCents,
          monthlyLimitCents: policy.monthlyLimitCents,
          hardStopEnabled: true,
          dailyReservedCents: dailyReservedCents,
          monthlyReservedCents: monthlyReservedCents,
          unpricedPendingRequests: unpricedPendingRequests,
          reason: '本月有未定价的待确认请求，请先按账单核对，不能按零费用继续硬停预算');
    }
    final projectedDaily = dailySpentCents + estimatedNextCallCents;
    final projectedMonthly = monthlySpentCents + estimatedNextCallCents;
    if (projectedDaily > policy.dailyLimitCents ||
        dailySpentCents >= policy.dailyLimitCents) {
      return CostBudgetEvaluation(
        allowed: !policy.hardStopEnabled,
        errorCode: policy.hardStopEnabled ? 'COST_BUDGET_EXHAUSTED' : null,
        dailySpentCents: dailySpentCents,
        dailyReservedCents: dailyReservedCents,
        monthlyReservedCents: monthlyReservedCents,
        unpricedPendingRequests: unpricedPendingRequests,
        monthlySpentCents: monthlySpentCents,
        dailyLimitCents: policy.dailyLimitCents,
        monthlyLimitCents: policy.monthlyLimitCents,
        hardStopEnabled: policy.hardStopEnabled,
        reason: policy.hardStopEnabled
            ? '已触发日费用硬停（当日预计 ${projectedDaily / 100.0} 元，日上限 ${policy.dailyLimitCents / 100.0} 元）'
            : '已超出日费用预算预警线',
      );
    }
    if (projectedMonthly > policy.monthlyLimitCents ||
        monthlySpentCents >= policy.monthlyLimitCents) {
      return CostBudgetEvaluation(
        allowed: !policy.hardStopEnabled,
        errorCode: policy.hardStopEnabled ? 'COST_BUDGET_EXHAUSTED' : null,
        dailySpentCents: dailySpentCents,
        monthlySpentCents: monthlySpentCents,
        dailyLimitCents: policy.dailyLimitCents,
        monthlyLimitCents: policy.monthlyLimitCents,
        hardStopEnabled: policy.hardStopEnabled,
        reason: policy.hardStopEnabled
            ? '已触发月费用硬停（当月预计 ${projectedMonthly / 100.0} 元，月上限 ${policy.monthlyLimitCents / 100.0} 元）'
            : '已超出月费用预算预警线',
        dailyReservedCents: dailyReservedCents,
        monthlyReservedCents: monthlyReservedCents,
        unpricedPendingRequests: unpricedPendingRequests,
      );
    }
    return CostBudgetEvaluation(
      allowed: true,
      dailySpentCents: dailySpentCents,
      dailyReservedCents: dailyReservedCents,
      monthlyReservedCents: monthlyReservedCents,
      unpricedPendingRequests: unpricedPendingRequests,
      monthlySpentCents: monthlySpentCents,
      dailyLimitCents: policy.dailyLimitCents,
      monthlyLimitCents: policy.monthlyLimitCents,
      hardStopEnabled: policy.hardStopEnabled,
      reason: '费用处于预算水位内',
    );
  }
}
