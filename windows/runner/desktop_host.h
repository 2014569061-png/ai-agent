#ifndef NEXUS_DESKTOP_HOST_H_
#define NEXUS_DESKTOP_HOST_H_
#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <memory>
#include <optional>
#include <map>
class PtySession;
struct PtyClose;
class DesktopHost {
 public:
  DesktopHost(flutter::BinaryMessenger* messenger, HWND window);
  ~DesktopHost();
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);
 private:
  HWND window_;
  bool close_to_tray_ = false;
  bool tray_added_ = false;
  int next_id_ = 1;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::map<int, std::unique_ptr<PtySession>> sessions_;
  std::map<int, std::unique_ptr<PtyClose>> closing_;
  void SetTray(bool enabled);
};
#endif
