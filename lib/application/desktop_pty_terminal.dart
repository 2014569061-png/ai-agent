import 'package:xterm/xterm.dart';

/// xterm 4.0 emits its zero-based buffer coordinates verbatim in CPR.
/// ConPTY rejects 0;0 and can leave an interactive shell waiting indefinitely.
/// Fix the protocol boundary rather than rewriting arbitrary keyboard input.
class DesktopPtyTerminal extends Terminal {
  DesktopPtyTerminal({super.maxLines});

  @override
  void sendCursorPosition() {
    onOutput?.call('\x1b[${buffer.cursorY + 1};${buffer.cursorX + 1}R');
  }
}
