#pragma once

#include <gtk/gtk.h>
#include <cstdint>
#include <vector>

// Owned by FlEngine; Wayland callbacks and timers run on the platform thread.
class AetheriaVsync {
 public:
  using Deliver = void (*)(void*, intptr_t, uint64_t, uint64_t);
  using Now = uint64_t (*)();
  AetheriaVsync(Deliver deliver, Now now, void* engine);
  ~AetheriaVsync();
  void SetWidget(GtkWidget* widget);
  void SetDirect(bool direct);
  void Request(intptr_t baton);
  void Frame();
  void Stop();
 private:
  static gboolean Dispatch(gpointer data);
  static gboolean Timeout(gpointer data);
  void Complete();
  Deliver deliver_;
  Now now_;
  void* engine_;
  GWeakRef widget_;
  GMutex mutex_;
  std::vector<intptr_t> batons_;
  guint dispatch_ = 0;
  guint timeout_ = 0;
  bool direct_ = false;
  bool stopped_ = false;
  gint64 opportunity_ = 0;
};
