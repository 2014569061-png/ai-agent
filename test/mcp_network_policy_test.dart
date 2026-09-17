import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/network_access_policy.dart';
import 'package:mobile_agent/infrastructure/mcp/mcp_server_config.dart';
import 'package:mobile_agent/infrastructure/mcp/mcp_tool_provider.dart';

/// MCP 出口安全回归测试（P0 #3）。
///
/// 背景：MCP 有两条出口，此前都**没有任何准入检查**——
/// 1. `StreamableHttpClientTransport` 直接 `Uri.parse(server.url)` 连接，
///    完全不走 `NetworkAccessPolicy`，于是 `http://192.168.1.1/mcp` 这类
///    内网地址可以被当成"工具服务器"接进来；
/// 2. `StdioClientTransport` 直接 spawn 用户填写的任意命令，且
///    `includeParentEnvironment: true` 会把 App 进程的环境变量（含用户
///    配置的 Provider API Key）全量透传给子进程。
///
/// 本文件锁定三件事：
/// * 私网 / 回环 / 元数据地址一律不可作为 MCP HTTP 端点；
/// * stdio 在真机开关关闭时不可用（默认关闭）；
/// * stdio 子进程不继承父环境变量。
void main() {
  const policy = NetworkAccessPolicy();

  McpServerConfig httpServer(String url) => McpServerConfig(
        id: 'test-http',
        name: '测试 HTTP',
        kind: McpServerKind.http,
        url: url,
      );

  McpServerConfig stdioServer() => const McpServerConfig(
        id: 'test-stdio',
        name: '测试 STDIO',
        kind: McpServerKind.stdio,
        command: 'echo',
        args: ['hi'],
      );

  group('MCP HTTP 端点必须过 NetworkAccessPolicy', () {
    // 这些地址正是「MCP 出口无策略」时可以被接进来的目标。
    const blocked = <String>[
      'http://127.0.0.1:8000/mcp', // 旧版 App 自带的预设，必须被拒
      'http://localhost:8000/mcp',
      'http://10.0.0.1/mcp',
      'http://172.16.0.1/mcp',
      'http://192.168.1.1/mcp',
      'http://169.254.169.254/latest/meta-data/', // 云元数据服务
      'http://[::1]:8000/mcp',
      'file:///etc/passwd',
    ];

    for (final url in blocked) {
      test('拒绝 $url', () {
        expect(policy.inspect(url).allowed, isFalse, reason: url);
      });
    }

    test('公网地址放行', () {
      expect(policy.inspect('https://mcp.example.com/mcp').allowed, isTrue);
    });

    test('connectAndListTools 对私网地址不会发起连接', () async {
      final provider = McpToolProvider(stdioEnabled: false);
      final tools = await provider.connectAndListTools(
        httpServer('http://192.168.1.1/mcp'),
      );
      expect(tools, isEmpty);
      expect(provider.lastBlockReason, isNotNull);
      expect(provider.lastBlockReason, contains('192.168.1.1'));
    });

    test('testConnection 对私网地址给出可读原因而不是抛异常', () async {
      final provider = McpToolProvider(stdioEnabled: false);
      final result = await provider.testConnection(
        httpServer('http://127.0.0.1:8000/mcp'),
      );
      expect(result.ok, isFalse);
      expect(result.toolCount, 0);
      expect(result.error, isNotNull);
      expect(result.error, contains('本机'));
    });

    test('空 URL 被拒绝', () async {
      final provider = McpToolProvider(stdioEnabled: false);
      final result = await provider.testConnection(httpServer(''));
      expect(result.ok, isFalse);
    });
  });

  group('stdio 门禁', () {
    test('真机开关关闭时不可用（默认关闭）', () {
      expect(McpStdioAvailability.isUsable(enabled: false), isFalse);
      expect(McpStdioAvailability.blockedReason(enabled: false), isNotNull);
    });

    test('真机开关开启后可用', () {
      expect(McpStdioAvailability.isUsable(enabled: true), isTrue);
      expect(McpStdioAvailability.blockedReason(enabled: true), isNull);
    });

    test('开关关闭时 connectAndListTools 不 spawn 进程', () async {
      final provider = McpToolProvider(stdioEnabled: false);
      final tools = await provider.connectAndListTools(stdioServer());
      expect(tools, isEmpty);
      expect(provider.lastBlockReason, isNotNull);
    });

    test('开关关闭时 testConnection 直接返回不可用', () async {
      final provider = McpToolProvider(stdioEnabled: false);
      final result = await provider.testConnection(stdioServer());
      expect(result.ok, isFalse);
      expect(result.error, isNotNull);
    });
  });

  group('stdio 子进程环境隔离', () {
    test('生产代码不把父环境变量透传给子进程', () {
      // `StdioServerParameters` 是 mcp_dart 的不可变配置对象，Provider 内部
      // 即刻消费、没有可观测的中间态，所以这里用**源码级约束**来锁：
      // 一旦有人把 includeParentEnvironment 改回 true（或删掉这一行），
      // App 进程的 Provider API Key 就会随子进程一起泄露。
      final source = File(
        'lib/infrastructure/mcp/mcp_tool_provider.dart',
      ).readAsStringSync();

      expect(
        source,
        isNot(contains('includeParentEnvironment: true')),
        reason: 'stdio 子进程不得继承 App 进程环境变量',
      );
      expect(
        RegExp(r'includeParentEnvironment:\s*false').allMatches(source).length,
        2,
        reason: 'connectAndListTools 与 testConnection 两条路径都要隔离',
      );
    });
  });

  group('NetworkAccessPolicy 边界（IPv4 映射与私网段）', () {
    test('IPv4 映射的 IPv6 回环也被拒绝', () {
      expect(policy.inspect('http://[::ffff:127.0.0.1]/').allowed, isFalse);
    });

    test('IPv4 映射的 IPv6 私网也被拒绝', () {
      expect(policy.inspect('http://[::ffff:192.168.0.1]/').allowed, isFalse);
    });

    test('IPv6 唯一本地地址 fc00::/7 被拒绝', () {
      expect(policy.inspect('http://[fd00::1]/').allowed, isFalse);
    });

    test('172.32.x.x 不在私网段内，应放行', () {
      expect(policy.inspect('http://172.32.0.1/').allowed, isTrue);
    });
  });
}
