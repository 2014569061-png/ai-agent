#include "desktop_host.h"
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include "resource.h"

namespace {
constexpr UINT kTrayMessage = WM_APP + 0x64;
constexpr UINT kPtyClosedMessage = WM_APP + 0x65;
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
std::string StringArg(const Map& args, const char* name) {
  auto it = args.find(Value(name));
  if (it == args.end()) return {};
  auto value = std::get_if<std::string>(&it->second);
  return value ? *value : std::string();
}
int IntArg(const Map& args, const char* name, int fallback) {
  auto it = args.find(Value(name));
  if (it == args.end()) return fallback;
  auto value = std::get_if<int32_t>(&it->second);
  return value ? *value : fallback;
}
std::wstring Wide(const std::string& text) {
  int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring out(size, 0);
  if (size) MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), out.data(), size);
  return out;
}
void Close(HANDLE& handle) { if (handle && handle != INVALID_HANDLE_VALUE) CloseHandle(handle); handle = nullptr; }
}

// Independent reader and writer keep ConPTY teardown and large pastes from
// blocking Flutter's platform thread. Only bounded buffers cross the channel.
class PtySession {
 public:
  HANDLE input = nullptr, output = nullptr, process = nullptr, job = nullptr;
  HPCON console = nullptr;
  std::atomic<bool> stopping{false};
  std::atomic<uint64_t> written_bytes{0};
  std::atomic<DWORD> write_error{ERROR_SUCCESS};
  std::thread reader, writer;
  std::mutex output_mutex, input_mutex;
  std::condition_variable input_ready;
  std::vector<uint8_t> bytes;
  std::deque<std::string> pending;
  size_t pending_bytes = 0;
  std::string start_error;
  bool Fail(const char* stage, DWORD code) {
    if (start_error.empty()) start_error = std::string(stage) + " (Windows error " + std::to_string(code) + ")";
    return false;
  }
  ~PtySession() {
    stopping = true;
    input_ready.notify_all();
    if (job) TerminateJobObject(job, 0);
    if (process) TerminateProcess(process, 0);
    // Termination is asynchronous. Do not acknowledge close while descendants
    // still hold the workspace directory (or the console's pipe endpoints).
    if (process) WaitForSingleObject(process, 5000);
    if (job) {
      const ULONGLONG deadline = GetTickCount64() + 5000;
      JOBOBJECT_BASIC_ACCOUNTING_INFORMATION accounting{};
      while (QueryInformationJobObject(job, JobObjectBasicAccountingInformation,
                 &accounting, sizeof(accounting), nullptr) &&
             accounting.ActiveProcesses && GetTickCount64() < deadline) {
        Sleep(10);
      }
    }
    if (writer.joinable()) CancelSynchronousIo(writer.native_handle());
    if (console) { ClosePseudoConsole(console); console = nullptr; }
    if (reader.joinable()) { CancelSynchronousIo(reader.native_handle()); reader.join(); }
    if (writer.joinable()) writer.join();
    Close(input); Close(output); Close(process); Close(job);
  }
  bool Start(const std::wstring& cwd, int cols, int rows, bool cmd) {
    HANDLE input_read = nullptr, output_write = nullptr;
    if (!CreatePipe(&input_read, &input, nullptr, 0)) return Fail("CreatePipe(input)", GetLastError());
    if (!CreatePipe(&output, &output_write, nullptr, 0)) {
      const DWORD error = GetLastError(); Close(input_read); return Fail("CreatePipe(output)", error);
    }
    HRESULT hr = CreatePseudoConsole(COORD{static_cast<SHORT>(cols), static_cast<SHORT>(rows)}, input_read, output_write, 0, &console);
    Close(input_read); Close(output_write);
    if (FAILED(hr)) return Fail("CreatePseudoConsole", static_cast<DWORD>(hr));
    // Drain output even when subsequent process/job setup fails: closing a
    // pseudoconsole may synchronously flush output and must have a live reader.
    reader = std::thread([this]() {
      uint8_t chunk[8192]; DWORD count;
      while (ReadFile(output, chunk, sizeof(chunk), &count, nullptr) && count) {
        std::lock_guard<std::mutex> lock(output_mutex);
        constexpr size_t limit = 2 * 1024 * 1024;
        if (bytes.size() + count > limit) bytes.erase(bytes.begin(), bytes.begin() + std::min(bytes.size(), static_cast<size_t>(count)));
        bytes.insert(bytes.end(), chunk, chunk + count);
      }
    });
    SIZE_T size = 0;
    InitializeProcThreadAttributeList(nullptr, 1, 0, &size);
    std::vector<uint8_t> storage(size);
    STARTUPINFOEXW startup{};
    startup.StartupInfo.cb = sizeof(startup);
    // Do not duplicate redirected parent stdio into the child. ConPTY must
    // bind all three streams; bInheritHandles=FALSE alone is insufficient.
    // See microsoft/terminal discussion #15814. Handles stay explicitly null.
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup.lpAttributeList = reinterpret_cast<PPROC_THREAD_ATTRIBUTE_LIST>(storage.data());
    if (!InitializeProcThreadAttributeList(startup.lpAttributeList, 1, 0, &size)) return Fail("InitializeProcThreadAttributeList", GetLastError());
    bool attributed = UpdateProcThreadAttribute(startup.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, console, sizeof(console), nullptr, nullptr) != FALSE;
    if (!attributed) {
      const DWORD error = GetLastError(); DeleteProcThreadAttributeList(startup.lpAttributeList);
      return Fail("UpdateProcThreadAttribute", error);
    }
    wchar_t system[MAX_PATH];
    GetSystemDirectoryW(system, MAX_PATH);
    std::wstring exe = std::wstring(system) + (cmd ? L"\\cmd.exe" : L"\\WindowsPowerShell\\v1.0\\powershell.exe");
    std::wstring command = L"\"" + exe + (cmd ? L"\" /d /k chcp 65001" :
        L"\" -NoLogo -NoProfile -NoExit -Command \"[Console]::InputEncoding = [System.Text.UTF8Encoding]::new(); [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()\"");
    PROCESS_INFORMATION info{};
    bool created = attributed && CreateProcessW(exe.c_str(), command.data(), nullptr, nullptr, FALSE,
        EXTENDED_STARTUPINFO_PRESENT | CREATE_SUSPENDED, nullptr, cwd.c_str(), &startup.StartupInfo, &info);
    const DWORD create_error = created ? ERROR_SUCCESS : GetLastError();
    DeleteProcThreadAttributeList(startup.lpAttributeList);
    if (!created) return Fail("CreateProcessW", create_error);
    process = info.hProcess;
    job = CreateJobObjectW(nullptr, nullptr);
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    bool managed = job && SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits)) && AssignProcessToJobObject(job, process);
    if (!managed) {
      const DWORD error = GetLastError(); TerminateProcess(process, 1); CloseHandle(info.hThread);
      return Fail("AssignProcessToJobObject / SetInformationJobObject", error);
    }
    writer = std::thread([this]() {
      while (!stopping) {
        std::string text;
        {
          std::unique_lock<std::mutex> lock(input_mutex);
          input_ready.wait(lock, [this] { return stopping || !pending.empty(); });
          if (stopping) break;
          text = std::move(pending.front()); pending.pop_front(); pending_bytes -= text.size();
        }
        size_t offset = 0;
        while (offset < text.size() && !stopping) {
          DWORD count = 0;
          if (!WriteFile(input, text.data() + offset, static_cast<DWORD>(std::min<size_t>(4096, text.size() - offset)), &count, nullptr)) {
            write_error = GetLastError(); break;
          }
          if (!count) break;
          written_bytes += count;
          offset += count;
        }
      }
    });
    const DWORD resumed = ResumeThread(info.hThread);
    const DWORD resume_error = resumed == static_cast<DWORD>(-1) ? GetLastError() : ERROR_SUCCESS;
    CloseHandle(info.hThread);
    if (resume_error != ERROR_SUCCESS) return Fail("ResumeThread", resume_error);
    return true;
  }
};

