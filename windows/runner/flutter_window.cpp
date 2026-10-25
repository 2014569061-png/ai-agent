#include "flutter_window.h"

#include <optional>
#include <tlhelp32.h>
#include <flutter/standard_method_codec.h>
#include <flutter/method_result_functions.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr UINT kPreparedClose = WM_APP + 0x4E;
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  desktop_host_ = std::make_unique<DesktopHost>(flutter_controller_->engine()->messenger(), GetHandle());
  lifecycle_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "nexus/desktop_lifecycle",
      &flutter::StandardMethodCodec::GetInstance());
  owned_process_job_ = CreateJobObject(nullptr, nullptr);
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (owned_process_job_ && !SetInformationJobObject(owned_process_job_,
      JobObjectExtendedLimitInformation, &limits, sizeof(limits))) {
    CloseHandle(owned_process_job_);
    owned_process_job_ = nullptr;
  }
  process_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "nexus/desktop_process",
      &flutter::StandardMethodCodec::GetInstance());
  process_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "trackProcess") {
      result->NotImplemented();
      return;
    }
    const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
    DWORD pid = 0;
    if (arguments) {
      const auto entry = arguments->find(flutter::EncodableValue("pid"));
      if (entry != arguments->end()) {
        if (const auto* value = std::get_if<int32_t>(&entry->second)) {
          if (*value > 0) pid = static_cast<DWORD>(*value);
        } else if (const auto* value64 = std::get_if<int64_t>(&entry->second)) {
          if (*value64 > 0 && *value64 <= MAXDWORD) pid = static_cast<DWORD>(*value64);
        }
      }
    }
    // Only a direct child may be managed. A supplied PID cannot enroll an
    // unrelated user's process into the application's termination job.
    bool owned = false;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot != INVALID_HANDLE_VALUE) {
      PROCESSENTRY32 entry{};
      entry.dwSize = sizeof(entry);
      if (Process32First(snapshot, &entry)) {
        do {
          if (entry.th32ProcessID == pid) {
            owned = entry.th32ParentProcessID == GetCurrentProcessId();
            break;
          }
        } while (Process32Next(snapshot, &entry));
      }
      CloseHandle(snapshot);
    }
    HANDLE process = owned ? OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE,
                                        FALSE, pid) : nullptr;
    const bool assigned = process && owned_process_job_ &&
        AssignProcessToJobObject(owned_process_job_, process);
    if (process) CloseHandle(process);
    if (assigned) result->Success();
    else result->Error("process_tracking", "Unable to manage this child process");
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  desktop_host_ = nullptr;
  lifecycle_channel_ = nullptr;
  process_channel_ = nullptr;
  if (owned_process_job_) {
    CloseHandle(owned_process_job_);
    owned_process_job_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (desktop_host_) {
    auto handled = desktop_host_->HandleMessage(message, wparam, lparam);
    if (handled) return *handled;
  }
  // WebView2 owns additional native windows. Ask the framework to release its
  // resources explicitly before destroying the Flutter engine, even when this
  // host is not considered the last window by the engine's lifecycle manager.
  if (message == kPreparedClose) {
    return Win32Window::MessageHandler(hwnd, WM_CLOSE, 0, 0);
  }
  if (message == WM_CLOSE && lifecycle_channel_) {
    if (close_requested_) return 0;
    close_requested_ = true;
    auto finish = [this, hwnd](bool allow) {
      if (allow) PostMessage(hwnd, kPreparedClose, 0, 0);
      else close_requested_ = false;
    };
    lifecycle_channel_->InvokeMethod("prepareClose", nullptr,
        std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
            [finish](const flutter::EncodableValue* response) {
              const auto* allow = response ? std::get_if<bool>(response) : nullptr;
              finish(!allow || *allow);
            },
            [finish](const std::string&, const std::string&,
                     const flutter::EncodableValue*) { finish(true); },
            [finish]() { finish(true); }));
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
