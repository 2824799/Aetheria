#include "../runner/window_state.h"
#include "../runner/floating_lyric_window.h"
#include <gdk/gdkx.h>
#include <gtk-layer-shell.h>
#include <X11/extensions/shape.h>
#include <cassert>
#include <iostream>
#include <string>
#include <vector>

void Pump(int ms) {
  const gint64 end = g_get_monotonic_time() + ms * 1000;
  while (g_get_monotonic_time() < end) {
    while (g_main_context_iteration(nullptr, FALSE)) {}
    g_usleep(1000);
  }
}
GtkWidget* LyricsWidget() {
  GList* list = gtk_window_list_toplevels();
  GtkWidget* result = nullptr;
  for (GList* p = list; p; p = p->next) {
    if (g_strcmp0(gtk_window_get_title(GTK_WINDOW(p->data)), "Aetheria Lyrics") == 0)
      result = GTK_WIDGET(p->data);
  }
  g_list_free(list);
  return result;
}

void Drag(GtkWidget* widget, double x, double y, double dx, double dy, bool accepted = true) {
  GdkEventButton button{};
  button.type = GDK_BUTTON_PRESS;
  button.button = 1;
  button.x = x;
  button.y = y;
  gboolean handled = FALSE;
  g_signal_emit_by_name(widget, "button-press-event", &button, &handled);
  assert(bool(handled) == accepted);
  if (!accepted) return;
  GdkEventMotion motion{};
  motion.type = GDK_MOTION_NOTIFY;
  motion.state = GDK_BUTTON1_MASK;
  motion.x = x + dx;
  motion.y = y + dy;
  g_signal_emit_by_name(widget, "motion-notify-event", &motion, &handled);
  assert(handled);
  Pump(100);
  button.type = GDK_BUTTON_RELEASE;
  g_signal_emit_by_name(widget, "button-release-event", &button, &handled);
  assert(handled && !gtk_widget_has_grab(widget));
  Pump(100);
}

// The KWin probe checks the compositor's actual stacking order and active
// window, rather than just the layer requested by this GTK client.
void CheckStacking(const char* phase, bool above, bool fullscreen) {
  const char* probe = g_getenv("AETHERIA_TEST_PROBE");
  assert(probe);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  assert(bus);
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(bus, probe,
      "/org/aetheria/DesktopTest", "org.aetheria.DesktopTest", "Check",
      g_variant_new("(sbb)", phase, above, fullscreen), G_VARIANT_TYPE_UNIT,
      G_DBUS_CALL_FLAGS_NONE, 10000, nullptr, &error);
  if (!reply) std::cerr << phase << ": " << error->message << std::endl;
  assert(reply);
}

void TestFullscreenStacking() {
  assert(gtk_layer_is_supported());
  GtkWidget* game = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(GTK_WINDOW(game), "Aetheria fullscreen regression fixture");
  gtk_window_set_default_size(GTK_WINDOW(game), 800, 600);
  gtk_widget_show_all(game);
  gtk_window_present(GTK_WINDOW(game));
  auto& overlay = FloatingLyricWindow::GetInstance();
  g_autoptr(FlValue) style = fl_value_new_map();
  fl_value_set_string_take(style, "locked", fl_value_new_bool(TRUE));
  fl_value_set_string_take(style, "alwaysOnTop", fl_value_new_bool(TRUE));
  overlay.UpdateStyle(style);
  overlay.Show();
  Pump(600);
  CheckStacking("ordinary window", true, false);
  gtk_window_fullscreen(GTK_WINDOW(game));
  Pump(600);
  CheckStacking("active fullscreen window", true, true);
  // Negative control: reproduce the old TOP layer being covered.
  gtk_layer_set_layer(GTK_WINDOW(LyricsWidget()), GTK_LAYER_SHELL_LAYER_TOP);
  Pump(300);
  CheckStacking("old TOP layer control", false, true);
  overlay.UpdateStyle(style);
  Pump(300);
  CheckStacking("restored overlay layer", true, true);
  fl_value_set_string_take(style, "alwaysOnTop", fl_value_new_bool(FALSE));
  overlay.UpdateStyle(style);
  Pump(300);
  CheckStacking("always on top disabled", false, true);
  fl_value_set_string_take(style, "alwaysOnTop", fl_value_new_bool(TRUE));
  fl_value_set_string_take(style, "locked", fl_value_new_bool(FALSE));
  overlay.UpdateStyle(style);
  Pump(300);
  CheckStacking("unlocked overlay", true, true);
  overlay.Hide();
  overlay.Show();
  Pump(400);
  CheckStacking("remapped overlay", true, true);
  gtk_window_unfullscreen(GTK_WINDOW(game));
  Pump(500);
  CheckStacking("leave fullscreen", true, false);
  overlay.Hide();
  gtk_widget_destroy(game);
}

