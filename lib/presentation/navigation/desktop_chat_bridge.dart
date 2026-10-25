import 'package:flutter/foundation.dart';

/// Desktop chrome delegates to the chat page so draft/attachment transitions
/// and the existing session configuration dialogs remain the source of truth.
class DesktopChatBridge {
  Future<void> Function()? newConversation;
  Future<void> Function(String)? switchConversation;
  VoidCallback? sessionSettings;
  VoidCallback? openDrawer;
  ValueChanged<String>? insertPrompt;

  void clear() {
    newConversation = null;
    switchConversation = null;
    sessionSettings = null;
    openDrawer = null;
    insertPrompt = null;
  }
}