struct PtyClose {
  std::unique_ptr<PtySession> session;
  std::unique_ptr<flutter::MethodResult<Value>> result;
  std::thread worker;
  ~PtyClose() { if (worker.joinable()) worker.join(); }
};

DesktopHost::DesktopHost(flutter::BinaryMessenger* messenger, HWND window) : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(messenger, "nexus/desktop_host", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto* supplied = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
    const Map empty;
    const Map& args = supplied ? *supplied : empty;
    const auto method = call.method_name();
    if (method == "openTerminal") {
      const auto cwd = Wide(StringArg(args, "cwd"));
      if (cwd.empty() || GetFileAttributesW(cwd.c_str()) == INVALID_FILE_ATTRIBUTES) {
        result->Error("terminal_directory", "工作目录不存在"); return;
      }
      auto session = std::make_unique<PtySession>();
      if (!session->Start(cwd, std::clamp(IntArg(args, "cols", 100), 2, 500), std::clamp(IntArg(args, "rows", 30), 2, 300), StringArg(args, "shell") == "cmd")) {
        result->Error("terminal_start", "无法启动 Windows ConPTY: " + session->start_error); return;
      }
      int id = next_id_++; sessions_[id] = std::move(session); result->Success(Value(id)); return;
    }
    if (method == "readTerminal" || method == "writeTerminal" || method == "resizeTerminal" || method == "closeTerminal") {
      int id = IntArg(args, "id", -1);
      auto it = sessions_.find(id);
      if (it == sessions_.end()) { result->Error("terminal_closed", "终端已关闭"); return; }
      auto& session = *it->second;
      if (method == "closeTerminal") {
        auto closing = std::make_unique<PtyClose>();
        closing->session = std::move(it->second);
        closing->result = std::move(result);
        sessions_.erase(it);
        auto* operation = closing.get();
        closing_[id] = std::move(closing);
        const HWND window = window_;
        operation->worker = std::thread([operation, window, id]() {
          operation->session.reset();
          PostMessage(window, kPtyClosedMessage, static_cast<WPARAM>(id), 0);
        });
        return;
      }
      if (method == "readTerminal") {
        std::vector<uint8_t> chunk;
        { std::lock_guard<std::mutex> lock(session.output_mutex);
          size_t count = std::min<size_t>(session.bytes.size(), 65536);
          chunk.assign(session.bytes.begin(), session.bytes.begin() + count);
          session.bytes.erase(session.bytes.begin(), session.bytes.begin() + count);
        }
        DWORD code = STILL_ACTIVE; GetExitCodeProcess(session.process, &code);
        result->Success(Value(Map{{Value("bytes"), Value(chunk)},
          {Value("exitCode"), Value(static_cast<int64_t>(code))},
          {Value("writtenBytes"), Value(static_cast<int64_t>(session.written_bytes.load()))},
          {Value("writeError"), Value(static_cast<int64_t>(session.write_error.load()))}}));
      } else if (method == "writeTerminal") {
        auto text = StringArg(args, "text");
        { std::lock_guard<std::mutex> lock(session.input_mutex);
          if (session.pending_bytes + text.size() > 1024 * 1024) { result->Error("terminal_busy", "输入过大，请稍后重试"); return; }
          session.pending_bytes += text.size(); session.pending.push_back(std::move(text));
        }
        session.input_ready.notify_one(); result->Success();
      } else {
        HRESULT hr = ResizePseudoConsole(session.console, COORD{static_cast<SHORT>(std::clamp(IntArg(args, "cols", 100), 2, 500)), static_cast<SHORT>(std::clamp(IntArg(args, "rows", 30), 2, 300))});
        if (FAILED(hr)) result->Error("terminal_resize", "无法调整终端尺寸"); else result->Success();
      }
      return;
    }
    if (method == "configure") {
      close_to_tray_ = IntArg(args, "closeToTray", 0) != 0;
      SetTray(close_to_tray_);
      result->Success(); return;
    }
    if (method == "clipboardImage") {
      if (!OpenClipboard(window_)) { result->Error("clipboard_busy", "剪贴板正在使用中"); return; }
      UINT png = RegisterClipboardFormatW(L"PNG");
      HANDLE data = GetClipboardData(png);
      bool is_png = data != nullptr;
      if (!data) data = GetClipboardData(CF_DIB);
      std::vector<uint8_t> bytes;
      if (data) {
        SIZE_T size = GlobalSize(data);
        auto* source = static_cast<uint8_t*>(GlobalLock(data));
        if (source && size > 0 && size <= 20 * 1024 * 1024) {
          if (is_png) bytes.assign(source, source + size);
          else if (size >= sizeof(BITMAPINFOHEADER)) {
            auto* info = reinterpret_cast<BITMAPINFOHEADER*>(source);
            DWORD colors = info->biClrUsed ? info->biClrUsed : (info->biBitCount <= 8 ? (1u << info->biBitCount) : 0);
            size_t pixel_offset = info->biSize + colors * sizeof(RGBQUAD);
            if (info->biSize == sizeof(BITMAPINFOHEADER) && info->biCompression == BI_BITFIELDS) pixel_offset += 12;
            if (pixel_offset <= size) {
              BITMAPFILEHEADER header{}; header.bfType = 0x4d42; header.bfSize = static_cast<DWORD>(sizeof(header) + size); header.bfOffBits = static_cast<DWORD>(sizeof(header) + pixel_offset);
              bytes.resize(sizeof(header) + size); memcpy(bytes.data(), &header, sizeof(header)); memcpy(bytes.data() + sizeof(header), source, size);
            }
          }
        }
        if (source) GlobalUnlock(data);
      }
      CloseClipboard();
      result->Success(bytes.empty() ? Value() : Value(bytes)); return;
    }
    if (method == "notify") {
      if (!tray_added_) SetTray(true);
      NOTIFYICONDATAW icon{}; icon.cbSize = sizeof(icon); icon.hWnd = window_; icon.uID = 1; icon.uFlags = NIF_INFO;
      auto title = Wide(StringArg(args, "title")), body = Wide(StringArg(args, "body"));
      wcsncpy_s(icon.szInfoTitle, title.c_str(), _TRUNCATE); wcsncpy_s(icon.szInfo, body.c_str(), _TRUNCATE); icon.dwInfoFlags = NIIF_INFO;
      Shell_NotifyIconW(NIM_MODIFY, &icon); result->Success(); return;
    }
    result->NotImplemented();
  });
  DragAcceptFiles(window_, TRUE);
}
DesktopHost::~DesktopHost() { SetTray(false); sessions_.clear(); closing_.clear(); }
void DesktopHost::SetTray(bool enabled) {
  if (enabled == tray_added_) return;
  NOTIFYICONDATAW icon{}; icon.cbSize = sizeof(icon); icon.hWnd = window_; icon.uID = 1;
  icon.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP; icon.uCallbackMessage = kTrayMessage;
  icon.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(icon.szTip, L"NEXUS Agent");
  if (Shell_NotifyIconW(enabled ? NIM_ADD : NIM_DELETE, &icon)) tray_added_ = enabled;
}
std::optional<LRESULT> DesktopHost::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == kPtyClosedMessage) {
    auto it = closing_.find(static_cast<int>(wparam));
    if (it != closing_.end()) {
      if (it->second->worker.joinable()) it->second->worker.join();
      it->second->result->Success();
      closing_.erase(it);
    }
    return 0;
  }
  if (message == WM_CLOSE && close_to_tray_) { ShowWindow(window_, SW_HIDE); return 0; }
  if (message == kTrayMessage) {
    if (lparam == WM_LBUTTONUP || lparam == NIN_BALLOONUSERCLICK) { ShowWindow(window_, SW_RESTORE); SetForegroundWindow(window_); }
    if (lparam == WM_RBUTTONUP) {
      HMENU menu = CreatePopupMenu(); AppendMenuW(menu, MF_STRING, 1, L"打开 NEXUS"); AppendMenuW(menu, MF_STRING, 2, L"退出并停止任务");
      POINT point; GetCursorPos(&point); SetForegroundWindow(window_);
      int selected = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY, point.x, point.y, 0, window_, nullptr); DestroyMenu(menu);
      if (selected == 1) { ShowWindow(window_, SW_RESTORE); SetForegroundWindow(window_); }
      if (selected == 2) { close_to_tray_ = false; PostMessage(window_, WM_CLOSE, 0, 0); }
    }
    return 0;
  }
  if (message == WM_DROPFILES) {
    HDROP drop = reinterpret_cast<HDROP>(wparam); flutter::EncodableList paths;
    UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
    for (UINT i = 0; i < count && i < 20; ++i) {
      UINT size = DragQueryFileW(drop, i, nullptr, 0); std::wstring path(size + 1, 0); DragQueryFileW(drop, i, path.data(), size + 1); path.resize(size);
      int bytes = WideCharToMultiByte(CP_UTF8, 0, path.data(), static_cast<int>(path.size()), nullptr, 0, nullptr, nullptr);
      std::string utf8(bytes, 0); WideCharToMultiByte(CP_UTF8, 0, path.data(), static_cast<int>(path.size()), utf8.data(), bytes, nullptr, nullptr); paths.emplace_back(utf8);
    }
    DragFinish(drop); channel_->InvokeMethod("filesDropped", std::make_unique<Value>(paths)); return 0;
  }
  return std::nullopt;
}
