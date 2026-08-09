#include "app_ipc.h"

namespace app_ipc {

namespace {

struct FindContext {
  HWND result;
};

BOOL CALLBACK FindMainWindowProc(HWND hwnd, LPARAM lparam) {
  // GetProp reads across processes — string property names live in the global
  // atom table.
  if (::GetProp(hwnd, kMainWindowProp) == nullptr) {
    return TRUE;
  }
  reinterpret_cast<FindContext*>(lparam)->result = hwnd;
  return FALSE;
}

}  // namespace

bool AcquireSingleInstance() {
  const HANDLE mutex = ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
  if (mutex == nullptr) {
    // Can't tell either way; boot rather than refuse to start.
    return true;
  }
  return ::GetLastError() != ERROR_ALREADY_EXISTS;
}

HWND FindExistingMainWindow(DWORD timeout_ms) {
  constexpr DWORD kPollIntervalMs = 100;
  // Counted loop, not a GetTickCount deadline, which breaks on the tick wrap.
  const DWORD attempts = (timeout_ms / kPollIntervalMs) + 1;
  for (DWORD i = 0; i < attempts; ++i) {
    FindContext ctx{nullptr};
    ::EnumWindows(&FindMainWindowProc, reinterpret_cast<LPARAM>(&ctx));
    if (ctx.result != nullptr) {
      return ctx.result;
    }
    ::Sleep(kPollIntervalMs);
  }
  return nullptr;
}

bool SendOpenFileRequest(HWND target, const std::wstring& path) {
  // Without this the target's SetForegroundWindow is ignored by the foreground
  // lock and the note opens behind whatever is on top.
  DWORD pid = 0;
  ::GetWindowThreadProcessId(target, &pid);
  if (pid != 0) {
    ::AllowSetForegroundWindow(pid);
  }

  COPYDATASTRUCT payload{};
  payload.dwData = kCopyDataOpenFile;
  // Includes the terminating NUL so the receiver can bound the string.
  payload.cbData = static_cast<DWORD>((path.size() + 1) * sizeof(wchar_t));
  payload.lpData = const_cast<wchar_t*>(path.c_str());

  // Timeout variant: a wedged target must not leave a stuck ghost process.
  DWORD_PTR result = 0;
  return ::SendMessageTimeoutW(target, WM_COPYDATA, 0,
                               reinterpret_cast<LPARAM>(&payload),
                               SMTO_ABORTIFHUNG, 5000, &result) != 0;
}

std::wstring FileArgumentFromCommandLine() {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::wstring();
  }

  std::wstring found;
  for (int i = 1; i < argc && found.empty(); ++i) {
    const DWORD attrs = ::GetFileAttributesW(argv[i]);
    if (attrs != INVALID_FILE_ATTRIBUTES &&
        (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0) {
      found.assign(argv[i]);
    }
  }

  ::LocalFree(argv);
  return found;
}

}  // namespace app_ipc
