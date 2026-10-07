#include "my_application.h"

int main(int argc, char** argv) {
  // Prefer the session's native Wayland scaling; layer-shell provides desktop
  // lyrics there. Keep direct and launcher starts consistent and honor overrides.
  if (g_getenv("GDK_BACKEND") == nullptr) {
    gdk_set_allowed_backends("wayland,x11");
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
