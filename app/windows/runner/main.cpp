#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr const wchar_t kWindowTitle[] = L"WeLearn 助手";
// Local\ 命名空间按登录会话隔离：同一用户只允许一个实例，
// 不同 Windows 用户仍可各自运行。
constexpr const wchar_t kSingleInstanceMutex[] =
    L"Local\\WeLearnAssistant.SingleInstance";

// 第二个进程只负责把已有窗口提到前台，不再创建 Flutter 引擎，
// 避免重复登录、重复扫描课程。
void FocusExistingWindow(HWND window) {
  if (::IsIconic(window)) {
    ::ShowWindow(window, SW_RESTORE);
  } else {
    ::ShowWindow(window, SW_SHOW);
  }
  ::SetForegroundWindow(window);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // 先按窗口 class + 标题查找旧实例；兼容还没有 mutex 的 1.0.1 版本。
  HWND existing = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW",
                               kWindowTitle);
  if (existing != nullptr) {
    FocusExistingWindow(existing);
    return EXIT_SUCCESS;
  }

  HANDLE instance_mutex =
      ::CreateMutex(nullptr, TRUE, kSingleInstanceMutex);
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    existing = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", kWindowTitle);
    if (existing != nullptr) {
      FocusExistingWindow(existing);
    }
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kWindowTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (instance_mutex != nullptr) {
    ::CloseHandle(instance_mutex);
  }
  return EXIT_SUCCESS;
}
