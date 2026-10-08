// Run against the bundle built from integration_test/high_refresh_render_test.dart.
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <cstdio>
#include <string>

struct TestWindow {
  GtkWidget* window;
  int step = 0;
};

static gboolean exercise(gpointer data) {
  auto* test = static_cast<TestWindow*>(data);
  switch (test->step++) {
    case 0: gtk_window_resize(GTK_WINDOW(test->window), 940, 640); break;
    case 1: gtk_window_maximize(GTK_WINDOW(test->window)); break;
    case 2: gtk_window_unmaximize(GTK_WINDOW(test->window)); break;
    case 3: gtk_widget_hide(test->window); break;
    case 4: gtk_widget_show(test->window); break;
    case 5: gtk_window_resize(GTK_WINDOW(test->window), 1120, 740); break;
    case 6: gtk_widget_hide(test->window); break;
    case 7: gtk_widget_show(test->window); break;
    case 8: gtk_widget_destroy(test->window); gtk_main_quit(); return G_SOURCE_REMOVE;
  }
  fprintf(stderr, "AETHERIA_LIFECYCLE step=%d time_us=%lld\n", test->step,
          static_cast<long long>(g_get_monotonic_time()));
  return G_SOURCE_CONTINUE;
}

int main(int argc, char** argv) {
  if (argc != 2) return 2;
  const std::string bundle = argv[1];
  gtk_init(nullptr, nullptr);
  auto* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(GTK_WINDOW(window), "Aetheria rendering lifecycle test");
  gtk_window_set_default_size(GTK_WINDOW(window), 1100, 700);
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  auto assets = bundle + "/data/flutter_assets";
  auto icu = bundle + "/data/icudtl.dat";
  auto aot = bundle + "/lib/libapp.so";
  fl_dart_project_set_assets_path(project, assets.data());
  fl_dart_project_set_icu_data_path(project, icu.data());
  fl_dart_project_set_aot_library_path(project, aot.c_str());
  auto* view = fl_view_new(project);
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  gtk_widget_show_all(window);
  TestWindow test{window};
  g_timeout_add(1500, exercise, &test);
  gtk_main();
  puts("Aetheria window lifecycle completed");
}
