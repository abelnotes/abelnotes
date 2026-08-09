#ifndef RUNNER_APP_IPC_H_
#define RUNNER_APP_IPC_H_

#include <windows.h>

#include <string>

// Single-instance guard and "open this file" plumbing.
//
// Windows starts a fresh process for every file activation (double-click on a
// .ncnote, shell "Open with"). Two instances writing the same SQLite database
// and notebook directory under Documents is a corruption risk, so the second
// process never builds an engine: it forwards its file argument to the mutex
// owner over WM_COPYDATA and exits.
//
// Enforced in every build mode: Debug and Release share one notebook store, so
// two instances are more dangerous across modes, not less.
namespace app_ipc {

// "Local\" scopes the mutex to the logon session (and, under MSIX, to the
// package namespace) so each user gets their own instance.
constexpr const wchar_t* kSingleInstanceMutex =
    L"Local\\AbelNotes.SingleInstance.v1";

// The runner's window CLASS is "FLUTTER_RUNNER_WIN32_WINDOW", shared by every
// Flutter Windows app, so it can't identify our window. This property can.
constexpr const wchar_t* kMainWindowProp = L"AbelNotesMainWindow";

// COPYDATASTRUCT::dwData tag, so unrelated WM_COPYDATA is never acted on.
constexpr DWORD_PTR kCopyDataOpenFile = 0x41424E31;  // 'ABN1'

// True if this process is the first instance and should boot normally. The
// handle is left open for the process lifetime by design.
bool AcquireSingleInstance();

// Polls for the running instance's window, which may not exist yet — that
// process takes the mutex before creating it. nullptr if it never appears.
HWND FindExistingMainWindow(DWORD timeout_ms);

// Sends |path| as WM_COPYDATA and hands over foreground rights. An empty
// |path| means "just surface the window".
bool SendOpenFileRequest(HWND target, const std::wstring& path);

// The file to open from this process's command line, or empty. Only existing
// files qualify, so a stray `--flag` is never taken for a document.
std::wstring FileArgumentFromCommandLine();

}  // namespace app_ipc

#endif  // RUNNER_APP_IPC_H_