std::vector<uint32_t> LyricPixels(GtkWidget* lyrics) {
  int width = 0, height = 0;
  gtk_window_get_size(GTK_WINDOW(lyrics), &width, &height);
  cairo_surface_t* surface =
      cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
  cairo_t* cr = cairo_create(surface);
  gtk_widget_draw(lyrics, cr);
  cairo_surface_flush(surface);
  const auto* pixels = reinterpret_cast<const uint32_t*>(
      cairo_image_surface_get_data(surface));
  const int stride = cairo_image_surface_get_stride(surface) / sizeof(uint32_t);
  std::vector<uint32_t> result;
  for (int y = 0; y < height; ++y) {
    result.insert(result.end(), pixels + y * stride, pixels + y * stride + width);
  }
  cairo_destroy(cr);
  cairo_surface_destroy(surface);
  return result;
}

uint64_t TotalAlpha(const std::vector<uint32_t>& pixels) {
  uint64_t alpha = 0;
  for (uint32_t pixel : pixels) alpha += pixel >> 24;
  return alpha;
}

void TestPauseOpacity() {
  auto& overlay = FloatingLyricWindow::GetInstance();
  g_autoptr(FlValue) style = fl_value_new_map();
  fl_value_set_string_take(style, "locked", fl_value_new_bool(TRUE));
  fl_value_set_string_take(style, "windowHeight", fl_value_new_int(250));
  fl_value_set_string_take(style, "opacity", fl_value_new_float(0.65));
  fl_value_set_string_take(style, "pauseOpacity", fl_value_new_float(0));
  fl_value_set_string_take(style, "compactMultiline", fl_value_new_bool(TRUE));
  overlay.UpdateStyle(style);
  g_autoptr(FlValue) frame = fl_value_new_map();
  fl_value_set_string_take(frame, "line", fl_value_new_string("暂停透明度测试"));
  fl_value_set_string_take(frame, "translation", fl_value_new_string("Translation"));
  fl_value_set_string_take(frame, "nextLine", fl_value_new_string("下一行歌词"));
  fl_value_set_string_take(frame, "nextTranslation", fl_value_new_string("Next translation"));
  g_autoptr(FlValue) context = fl_value_new_list();
  fl_value_append_take(context, fl_value_new_string("后续歌词"));
  fl_value_set_string_take(frame, "contextLines", fl_value_ref(context));
  g_autoptr(FlValue) translations = fl_value_new_list();
  fl_value_append_take(translations, fl_value_new_string("Context translation"));
  fl_value_set_string_take(frame, "contextTranslations", fl_value_ref(translations));
  fl_value_set_string_take(frame, "progress", fl_value_new_float(0.5));
  fl_value_set_string_take(frame, "isPlaying", fl_value_new_bool(TRUE));
  overlay.UpdateLyrics(frame);
  overlay.Show();
  Pump(300);
  GtkWidget* lyrics = LyricsWidget();
  assert(lyrics);
  const auto playing = LyricPixels(lyrics);
  assert(TotalAlpha(playing) > 0);

  fl_value_set_string_take(frame, "isPlaying", fl_value_new_bool(FALSE));
  overlay.UpdateLyrics(frame);
  Pump(50);
  assert(TotalAlpha(LyricPixels(lyrics)) == 0);  // Includes other lines and shadows.

  fl_value_set_string_take(style, "pauseOpacity", fl_value_new_float(0.4));
  overlay.UpdateStyle(style);  // A paused slider update must repaint immediately.
  Pump(50);
  const auto partial = TotalAlpha(LyricPixels(lyrics));
  assert(partial > 0 && partial < TotalAlpha(playing));

  fl_value_set_string_take(style, "pauseOpacity", fl_value_new_float(1));
  overlay.UpdateStyle(style);
  Pump(50);
  const auto full = LyricPixels(lyrics);
  assert(TotalAlpha(full) > TotalAlpha(playing));

  fl_value_set_string_take(frame, "isPlaying", fl_value_new_bool(TRUE));
  overlay.UpdateLyrics(frame);
  Pump(50);
  assert(LyricPixels(lyrics) == playing);  // Resuming restores playback opacity.
  fl_value_set_string_take(style, "opacity", fl_value_new_float(1));
  overlay.UpdateStyle(style);
  Pump(50);
  assert(LyricPixels(lyrics) == full);  // 100% pause opacity is independent.
  overlay.Hide();
  std::cout << "Native paused lyric opacity pixels passed (0%, 40%, 100%, resume).\n";
}

