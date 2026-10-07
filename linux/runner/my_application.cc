#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "floating_lyric_window.h"
#include "window_state.h"
#include <gtk-layer-shell.h>

namespace {

constexpr char kNativeChannelName[] = "com.aetheria.app/notification";
FlMethodChannel* g_native_channel = nullptr;

void handle_native_method_call(FlMethodChannel* channel,
                               FlMethodCall* method_call,
                               gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (g_strcmp0(method, "getDesktopWindowInfo") == 0) {
    auto* view = GTK_WIDGET(user_data);
    GdkDisplay* display = gtk_widget_get_display(view);
    const char* backend = "wayland";
#ifdef GDK_WINDOWING_X11
    if (GDK_IS_X11_DISPLAY(display)) backend = "x11";
#endif
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "backend", fl_value_new_string(backend));
    fl_value_set_string_take(result, "layerShell", fl_value_new_bool(gtk_layer_is_supported()));
    fl_value_set_string_take(result, "scale", fl_value_new_int(gtk_widget_get_scale_factor(view)));
    fl_method_call_respond_success(method_call, result, nullptr);
    return;
  }
  if (g_strcmp0(method, "canDrawOverlays") == 0) {
    fl_method_call_respond_success(method_call, fl_value_new_bool(TRUE), nullptr);
    return;
  }
  if (g_strcmp0(method, "requestOverlayPermission") == 0) {
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }
  if (g_strcmp0(method, "getDeviceName") == 0) {
    const gchar* hostname = g_get_host_name();
    fl_method_call_respond_success(
        method_call, fl_value_new_string(hostname != nullptr ? hostname : ""),
        nullptr);
    return;
  }
  if (g_strcmp0(method, "showFloatingLyrics") == 0) {
    FloatingLyricWindow::GetInstance().Show();
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }
  if (g_strcmp0(method, "hideFloatingLyrics") == 0) {
    FloatingLyricWindow::GetInstance().Hide();
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }
  if (g_strcmp0(method, "updateFloatingLyricsStyle") == 0) {
    FloatingLyricWindow::GetInstance().UpdateStyle(args);
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }
  if (g_strcmp0(method, "updateFloatingLyrics") == 0) {
    FloatingLyricWindow::GetInstance().UpdateLyrics(args);
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }

  fl_method_call_respond_not_implemented(method_call, nullptr);
}

void setup_native_channel(FlView* view) {
  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_native_channel =
      fl_method_channel_new(messenger, kNativeChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      g_native_channel, handle_native_method_call, view, nullptr);

  FloatingLyricWindow::GetInstance().SetBoundsCallback(
      [](int x, int y, int width, int height) {
        if (g_native_channel == nullptr) {
          return;
        }
        g_autoptr(FlValue) event = fl_value_new_map();
        fl_value_set_string_take(event, "type",
                                 fl_value_new_string("boundsChanged"));
        fl_value_set_string_take(event, "x", fl_value_new_int(x));
        fl_value_set_string_take(event, "y", fl_value_new_int(y));
        fl_value_set_string_take(event, "width", fl_value_new_int(width));
        fl_value_set_string_take(event, "height", fl_value_new_int(height));
        fl_method_channel_invoke_method(g_native_channel, "floatingLyricsEvent",
                                        event, nullptr, nullptr, nullptr);
      });
}

void teardown_native_channel() {
  FloatingLyricWindow::GetInstance().Hide();
  FloatingLyricWindow::GetInstance().SetBoundsCallback(nullptr);
  g_clear_object(&g_native_channel);
}

}  // namespace

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Resolve the icon next to the bundled executable so direct launches also
// show the application icon in the window/task switcher.
static void set_application_icon(GtkWindow* window) {
  g_autofree gchar* executable_path = g_file_read_link("/proc/self/exe", nullptr);
  if (executable_path == nullptr) {
    return;
  }

  g_autofree gchar* executable_dir = g_path_get_dirname(executable_path);
  g_autofree gchar* icon_path = g_build_filename(
      executable_dir, "share", "icons", "hicolor", "scalable",
      "apps", "aetheria.svg", nullptr);
  if (!g_file_test(icon_path, G_FILE_TEST_IS_REGULAR)) {
    return;
  }

  g_autoptr(GError) error = nullptr;
  gtk_window_set_icon_from_file(window, icon_path, &error);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  if (g_getenv("AETHERIA_DESKTOP_DIAGNOSTICS") != nullptr) {
    const auto* display = gtk_widget_get_display(GTK_WIDGET(view));
    int width = 0, height = 0;
    gtk_window_get_size(GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view))), &width, &height);
    g_message("Aetheria desktop: backend=%s scale=%d size=%dx%d",
        G_OBJECT_TYPE_NAME(display), gtk_widget_get_scale_factor(GTK_WIDGET(view)), width, height);
  }
}

// Called when the main window is being destroyed; tear down the overlay while
// GTK is still fully initialized.
static void main_window_destroy_cb(GtkWidget* /*widget*/, gpointer /*data*/) {
  teardown_native_channel();
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  set_application_icon(window);

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
    gtk_header_bar_set_title(header_bar, "aetheria");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "aetheria");
  }

  RestoreAndTrackWindowState(window);

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
  g_signal_connect(window, "destroy", G_CALLBACK(main_window_destroy_cb),
                   nullptr);

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  setup_native_channel(view);

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
