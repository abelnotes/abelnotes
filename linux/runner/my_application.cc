#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // Pen-pressure bridge. Flutter's Linux GTK embedder never reads the
  // stylus axes, so PointerEvent.pressure is always 0 on Linux (see
  // flutter/flutter#63209). We observe GDK motion events ourselves, pull
  // GDK_AXIS_PRESSURE / XTILT / YTILT, and stream them to Dart over this
  // channel. The Dart side (LinuxPenPressure) caches the latest sample and
  // the canvas pointer handlers use it to override the missing pressure.
  FlMethodChannel* pen_channel;  // owned
  // Window-control bridge (fullscreen for presentation mode). Kept in the
  // runner instead of the window_manager plugin: that plugin hooks GTK
  // window signals and raced the embedder during teardown, crashing on
  // app close with "invalid unclassed pointer in cast to 'FlView'".
  FlMethodChannel* window_channel;  // owned
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Forward one stylus sample (pressure + tilt) to Dart over the pen channel.
static void send_pen_sample(MyApplication* self, gdouble x, gdouble y,
                            gdouble pressure, gdouble tilt_x, gdouble tilt_y) {
  if (self->pen_channel == nullptr) return;

  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "x", fl_value_new_float(x));
  fl_value_set_string_take(args, "y", fl_value_new_float(y));
  fl_value_set_string_take(args, "pressure", fl_value_new_float(pressure));
  fl_value_set_string_take(args, "tiltX", fl_value_new_float(tilt_x));
  fl_value_set_string_take(args, "tiltY", fl_value_new_float(tilt_y));
  fl_value_set_string_take(
      args, "t", fl_value_new_int(g_get_monotonic_time() / 1000));  // ms
  fl_method_channel_invoke_method(self->pen_channel, "penSample", args,
                                  nullptr, nullptr, nullptr);
}

// Pressure via GtkGestureStylus. Driven in the CAPTURE phase so we OBSERVE
// the pen stream before FlView consumes it — without claiming the sequence,
// so Flutter still gets the normal PointerEvent (with its correct x/y). We
// only supply the pressure the embedder drops. NOTE: this gesture only fires
// for devices GDK classifies as GDK_SOURCE_PEN/ERASER; many tablets
// (Gaomon/Huion/XP-Pen) are classed as a generic pointer, so it never
// activates for them — the source-agnostic GtkGestureDrag path below covers
// those.
static void forward_pen_sample(MyApplication* self, GtkGestureStylus* gesture,
                               gdouble x, gdouble y) {
  gdouble pressure = -1.0;
  gdouble tilt_x = 0.0;
  gdouble tilt_y = 0.0;
  if (!gtk_gesture_stylus_get_axis(gesture, GDK_AXIS_PRESSURE, &pressure)) {
    return;  // device exposes no pressure axis — nothing to enrich
  }
  gtk_gesture_stylus_get_axis(gesture, GDK_AXIS_XTILT, &tilt_x);
  gtk_gesture_stylus_get_axis(gesture, GDK_AXIS_YTILT, &tilt_y);
  send_pen_sample(self, x, y, pressure, tilt_x, tilt_y);
}

static void on_stylus_down(GtkGestureStylus* gesture, gdouble x, gdouble y,
                           gpointer user_data) {
  forward_pen_sample(MY_APPLICATION(user_data), gesture, x, y);
}

static void on_stylus_motion(GtkGestureStylus* gesture, gdouble x, gdouble y,
                             gpointer user_data) {
  forward_pen_sample(MY_APPLICATION(user_data), gesture, x, y);
}