void TestPreviewTranslations() {
  auto& overlay = FloatingLyricWindow::GetInstance();
  g_autoptr(FlValue) style = fl_value_new_map();
  fl_value_set_string_take(style, "locked", fl_value_new_bool(TRUE));
  fl_value_set_string_take(style, "compactMultiline", fl_value_new_bool(TRUE));
  fl_value_set_string_take(style, "textShadowEnabled", fl_value_new_bool(FALSE));
  fl_value_set_string_take(style, "windowHeight", fl_value_new_int(320));
  fl_value_set_string_take(style, "fontSize", fl_value_new_int(36));
  fl_value_set_string_take(style, "opacity", fl_value_new_float(1));
  fl_value_set_string_take(style, "playedColor", fl_value_new_int(0xFFFFAABB));
  fl_value_set_string_take(style, "unplayedColor", fl_value_new_int(0xFFFFAABB));
  overlay.UpdateStyle(style);
  g_autoptr(FlValue) frame = fl_value_new_map();
  fl_value_set_string_take(frame, "isPlaying", fl_value_new_bool(TRUE));
  fl_value_set_string_take(frame, "line", fl_value_new_string("明るい朝です"));
  fl_value_set_string_take(frame, "translation", fl_value_new_string("明亮的早晨"));
  fl_value_set_string_take(frame, "nextLine", fl_value_new_string("窓を開けて"));
  fl_value_set_string_take(frame, "nextTranslation", fl_value_new_string("打开窗户"));
  g_autoptr(FlValue) context = fl_value_new_list();
  fl_value_append_take(context, fl_value_new_string("風を感じて"));
  fl_value_set_string_take(frame, "contextLines", fl_value_ref(context));
  g_autoptr(FlValue) translations = fl_value_new_list();
  fl_value_append_take(translations, fl_value_new_string("感受微风"));
  fl_value_set_string_take(frame, "contextTranslations", fl_value_ref(translations));
  overlay.UpdateLyrics(frame);
  overlay.Show();
  Pump(300);
  GtkWidget* lyrics = LyricsWidget();
  assert(lyrics);
  auto bilingual = LyricPixels(lyrics);
  assert(TotalAlpha(bilingual) > 0);
  if (const char* directory = g_getenv("AETHERIA_TEST_SCREENSHOTS")) {
    g_mkdir_with_parents(directory, 0700);
    int width = 0, height = 0;
    gtk_window_get_size(GTK_WINDOW(lyrics), &width, &height);
    cairo_surface_t* surface = cairo_image_surface_create_for_data(
        reinterpret_cast<unsigned char*>(bilingual.data()), CAIRO_FORMAT_ARGB32,
        width, height, width * sizeof(uint32_t));
    const auto path = std::string(directory) + "/bilingual-preview-" +
                      g_getenv("GDK_BACKEND") + ".png";
    assert(cairo_surface_write_to_png(surface, path.c_str()) == CAIRO_STATUS_SUCCESS);
    cairo_surface_destroy(surface);
  }

  fl_value_set_string_take(style, "showTranslation", fl_value_new_bool(FALSE));
  overlay.UpdateStyle(style);
  Pump(50);
  const auto originals = LyricPixels(lyrics);
  assert(originals != bilingual);
  fl_value_set_string_take(style, "showTranslation", fl_value_new_bool(TRUE));
  overlay.UpdateStyle(style);
  fl_value_set_string_take(frame, "translation", fl_value_new_string(""));
  fl_value_set_string_take(frame, "nextTranslation", fl_value_new_string(""));
  fl_value_set_string_take(frame, "contextTranslations", fl_value_new_list());
  overlay.UpdateLyrics(frame);
  Pump(50);
  assert(LyricPixels(lyrics) == originals);  // No invisible translation rows.

  fl_value_set_string_take(frame, "nextTranslation", fl_value_new_string("打开窗户"));
  fl_value_set_string_take(frame, "contextTranslations", fl_value_ref(translations));
  overlay.UpdateLyrics(frame);
  fl_value_set_string_take(style, "compactMultiline", fl_value_new_bool(FALSE));
  overlay.UpdateStyle(style);
  Pump(50);
  const auto one_preview = LyricPixels(lyrics);
  fl_value_set_string_take(style, "compactMultiline", fl_value_new_bool(TRUE));
  overlay.UpdateStyle(style);
  fl_value_set_string_take(frame, "contextLines", fl_value_new_list());
  fl_value_set_string_take(frame, "contextTranslations", fl_value_new_list());
  overlay.UpdateLyrics(frame);
  Pump(50);
  assert(LyricPixels(lyrics) == one_preview);  // Next translation survives compact off.

  fl_value_set_string_take(style, "showNextLine", fl_value_new_bool(FALSE));
  overlay.UpdateStyle(style);
  Pump(50);
  const auto no_preview = LyricPixels(lyrics);
  assert(no_preview != one_preview);
  fl_value_set_string_take(style, "showNextLine", fl_value_new_bool(TRUE));
  overlay.UpdateStyle(style);
  fl_value_set_string_take(frame, "nextLine", fl_value_new_string(""));
  fl_value_set_string_take(frame, "nextTranslation", fl_value_new_string(""));
  overlay.UpdateLyrics(frame);
  Pump(50);
  assert(LyricPixels(lyrics) == no_preview);
  overlay.Hide();
  std::cout << "Native bilingual preview pixels passed (translation/compact/preview toggles).\n";
}

