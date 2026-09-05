import 'package:dio/dio.dart';

class BillingApiException implements Exception {
  const BillingApiException(this.message, {this.statusCode, this.code});
  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}

/// 后端账户会话令牌（内存持有，secure storage 持久化由 AccountService 负责）。
class AccountSession {
  const AccountSession(
      {required this.userId,
      required this.apiKey,
      required this.access,
      required this.refresh});
  final int userId;
  final String apiKey;
  final String access;
  final String refresh;

  bool get isLoggedIn => access.isNotEmpty;

  AccountSession copyWith(
          {int? userId, String? apiKey, String? access, String? refresh}) =>
      AccountSession(
        userId: userId ?? this.userId,
        apiKey: apiKey ?? this.apiKey,
        access: access ?? this.access,
        refresh: refresh ?? this.refresh,
      );
}

/// 账户 API 响应模型。
class BalanceInfo {
  const BalanceInfo({required this.balanceCents, this.transactions = const []});
  final int balanceCents;
  final List<Map<String, dynamic>> transactions;
}

class UsageDaily {
  const UsageDaily(
      {required this.day,
      required this.promptTokens,
      required this.completionTokens,
      required this.cachedTokens,
      required this.spendCents,
      required this.costCents});
  final String day;
  final int promptTokens;
  final int completionTokens;
  final int cachedTokens;
  final int spendCents;
  final int costCents;
  int get totalTokens => promptTokens + completionTokens;
  int get calls => 1;
}

class UsageReport {
  const UsageReport(
      {this.summary = const {}, this.daily = const [], this.models = const []});
  final Map<String, dynamic> summary;
  final List<UsageDaily> daily;
  final List<Map<String, dynamic>> models;
  bool get isEmpty => daily.isEmpty && models.isEmpty;
}

class OrderInfo {
  const OrderInfo(
      {required this.outTradeNo,
      required this.amountCents,
      required this.codeUrl,
      required this.status});
  final String outTradeNo;
  final int amountCents;
  final String codeUrl;
  final String status;
}

/// 后端 `/v1` HTTP 客户端。baseUrl 与 access token 可在运行时替换/注入。
class BillingApi {
  BillingApi({required this.baseUrl, Dio? dio}) : _dio = dio ?? Dio();

  final String baseUrl;
  final Dio _dio;

  static const _defaultHeaders = {'accept': 'application/json'};

  Options _auth(String access) =>
      Options(headers: {..._defaultHeaders, 'authorization': 'Bearer $access'});

  /// 注册（邮箱或手机号）。
  Future<AccountSession> register(
      {String? email,
      String? phone,
      required String password,
      String deviceId = 'default'}) async {
    final r = await _dio.post<Map<String, dynamic>>('$baseUrl/v1/auth/register',
        data: {
          if (email != null) 'email': email,
          if (phone != null) 'phone': phone,
          'password': password
        },
        options:
            Options(headers: {..._defaultHeaders, 'x-device-id': deviceId}));
    final j = r.data!;
    return AccountSession(
      userId: j['userId'] as int,
      apiKey: j['apiKey'] as String,
      access: j['tokens']['access'] as String,
      refresh: j['tokens']['refresh'] as String,
    );
  }

  /// 登录。返回会话或 tfaRequired（需二次校验）。
  Future<({AccountSession? session, String? pendingToken})> login(
      {String? email,
      String? phone,
      required String password,
      String deviceId = 'default',
      String? code}) async {
    final r = await _dio.post<Map<String, dynamic>>('$baseUrl/v1/auth/login',
        data: {
          if (email != null) 'email': email,
          if (phone != null) 'phone': phone,
          'password': password,
          if (code != null) 'code': code
        },
        options:
            Options(headers: {..._defaultHeaders, 'x-device-id': deviceId}));
    final j = r.data!;
    if (j['tfaRequired'] == true) {
      return (session: null, pendingToken: j['pendingToken'] as String);
    }
    final t = j['tokens'] as Map<String, dynamic>;
    return (
      session: AccountSession(
          userId: 0,
          apiKey: (j['apiKey'] as String?) ?? '',
          access: t['access'] as String,
          refresh: t['refresh'] as String),
      pendingToken: null,
    );
  }