// Permission-free pressure via the display server — the primary path.
//
// GtkGestureStylus above only fires for devices GDK tags as PEN/ERASER, and
// GDK mislabels many tablets (e.g. Gaomon on X11) as a generic pointer, so
// that gesture never activates for them. But GDK still builds each device's
// axis list from its XInput2 valuators (X11) or the tablet-v2 protocol
// (Wayland), independently of the source-type heuristic — so the "Abs
// Pressure" axis is readable straight off the raw event with
// gdk_event_get_axis(). The X server already owns the device, so this needs
// NO /dev/input access, NO 'input' group, and works for any user on a fresh
// install (the same mechanism Krita/Xournal++ use).
//
// We use a plain GtkGestureDrag (NOT GtkGestureStylus): it is concrete and
// source-agnostic, so it tracks the pen-contact sequence even when GDK labels
// the tablet as a generic pointer. In the CAPTURE phase it observes the
// stream without ever claiming the sequence, so Flutter still gets the normal
// PointerEvent with its correct coordinates. We pull the pressure axis off the
// gesture's last event.
static void forward_drag_pressure(GtkGesture* gesture, gpointer user_data) {
  GdkEventSequence* seq =
      gtk_gesture_single_get_current_sequence(GTK_GESTURE_SINGLE(gesture));
  const GdkEvent* ev = gtk_gesture_get_last_event(gesture, seq);
  if (ev == nullptr) return;
  gdouble pressure = -1.0;
  if (!gdk_event_get_axis(ev, GDK_AXIS_PRESSURE, &pressure)) {
    return;  // device has no pressure axis (e.g. a real mouse)
  }
  gdouble x = 0.0, y = 0.0, tilt_x = 0.0, tilt_y = 0.0;
  gtk_gesture_get_point(gesture, seq, &x, &y);
  gdk_event_get_axis(ev, GDK_AXIS_XTILT, &tilt_x);
  gdk_event_get_axis(ev, GDK_AXIS_YTILT, &tilt_y);
  send_pen_sample(MY_APPLICATION(user_data), x, y, pressure, tilt_x, tilt_y);
}

// "drag-begin" (start_x, start_y) and "drag-update" (offset_x, offset_y) both
// pass two gdoubles then the user_data; we ignore them and read live state off
// the gesture, so one handler serves both.
static void on_pen_drag(GtkGestureDrag* drag, gdouble a, gdouble b,
                        gpointer user_data) {
  (void)a;
  (void)b;
  forward_drag_pressure(GTK_GESTURE(drag), user_data);
}

