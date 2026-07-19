#include "flutter_window.h"

#include <commctrl.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

#pragma comment(lib, "comctl32.lib")

namespace {
// Value of tpcshrd.h's MICROSOFT_TABLETPENSERVICE_PROPERTY macro.
constexpr const wchar_t* kTabletPenServiceProperty =
    L"MicrosoftTabletPenServiceProperty";
// WM_TABLET_DEFBASE (0x02C0) + 12: the tablet service asks the window
// which system gestures to keep before showing press-and-hold & co.
constexpr UINT kTabletQuerySystemGestureStatus = 0x02CC;
// tpcshrd.h TABLET_DISABLE_*: PRESSANDHOLD | PENTAPFEEDBACK |
// PENBARRELFEEDBACK | FLICKS.
constexpr DWORD_PTR kDisablePenFeedback =
    0x00000001 | 0x00000008 | 0x00000010 | 0x00010000;
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }
  // NOTE: we deliberately do NOT call EnableMouseInPointer(TRUE)
  // here. Flutter's Windows runner reads MOUSE input from the
  // legacy WM_LBUTTONDOWN / WM_MOUSEMOVE messages, and forcing
  // mouse-in-pointer routes them through WM_POINTER instead —
  // Flutter then loses every click and the window appears frozen.
  // Pen events still arrive via WM_POINTER on Win10+ without the
  // opt-in (pens are pointer-aware by default on the OS side).

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
  child_hwnd_ = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(child_hwnd_);

  // Pen-button bridge — see header. Mounted once the engine is alive so
  // the MethodChannel has a valid messenger; nothing is sent until the
  // first WM_POINTER* with a pen pointer type arrives.
  pen_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "handwriter/pen_input",
          &flutter::StandardMethodCodec::GetInstance());

  // Pointer messages are routed to the window UNDER the cursor — on
  // Flutter Windows that's the renderer CHILD HWND, not the
  // top-level FlutterWindow we subclass below. Hook a WindowProc
  // subclass on the child so HandlePenPointerMessage actually sees
  // WM_POINTER* from the digitizer.
  if (child_hwnd_) {
    SetWindowSubclass(child_hwnd_, &FlutterWindow::ChildSubclassProc,
                      /*subclass_id=*/1,
                      reinterpret_cast<DWORD_PTR>(this));
  }

  // Kill the Windows pen system gestures on the canvas: hovering or
  // drawing slowly makes the shell show its press-and-hold ring (the
  // "closing circle" animation = hold for right-click) and can delay or
  // swallow slow strokes. The per-window opt-out is this window property
  // (note: the VALUE of tpcshrd.h's MICROSOFT_TABLETPENSERVICE_PROPERTY
  // macro, "MicrosoftTabletPenServiceProperty" — not the macro name),
  // read by the tablet input service. Flag values from tpcshrd.h:
  // PRESSANDHOLD 0x01, PENTAPFEEDBACK 0x08, PENBARRELFEEDBACK 0x10,
  // FLICKS 0x10000. WM_TABLET_QUERYSYSTEMGESTURESTATUS is also answered
  // with the same flags in the window procs below — some Windows builds
  // only honour one of the two mechanisms.
  const HANDLE feedback_flags = reinterpret_cast<HANDLE>(kDisablePenFeedback);
  SetProp(GetHandle(), kTabletPenServiceProperty, feedback_flags);
  if (child_hwnd_) {
    SetProp(child_hwnd_, kTabletPenServiceProperty, feedback_flags);
  }

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
  // Window properties must be removed before the window is destroyed.
  RemoveProp(GetHandle(), kTabletPenServiceProperty);
  if (child_hwnd_) {
    RemoveProp(child_hwnd_, kTabletPenServiceProperty);
    RemoveWindowSubclass(child_hwnd_, &FlutterWindow::ChildSubclassProc, 1);
    child_hwnd_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

// static
LRESULT CALLBACK FlutterWindow::ChildSubclassProc(HWND hwnd, UINT msg,
                                                  WPARAM wparam,
                                                  LPARAM lparam,
                                                  UINT_PTR /*subclass_id*/,
                                                  DWORD_PTR ref_data) {
  if (msg == kTabletQuerySystemGestureStatus) {
    return kDisablePenFeedback;
  }
  auto* self = reinterpret_cast<FlutterWindow*>(ref_data);
  if (self) {
    switch (msg) {
      case WM_POINTERDOWN:
      case WM_POINTERUPDATE:
      case WM_POINTERUP:
        self->HandlePenPointerMessage(msg, wparam);
        break;
      default:
        break;
    }
  }
  return DefSubclassProc(hwnd, msg, wparam, lparam);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {

  if (message == kTabletQuerySystemGestureStatus) {
    return kDisablePenFeedback;
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

void FlutterWindow::HandlePenPointerMessage(UINT message, WPARAM wparam) {
  if (!pen_channel_) return;

  const UINT32 pointer_id = GET_POINTERID_WPARAM(wparam);
  POINTER_INPUT_TYPE pointer_type = PT_POINTER;
  if (!GetPointerType(pointer_id, &pointer_type)) return;
  if (pointer_type != PT_PEN) return;

  POINTER_PEN_INFO pen_info{};
  if (!GetPointerPenInfo(pointer_id, &pen_info)) return;

  // PEN_FLAG_BARREL is the lower side button. Gaomon (and most
  // Huion-class tablets) report the upper button by flipping
  // PEN_FLAG_INVERTED — same flag the OS would set if the user
  // flipped the pen to use the eraser end. Both are emitted in the
  // standard WM_POINTERUPDATE stream, even when the pen is just
  // hovering (no tip contact) over the window.
  const bool barrel_now = (pen_info.penFlags & PEN_FLAG_BARREL) != 0;
  const bool tip_in_contact =
      (pen_info.pointerInfo.pointerFlags & POINTER_FLAG_INCONTACT) != 0;
  const bool first_button_pen =
      (pen_info.pointerInfo.pointerFlags & POINTER_FLAG_FIRSTBUTTON) != 0;
  last_pen_pointer_id_ = pointer_id;

  // Latch the Gaomon-driverless upper-barrel state via the
  // pressure-zero signature. On this hardware the upper side button
  // reports identically to a real tip touch in `pointerFlags`:
  // FIRSTBUTTON + INCONTACT + INRANGE + DOWN all set, same
  // ButtonChangeType (FIRSTBUTTON_DOWN). The ONLY distinguishing
  // field is `pressure` — a physical tip touch always registers
  // non-zero (even the lightest tap reads ~30-150 out of 1024)
  // because the pen has a pressure sensor, while the upper button
  // is a discrete switch with no sensor and reports pressure=0.
  // We latch on the FIRSTBUTTON 0→1 transition when pressure is
  // exactly 0, and keep the latch alive until FIRSTBUTTON drops —
  // so the override survives the user touching the tip mid-gesture
  // (pressure rises to >0 then, but the latch stays on).
  if (first_button_pen && !last_first_button_pen_) {
    upper_button_latched_ = (pen_info.pressure == 0);
  }
  if (!first_button_pen) {
    upper_button_latched_ = false;
  }
  last_first_button_pen_ = first_button_pen;

  const bool inverted_now =
      ((pen_info.penFlags & PEN_FLAG_INVERTED) != 0) || upper_button_latched_;

  // Gate the pen-gesture flow on REAL tip contact (INCONTACT bit AND
  // non-zero pressure), not the bit alone. The Gaomon driverless
  // upper-button click sets INCONTACT even though the tip isn't
  // actually touching, which would otherwise start an eraser stroke
  // at the cursor the moment the user presses the upper barrel —
  // even before they bring the pen down. Pressure>0 ensures we only
  // fire bridge-pen events when the user is genuinely drawing on the
  // surface.
  const bool real_tip_contact = tip_in_contact && (pen_info.pressure > 0);

  // Compute current logical client coordinates once — used for any
  // pen-gesture phase we forward below.
  //
  // SUB-PIXEL: `ptPixelLocation` is integer screen pixels. The
  // digitizer's real resolution lives in `ptHimetricLocation`
  // (0.01 mm units); GetPointerDeviceRects gives the himetric→display
  // mapping, yielding float screen coordinates. Zoomed out, the
  // integer staircase (±0.5 px ≈ 1-2 page units) otherwise renders as
  // a wavy stroke. Falls back to the integer position if the API
  // fails (e.g. sourceDevice gone).
  double screen_x = static_cast<double>(pen_info.pointerInfo.ptPixelLocation.x);
  double screen_y = static_cast<double>(pen_info.pointerInfo.ptPixelLocation.y);
  RECT device_rect{}, display_rect{};
  if (GetPointerDeviceRects(pen_info.pointerInfo.sourceDevice, &device_rect,
                            &display_rect)) {
    const double dev_w =
        static_cast<double>(device_rect.right) - device_rect.left;
    const double dev_h =
        static_cast<double>(device_rect.bottom) - device_rect.top;
    if (dev_w > 0 && dev_h > 0) {
      const auto& him = pen_info.pointerInfo.ptHimetricLocation;
      screen_x = display_rect.left +
                 (him.x - device_rect.left) *
                     (static_cast<double>(display_rect.right) -
                      display_rect.left) /
                     dev_w;
      screen_y = display_rect.top +
                 (him.y - device_rect.top) *
                     (static_cast<double>(display_rect.bottom) -
                      display_rect.top) /
                     dev_h;
    }
  }
  POINT client_origin{0, 0};
  if (child_hwnd_) ClientToScreen(child_hwnd_, &client_origin);
  const UINT dpi = child_hwnd_ ? GetDpiForWindow(child_hwnd_) : 96;
  const double dpr = dpi > 0 ? dpi / 96.0 : 1.0;
  const double x_logical = (screen_x - client_origin.x) / dpr;
  const double y_logical = (screen_y - client_origin.y) / dpr;
  const double pressure_norm = pen_info.pressure > 0
      ? static_cast<double>(pen_info.pressure) / 1024.0
      : 0.5;

  // Stream the sub-pixel sample BEFORE any gesture bookkeeping so the
  // Dart cache is already fresh when the engine's own (integer)
  // pointer event for this same WM_POINTER message reaches the canvas.
  NotifyPenPos(x_logical, y_logical, real_tip_contact, pressure_norm);

  // End an active pen gesture FIRST (before announcing the button
  // release) so Dart's _onBarrelPen still has access to the
  // override-target tool when it commits the lasso / eraser stroke.
  const bool button_releasing =
      (last_barrel_pressed_ && !barrel_now) ||
      (last_inverted_ && !inverted_now);
  if (pen_gesture_active_ && (!real_tip_contact || button_releasing)) {
    NotifyBarrelPen("up", x_logical, y_logical, pressure_norm);
    pen_gesture_active_ = false;
  }

  if (barrel_now != last_barrel_pressed_) {
    NotifyBarrelChange("barrel", barrel_now);
    last_barrel_pressed_ = barrel_now;
  }
  if (inverted_now != last_inverted_) {
    NotifyBarrelChange("inverted", inverted_now);
    last_inverted_ = inverted_now;
  }

  // While a side button is held and the tip is in contact, Gaomon
  // driverless never delivers a Flutter PointerEvent — the canvas
  // Listener stays silent and the lasso/eraser never sees the
  // gesture. Synthesise the down/move/up sequence from the raw
  // WM_POINTER stream we already read above; Dart's _onBarrelPen
  // drives the override directly from these.
  const bool any_button_held = last_barrel_pressed_ || last_inverted_;
  if (any_button_held && real_tip_contact) {
    if (!pen_gesture_active_) {
      pen_gesture_active_ = true;
      NotifyBarrelPen("down", x_logical, y_logical, pressure_norm);
    } else {
      NotifyBarrelPen("move", x_logical, y_logical, pressure_norm);
    }
  }

  last_tip_in_contact_ = tip_in_contact;

  // No defensive cleanup on WM_POINTERUP: the previous version
  // force-released the barrel on every tip-lift, which caused a
  // spurious flap (barrel goes false → next hover update sees
  // PEN_FLAG_BARREL still set → fires true again, 5 ms later) and
  // dropped `_activeNativeBarrel` mid-gesture. The actual barrel
  // state is now tracked exclusively through penFlags transitions
  // above. If the pen leaves the digitizer entirely the Dart side
  // simply stays in override-mode until the user returns the pen,
  // at which point a fresh transition restores the correct state.
}

void FlutterWindow::NotifyBarrelChange(const std::string& button, bool down) {
  if (!pen_channel_) return;
  flutter::EncodableMap args = {
      {flutter::EncodableValue("button"), flutter::EncodableValue(button)},
      {flutter::EncodableValue("down"), flutter::EncodableValue(down)},
  };
  pen_channel_->InvokeMethod(
      "onBarrelChange",
      std::make_unique<flutter::EncodableValue>(args));
}

void FlutterWindow::NotifyPenPos(double x, double y, bool contact,
                                 double pressure) {
  if (!pen_channel_) return;
  flutter::EncodableMap args = {
      {flutter::EncodableValue("x"), flutter::EncodableValue(x)},
      {flutter::EncodableValue("y"), flutter::EncodableValue(y)},
      {flutter::EncodableValue("contact"), flutter::EncodableValue(contact)},
      {flutter::EncodableValue("pressure"), flutter::EncodableValue(pressure)},
  };
  pen_channel_->InvokeMethod(
      "onPenPos", std::make_unique<flutter::EncodableValue>(args));
}

void FlutterWindow::NotifyBarrelPen(const std::string& phase, double x,
                                    double y, double pressure) {
  if (!pen_channel_) return;
  flutter::EncodableMap args = {
      {flutter::EncodableValue("phase"), flutter::EncodableValue(phase)},
      {flutter::EncodableValue("x"), flutter::EncodableValue(x)},
      {flutter::EncodableValue("y"), flutter::EncodableValue(y)},
      {flutter::EncodableValue("pressure"), flutter::EncodableValue(pressure)},
  };
  pen_channel_->InvokeMethod(
      "onBarrelPen",
      std::make_unique<flutter::EncodableValue>(args));
}