int main(int argc, char** argv) {
  gtk_init(&argc, &argv);
  const std::string mode = argc > 1 ? argv[1] : "write";
  if (mode == "preview") {
    TestPreviewTranslations();
    return 0;
  }
  if (mode == "opacity") {
    TestPauseOpacity();
    return 0;
  }
  if (mode == "fullscreen") {
    TestFullscreenStacking();
    return 0;
  }
  GtkWidget* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(GTK_WINDOW(window), "Aetheria desktop regression test");
  gtk_window_set_accept_focus(GTK_WINDOW(window), FALSE);
  RestoreAndTrackWindowState(GTK_WINDOW(window));
  gtk_widget_show_all(window);
  Pump(400);
  int width = 0, height = 0;
  if (mode == "write") {
    gtk_window_resize(GTK_WINDOW(window), 903, 617);
    Pump(500);
  } else {
    gtk_window_get_size(GTK_WINDOW(window), &width, &height);
    std::cout << "Restored " << width << "x" << height << std::endl;
    assert(width == 903 && height == 617);
    gtk_window_maximize(GTK_WINDOW(window));
    Pump(400);
  }
  gtk_widget_destroy(window);
  Pump(100);
  if (mode == "write") return 0;

  // Reopen maximized, then restore to the same normal content size.
  window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  RestoreAndTrackWindowState(GTK_WINDOW(window));
  gtk_widget_show_all(window);
  Pump(400);
  assert(gtk_window_is_maximized(GTK_WINDOW(window)));
  gtk_window_unmaximize(GTK_WINDOW(window));
  Pump(400);
  gtk_window_get_size(GTK_WINDOW(window), &width, &height);
  std::cout << "Unmaximized " << width << "x" << height << std::endl;
  assert(width == 903 && height == 617);
  gtk_widget_destroy(window);
  Pump(50);

  auto& overlay = FloatingLyricWindow::GetInstance();
  g_autoptr(FlValue) style = fl_value_new_map();
  fl_value_set_string_take(style, "locked", fl_value_new_bool(TRUE));
  fl_value_set_string_take(style, "windowWidth", fl_value_new_int(600));
  fl_value_set_string_take(style, "windowHeight", fl_value_new_int(100));
  fl_value_set_string_take(style, "playedColor", fl_value_new_int(0x80ff6633));
  fl_value_set_string_take(style, "unplayedColor", fl_value_new_int(0x803399ff));
  overlay.UpdateStyle(style);
  g_autoptr(FlValue) frame = fl_value_new_map();
  fl_value_set_string_take(frame, "line", fl_value_new_string("桌面歌词 · Color test"));
  fl_value_set_string_take(frame, "progress", fl_value_new_float(0.5));
  overlay.UpdateLyrics(frame);
  overlay.Show();
  Pump(300);
  GtkWidget* lyrics = LyricsWidget();
  assert(lyrics && !gtk_window_get_decorated(GTK_WINDOW(lyrics)));
  gtk_window_get_size(GTK_WINDOW(lyrics), &width, &height);
  assert(width == 600 && height == 100);
  GdkWindow* native = gtk_widget_get_window(lyrics);
  bool x11 = GDK_IS_X11_WINDOW(native);
  if (gtk_layer_is_supported()) {
    assert(!x11 && gtk_layer_is_layer_window(GTK_WINDOW(lyrics)));
    assert(gtk_layer_get_layer(GTK_WINDOW(lyrics)) == GTK_LAYER_SHELL_LAYER_OVERLAY);
    assert(gtk_layer_get_keyboard_mode(GTK_WINDOW(lyrics)) == GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
    const int left = gtk_layer_get_margin(GTK_WINDOW(lyrics), GTK_LAYER_SHELL_EDGE_LEFT);
    Drag(lyrics, 200, 50, 40, 20, false); // Locked windows must reject mouse actions.
    assert(gtk_layer_get_margin(GTK_WINDOW(lyrics), GTK_LAYER_SHELL_EDGE_LEFT) == left);
  }
  if (x11) {
    int count = 0, ordering = 0;
    XRectangle* rectangles = XShapeGetRectangles(gdk_x11_display_get_xdisplay(gdk_window_get_display(native)),
        gdk_x11_window_get_xid(native), ShapeInput, &count, &ordering);
    std::cerr << "Locked input rectangles=" << count;
    for (int i = 0; i < count; ++i) std::cerr << " [" << rectangles[i].x << "," << rectangles[i].y << " " << rectangles[i].width << "x" << rectangles[i].height << "]";
    std::cerr << std::endl;
    assert(count == 0); // Initially locked, not only locked after showing.
    XFree(rectangles);
  }
  // Snapshot precisely the actual GTK overlay, not the whole user's screen.
  cairo_surface_t* surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
  cairo_t* cr = cairo_create(surface);
  gtk_widget_draw(lyrics, cr);
  const auto path = std::string("/tmp/aetheria-overlay-") + (x11 ? "x11" : "wayland") + ".png";
  cairo_surface_write_to_png(surface, path.c_str());
  cairo_destroy(cr);
  cairo_surface_destroy(surface);
  fl_value_set_string_take(style, "locked", fl_value_new_bool(FALSE));
  overlay.UpdateStyle(style);
  Pump(100);
  if (x11) {
    int count = 0, ordering = 0;
    XRectangle* rectangles = XShapeGetRectangles(gdk_x11_display_get_xdisplay(gdk_window_get_display(native)),
        gdk_x11_window_get_xid(native), ShapeInput, &count, &ordering);
    assert(count > 0);
    XFree(rectangles);
  }
  if (gtk_layer_is_supported()) {
    // Drive production input handlers and let the real compositor configure
    // the new surface. Check callback persistence, not only requested values.
    int saved_x = -1, saved_y = -1, saved_width = -1, saved_height = -1;
    overlay.SetBoundsCallback([&](int x, int y, int w, int h) {
      saved_x = x; saved_y = y; saved_width = w; saved_height = h;
    });
    g_autoptr(FlValue) position = fl_value_new_map();
    fl_value_set_string_take(position, "windowX", fl_value_new_int(180));
    fl_value_set_string_take(position, "windowY", fl_value_new_int(200));
    overlay.UpdateStyle(position);
    Pump(150);
    const int left = gtk_layer_get_margin(GTK_WINDOW(lyrics), GTK_LAYER_SHELL_EDGE_LEFT);
    const int top = gtk_layer_get_margin(GTK_WINDOW(lyrics), GTK_LAYER_SHELL_EDGE_TOP);
    Drag(lyrics, 200, 50, 40, 20);
    assert(gtk_layer_get_margin(GTK_WINDOW(lyrics), GTK_LAYER_SHELL_EDGE_LEFT) == left + 40);
    assert(gtk_layer_get_margin(GTK_WINDOW(lyrics), GTK_LAYER_SHELL_EDGE_TOP) == top + 20);
    assert(saved_x == 220 && saved_y == 220);
    Drag(lyrics, 598, 98, 60, 20);
    gtk_window_get_size(GTK_WINDOW(lyrics), &width, &height);
    assert(width == 660 && height == 120 && saved_width == width && saved_height == height);
    Drag(lyrics, 2, 2, 30, 10);
    gtk_window_get_size(GTK_WINDOW(lyrics), &width, &height);
    assert(width == 630 && height == 110 && saved_x == 250 && saved_y == 230);
    fl_value_set_string_take(position, "alwaysOnTop", fl_value_new_bool(FALSE));
    overlay.UpdateStyle(position);
    Pump(100);
    assert(gtk_layer_get_layer(GTK_WINDOW(lyrics)) == GTK_LAYER_SHELL_LAYER_BOTTOM);
    fl_value_set_string_take(position, "alwaysOnTop", fl_value_new_bool(TRUE));
    overlay.UpdateStyle(position);
    overlay.Hide();
    overlay.Show();
    Pump(150);
    assert(gtk_layer_get_layer(GTK_WINDOW(lyrics)) == GTK_LAYER_SHELL_LAYER_OVERLAY);
    overlay.SetBoundsCallback(nullptr);
    std::cout << "Native layer-shell: stacking, locked input, drag, resize, bounds and remap passed" << std::endl;
  }
  overlay.Hide();
  std::cout << "Window persistence/maximize and overlay checks passed: " << (x11 ? "X11" : "Wayland")
            << ", scale=" << gtk_widget_get_scale_factor(lyrics) << std::endl;
}