// Pen lifted: report zero so the cached pressure can't linger into the next
// stroke (mirrors the evdev path's lift-zeroing). Guard on the pressure axis
// so an ordinary mouse drag-end does NOT clamp _pressure to 0 — for a mouse we
// must leave it at -1 so the canvas keeps its velocity-synth width.
static void on_pen_drag_end(GtkGestureDrag* drag, gdouble offset_x,
                            gdouble offset_y, gpointer user_data) {
  (void)offset_x;
  (void)offset_y;
  GtkGesture* g = GTK_GESTURE(drag);
  GdkEventSequence* seq =
      gtk_gesture_single_get_current_sequence(GTK_GESTURE_SINGLE(g));
  const GdkEvent* ev = gtk_gesture_get_last_event(g, seq);
  gdouble pressure = -1.0;
  if (ev == nullptr || !gdk_event_get_axis(ev, GDK_AXIS_PRESSURE, &pressure)) {
    return;  // not a pressure device (e.g. a mouse) — leave _pressure as-is
  }
  send_pen_sample(MY_APPLICATION(user_data), 0.0, 0.0, 0.0, 0.0, 0.0);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Handles calls on the "handwriter/window" channel. Only setFullScreen —
// plain gtk_window_fullscreen/unfullscreen on the active window, nothing
// attached to the window's lifecycle (see window_channel comment above).
static void window_method_cb(FlMethodChannel* channel,
                             FlMethodCall* method_call, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (g_strcmp0(fl_method_call_get_name(method_call), "setFullScreen") != 0) {
    fl_method_call_respond_not_implemented(method_call, nullptr);
    return;
  }
  FlValue* args = fl_method_call_get_args(method_call);
  gboolean enable = fl_value_get_type(args) == FL_VALUE_TYPE_BOOL &&
                    fl_value_get_bool(args);
  GtkWindow* window =
      gtk_application_get_active_window(GTK_APPLICATION(self));
  if (window != nullptr) {
    if (enable) {
      gtk_window_fullscreen(window);
    } else {
      gtk_window_unfullscreen(window);
    }
  }
  fl_method_call_respond_success(method_call, nullptr, nullptr);
}

// Set the window (and taskbar) icon from the bundled Flutter asset.
// Resolves data/flutter_assets/assets/icon/app_icon.png relative to the
// running executable so it works from both the build tree and an installed
// bundle. All failures are non-fatal — the shell just keeps its placeholder.
static void set_window_icon(GtkWindow* window) {
  g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path == nullptr) return;
  g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
  g_autofree gchar* icon_path = g_build_filename(
      exe_dir, "data", "flutter_assets", "assets", "icon", "app_icon.png",
      nullptr);
  if (!g_file_test(icon_path, G_FILE_TEST_EXISTS)) return;
  gtk_window_set_icon_from_file(window, icon_path, nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "AbelNotes");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "AbelNotes");
  }

  // Taskbar / window icon. Flutter's Linux embedder sets none and
  // flutter_launcher_icons doesn't target Linux, so without this the shell
  // shows a generic placeholder. We load the bundled PNG (added to the
  // Flutter asset manifest, see pubspec.yaml) from its path relative to the
  // running executable — works for both the build tree and an installed
  // bundle. Best-effort: a missing file just leaves the placeholder.
  set_window_icon(window);

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // ── Pen-pressure bridge ──────────────────────────────────────────────
  // Register the method channel on the engine's messenger, then observe
  // GDK motion events on the FlView to forward stylus pressure/tilt that
  // Flutter's embedder drops. The view is realized above, so its GdkWindow
  // exists and we can extend its event mask to receive motion + axes.
  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->pen_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), "handwriter/pen_input_linux",
      FL_METHOD_CODEC(codec));

  // Window-control channel (fullscreen for presentation mode).
  self->window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), "handwriter/window",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->window_channel,
                                            window_method_cb, self, nullptr);
  // GtkGestureStylus only fires for GDK_SOURCE_PEN/ERASER devices and gives
  // us gtk_gesture_stylus_get_axis(). CAPTURE phase = we see the events
  // before FlView; we never claim the sequence, so propagation continues.
  // The gesture is owned by the widget (lives for the app's lifetime).
  GtkGesture* stylus = gtk_gesture_stylus_new(GTK_WIDGET(view));
  gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(stylus),
                                             GTK_PHASE_CAPTURE);
  g_signal_connect(stylus, "down", G_CALLBACK(on_stylus_down), self);
  g_signal_connect(stylus, "motion", G_CALLBACK(on_stylus_motion), self);

  // Primary, permission-free pressure path: a source-agnostic GtkGestureDrag
  // that reads the GDK pressure axis off its events (see forward_drag_pressure).
  // Covers tablets GDK mislabels as a generic pointer, where the stylus gesture
  // above never fires. CAPTURE phase + never claiming = observe without
  // stealing the event from Flutter. Button 0 = react to any contact button.
  // The gesture is owned by the widget (lives for the app's lifetime).
  GtkGesture* pen_drag = gtk_gesture_drag_new(GTK_WIDGET(view));
  gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(pen_drag),
                                             GTK_PHASE_CAPTURE);
  gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(pen_drag), 0);
  g_signal_connect(pen_drag, "drag-begin", G_CALLBACK(on_pen_drag), self);
  g_signal_connect(pen_drag, "drag-update", G_CALLBACK(on_pen_drag), self);
  g_signal_connect(pen_drag, "drag-end", G_CALLBACK(on_pen_drag_end), self);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->pen_channel);
  g_clear_object(&self->window_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
