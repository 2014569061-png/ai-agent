import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/terminal/ssh_host_key_store.dart';
import 'package:mobile_agent/infrastructure/terminal/ssh_terminal_session.dart';
import 'package:mobile_agent/infrastructure/terminal/termux_ssh_credentials.dart';
import 'package:xterm/xterm.dart';

class _MemoryKnownHosts implements SshKnownHostStore {
  final saved = <String, String>{};
  var failReads = false;
  var failWrites = false;

  String _id(String host, int port) => '$port|${host.toLowerCase()}';

  @override
  Future<String?> readFingerprint(String host, int port) async {
    if (failReads) throw StateError('read failed');
    return saved[_id(host, port)];
  }

  @override
  Future<void> saveFingerprint(String host, int port, String fingerprint) async {
    if (failWrites) throw StateError('write failed');
    saved[_id(host, port)] = fingerprint;
  }
}

void main() {
  test('first host key is trusted and a changed key is rejected', () async {
    final store = _MemoryKnownHosts();
    final verifier = SshHostKeyVerifier(store);
    const host = '127.0.0.1';
    const port = 8022;

    final first = await verifier.decide(
      host: host,
      port: port,
      fingerprint: 'SHA256:first',
    );
    expect(first, SshHostKeyDecision.trustedNew);
    expect(store.saved['8022|127.0.0.1'], 'SHA256:first');

    final same = await verifier.decide(
      host: host,
      port: port,
      fingerprint: 'SHA256:first',
    );
    expect(same, SshHostKeyDecision.trusted);

    final changed = await verifier.decide(
      host: host,
      port: port,
      fingerprint: 'SHA256:changed',
    );
    expect(changed, SshHostKeyDecision.mismatch);
    expect(store.saved['8022|127.0.0.1'], 'SHA256:first');
  });

  test('unknown key can be rejected by the confirm callback', () async {
    final verifier = SshHostKeyVerifier(_MemoryKnownHosts());
    final decision = await verifier.decide(
      host: '127.0.0.1',
      port: 8022,
      fingerprint: 'SHA256:new',
      confirmUnknown: (_) async => false,
    );
    expect(decision, SshHostKeyDecision.rejected);
  });

  test('storage failure fails closed', () async {
    final store = _MemoryKnownHosts()..failReads = true;
    final verifier = SshHostKeyVerifier(store);
    final decision = await verifier.decide(
      host: '127.0.0.1',
      port: 8022,
      fingerprint: 'SHA256:new',
    );
    expect(decision, SshHostKeyDecision.rejected);
  });

  test('session uses the injected verifier before any socket is opened', () async {
    final store = _MemoryKnownHosts();
    final terminal = Terminal(maxLines: 200);
    final session = SSHTerminalSession(
      terminal: terminal,
      config: const SSHTerminalConfig(host: '127.0.0.1', port: 8022),
      hostKeyVerifier: SshHostKeyVerifier(store),
    );

    expect(await session.acceptPresentedHostKey('SHA256:tofu'), isTrue);
    expect(await session.acceptPresentedHostKey('SHA256:tofu'), isTrue);
    expect(await session.acceptPresentedHostKey('SHA256:other'), isFalse);
    expect(session.state, SSHTerminalState.disconnected);
  });
}
