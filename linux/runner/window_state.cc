#include "window_state.h"
#include <algorithm>
#include <glib/gstdio.h>

namespace {
struct State {
  GtkWindow* window;
  gchar* path;
  int width = 1280;
  int height = 720;
  bool maximized = false;
  bool fullscreen = false;
  guint timer = 0;
};

void Save(State* state) {
  g_autoptr(GKeyFile) file = g_key_file_new();
  g_key_file_set_integer(file, "window", "width", state->width);
  g_key_file_set_integer(file, "window", "height", state->height);
  g_key_file_set_boolean(file, "window", "maximized", state->maximized);
  g_autofree gchar* dir = g_path_get_dirname(state->path);
  if (g_mkdir_with_parents(dir, 0700) != 0) return;
  gsize length = 0;
  g_autofree gchar* data = g_key_file_to_data(file, &length, nullptr);
  g_autoptr(GError) error = nullptr;
  if (!g_file_set_contents(state->path, data, length, &error)) {
    g_warning("Could not save window state: %s", error->message);
  }
}
void Schedule(State* state) {
  if (state->timer != 0) g_source_remove(state->timer);
  state->timer = g_timeout_add(250, [](gpointer data) -> gboolean {
    auto* state = static_cast<State*>(data);
    state->timer = 0;
    Save(state);
    return G_SOURCE_REMOVE;
  }, state);
}
gboolean Configure(GtkWidget*, GdkEventConfigure* event, gpointer data) {
  auto* state = static_cast<State*>(data);
  GdkWindow* native = gtk_widget_get_window(GTK_WIDGET(state->window));
  const auto flags = native ? gdk_window_get_state(native) : GdkWindowState(0);
  if (!(flags & (GDK_WINDOW_STATE_MAXIMIZED | GDK_WINDOW_STATE_FULLSCREEN |
                  GDK_WINDOW_STATE_ICONIFIED)) && !state->maximized &&
      !state->fullscreen && event->width > 0 && event->height > 0) {
    gtk_window_get_size(state->window, &state->width, &state->height);
    Schedule(state);
  }
  return FALSE;
}
gboolean WindowState(GtkWidget*, GdkEventWindowState* event, gpointer data) {
  auto* state = static_cast<State*>(data);
  state->maximized = (event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0;
  state->fullscreen = (event->new_window_state & GDK_WINDOW_STATE_FULLSCREEN) != 0;
  Schedule(state);
  return FALSE;
}
void Destroy(GtkWidget*, gpointer data) {
  auto* state = static_cast<State*>(data);
  if (state->timer != 0) g_source_remove(state->timer);
  Save(state);
  g_free(state->path);
  delete state;
}
}  // namespace

void RestoreAndTrackWindowState(GtkWindow* window) {
  auto* state = new State{};
  state->window = window;
  state->path = g_build_filename(g_get_user_config_dir(), "aetheria",
                                "window-state.ini", nullptr);
  g_autoptr(GKeyFile) file = g_key_file_new();
  if (g_key_file_load_from_file(file, state->path, G_KEY_FILE_NONE, nullptr)) {
    const int width = g_key_file_get_integer(file, "window", "width", nullptr);
    const int height = g_key_file_get_integer(file, "window", "height", nullptr);
    if (width >= 320 && width <= 16384) state->width = width;
    if (height >= 240 && height <= 16384) state->height = height;
    state->maximized = g_key_file_get_boolean(file, "window", "maximized", nullptr);
  }
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
  if (!monitor) monitor = gdk_display_get_monitor(display, 0);
  if (monitor) {
    GdkRectangle area{};
    gdk_monitor_get_workarea(monitor, &area);
    state->width = std::min(state->width, std::max(320, area.width));
    state->height = std::min(state->height, std::max(240, area.height - 48));
  }
  gtk_window_set_default_size(window, state->width, state->height);
  if (state->maximized) gtk_window_maximize(window);
  g_signal_connect(window, "configure-event", G_CALLBACK(Configure), state);
  g_signal_connect(window, "window-state-event", G_CALLBACK(WindowState), state);
  g_signal_connect(window, "destroy", G_CALLBACK(Destroy), state);
}