  /// 2FA 二次校验（pending → 令牌）。
  Future<AccountSession> verify2fa(
      {required String pendingToken,
      required String code,
      String deviceId = 'default'}) async {
    final r = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/v1/auth/2fa/verify',
        data: {'pendingToken': pendingToken, 'code': code},
        options:
            Options(headers: {..._defaultHeaders, 'x-device-id': deviceId}));
    final t = r.data!['tokens'] as Map<String, dynamic>;
    return AccountSession(
        userId: 0,
        apiKey: '',
        access: t['access'] as String,
        refresh: t['refresh'] as String);
  }

  /// 刷新访问令牌。
  Future<AccountSession> refresh(
      {required String refresh, required int userId}) async {
    final r = await _dio.post<Map<String, dynamic>>('$baseUrl/v1/auth/refresh',
        data: {'refresh': refresh}, options: _auth(refresh));
    final t = r.data!['tokens'] as Map<String, dynamic>;
    return AccountSession(
        userId: userId,
        apiKey: '',
        access: t['access'] as String,
        refresh: t['refresh'] as String);
  }

  Future<BalanceInfo> balance({required String access}) async {
    final r = await _dio.get<Map<String, dynamic>>('$baseUrl/v1/balance',
        options: _auth(access));
    final j = r.data!;
    return BalanceInfo(
        balanceCents: j['balanceCents'] as int,
        transactions: List<Map<String, dynamic>>.from(j['transactions'] ?? []));
  }

  Future<UsageReport> usage({required String access}) async {
    final r = await _dio.get<Map<String, dynamic>>('$baseUrl/v1/usage',
        options: _auth(access));
    final j = r.data!;
    return UsageReport(
      summary: Map<String, dynamic>.from(j['summary'] as Map? ?? const {}),
      daily: (j['daily'] as List? ?? [])
          .map((d) => UsageDaily(
                day: d['day'] as String,
                promptTokens: (d['prompt_tokens'] as num?)?.toInt() ?? 0,
                completionTokens:
                    (d['completion_tokens'] as num?)?.toInt() ?? 0,
                cachedTokens: (d['cached_tokens'] as num?)?.toInt() ?? 0,
                spendCents: (d['spend_cents'] as num?)?.toInt() ?? 0,
                costCents: (d['cost_cents'] as num?)?.toInt() ?? 0,
              ))
          .toList(),
      models: List<Map<String, dynamic>>.from(j['models'] ?? []),
    );
  }

  /// 创建充值订单（tier: '5'|'10'|'30'|'50'，或直接 amountCents）。
  Future<OrderInfo> createOrder(
      {required String access, String? tier, int? amountCents}) async {
    final r = await _dio.post<Map<String, dynamic>>('$baseUrl/v1/orders',
        data: {
          if (tier != null) 'tier': tier,
          if (amountCents != null) 'amountCents': amountCents
        },
        options: _auth(access));
    final j = r.data!;
    return OrderInfo(
        outTradeNo: j['outTradeNo'] as String,
        amountCents: j['amountCents'] as int,
        codeUrl: j['codeUrl'] as String,
        status: 'pending');
  }

  /// 轮询订单状态。
  Future<OrderInfo> pollOrder(
      {required String access, required String id}) async {
    final r = await _dio.get<Map<String, dynamic>>('$baseUrl/v1/orders/$id',
        options: _auth(access));
    final j = r.data!;
    return OrderInfo(
        outTradeNo: j['out_trade_no'] as String,
        amountCents: j['amount_cents'] as int,
        codeUrl: '',
        status: j['status'] as String);
  }

  /// 模拟支付回调（mock 模式）。真实模式由客户端引导用户在支付 App 完成。
  Future<void> mockPay({required String outTradeNo}) async {
    await _dio.post<Map<String, dynamic>>('$baseUrl/v1/webhook/pay',
        data: {'outTradeNo': outTradeNo},
        options: Options(headers: _defaultHeaders));
  }

  /// 设备列表 / 远程下线。
  Future<List<Map<String, dynamic>>> devices({required String access}) async {
    final r = await _dio.get<List<dynamic>>('$baseUrl/v1/auth/devices',
        options: _auth(access));
    return List<Map<String, dynamic>>.from(r.data!);
  }

  Future<void> revokeDevice({required String access, required int id}) async {
    await _dio.delete('$baseUrl/v1/auth/devices/$id', options: _auth(access));
  }

  /// 注销账号。
  Future<void> deleteAccount({required String access}) async {
    await _dio.delete('$baseUrl/v1/auth', options: _auth(access));
  }

  /// Feature Flag / 远程配置（匿名）。
  Future<Map<String, dynamic>> fetchConfig(
      {String appVersion = '0.0.0'}) async {
    final r = await _dio.get<Map<String, dynamic>>('$baseUrl/v1/config',
        options: Options(
            headers: {..._defaultHeaders, 'x-app-version': appVersion}));
    return (r.data!['config'] as Map<String, dynamic>?) ?? const {};
  }

  /// 意见反馈。
  Future<void> feedback(
      {required String access,
      required String content,
      String? category}) async {
    await _dio.post<Map<String, dynamic>>('$baseUrl/v1/feedback',
        data: {'content': content, if (category != null) 'category': category},
        options: _auth(access));
  }
}
