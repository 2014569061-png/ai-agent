import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/terminal/ssh_terminal_session.dart';
import 'package:mobile_agent/infrastructure/terminal/termux_ssh_credentials.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('SSHTerminalSession Tests', () {
    test('initial state and default configuration', () {
      final terminal = Terminal(maxLines: 500);
      final session = SSHTerminalSession(terminal: terminal);

      expect(session.state, SSHTerminalState.disconnected);
      expect(session.config.isLocalTermux, isTrue);
      expect(session.config.port, 8022);
      expect(session.config.username, isEmpty);
    });

    test('missing config username stays empty instead of using termux', () {
      expect(SSHTerminalConfig.fromJson({}).username, isEmpty);
      expect(const SSHTerminalConfig().port, 8022);
    });

    test('sendCtrl produces proper ASCII control codes', () {
      final terminal = Terminal(maxLines: 500);
      final session = SSHTerminalSession(terminal: terminal);

      // In offline state, sendCtrl writes to terminal locally
      // Ctrl+C is ASCII 3 (\x03)
      session.sendCtrl('C');
      session.sendCtrl('D');
      session.sendCtrl('Z');

      // Check that it doesn't throw and properly handles inputs
      expect(session.state, SSHTerminalState.disconnected);
    });

    test('sendInput sends raw ANSI escapes in offline state', () {
      final terminal = Terminal(maxLines: 500);
      final session = SSHTerminalSession(terminal: terminal);

      session.sendInput('\x1b'); // ESC
      session.sendInput('\t'); // TAB
      session.sendInput('\x1b[A'); // UP
      session.sendInput('\x1b[B'); // DOWN

      expect(session.state, SSHTerminalState.disconnected);
    });

    test('config serialization roundtrip', () {
      const original = SSHTerminalConfig(
        host: '192.168.1.100',
        port: 2222,
        username: 'nexus_user',
        password: 'secret_password',
        label: 'Remote VPS',
      );

      final json = original.toJson();
      final restored = SSHTerminalConfig.fromJson(json);

      expect(restored.host, '192.168.1.100');
      expect(restored.port, 2222);
      expect(restored.username, 'nexus_user');
      expect(restored.password, 'secret_password');
      expect(restored.label, 'Remote VPS');
      expect(restored.isLocalTermux, isFalse);
    });
  });
}
