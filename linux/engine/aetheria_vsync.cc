#include "aetheria_vsync.h"
#include <algorithm>

AetheriaVsync::AetheriaVsync(Deliver deliver, Now now, void* engine)
    : deliver_(deliver), now_(now), engine_(engine) {
  g_weak_ref_init(&widget_, nullptr);
  g_mutex_init(&mutex_);
}
AetheriaVsync::~AetheriaVsync() {
  Stop();
  g_weak_ref_clear(&widget_);
  g_mutex_clear(&mutex_);
}
void AetheriaVsync::SetWidget(GtkWidget* widget) {
  g_weak_ref_set(&widget_, widget);
}
void AetheriaVsync::SetDirect(bool direct) { direct_ = direct; }
void AetheriaVsync::Request(intptr_t baton) {
  g_mutex_lock(&mutex_);
  if (!stopped_) {
    batons_.push_back(baton);
    if (!dispatch_) dispatch_ = g_idle_add_full(G_PRIORITY_HIGH, Dispatch, this, nullptr);
  }
  g_mutex_unlock(&mutex_);
}
gboolean AetheriaVsync::Dispatch(gpointer data) {
  auto* self = static_cast<AetheriaVsync*>(data);
  g_mutex_lock(&self->mutex_);
  self->dispatch_ = 0;
  g_mutex_unlock(&self->mutex_);
  if (self->stopped_) return G_SOURCE_REMOVE;
  if (self->opportunity_) {
    self->opportunity_ = 0;
    self->Complete();
  } else if (!self->timeout_) {
    // Bootstrap before mapping and recover when a hidden surface stops callbacks.
    self->timeout_ = g_timeout_add_full(G_PRIORITY_HIGH, self->direct_ ? 100 : 17,
                                       Timeout, self, nullptr);
  }
  return G_SOURCE_REMOVE;
}
gboolean AetheriaVsync::Timeout(gpointer data) {
  auto* self = static_cast<AetheriaVsync*>(data);
  self->timeout_ = 0;
  self->Complete();
  return G_SOURCE_REMOVE;
}
void AetheriaVsync::Frame() {
  if (stopped_) return;
  g_mutex_lock(&mutex_);
  const bool pending = !batons_.empty();
  g_mutex_unlock(&mutex_);
  if (pending) Complete();
  else opportunity_ = g_get_monotonic_time();
}
void AetheriaVsync::Complete() {
  if (timeout_) { g_source_remove(timeout_); timeout_ = 0; }
  std::vector<intptr_t> pending;
  g_mutex_lock(&mutex_);
  pending.swap(batons_);
  g_mutex_unlock(&mutex_);
  auto* widget = GTK_WIDGET(g_weak_ref_get(&widget_));
  uint64_t interval = 16666667;
  if (widget && gtk_widget_get_window(widget)) {
    auto* monitor = gdk_display_get_monitor_at_window(gtk_widget_get_display(widget),
                                                     gtk_widget_get_window(widget));
    const int rate = monitor ? gdk_monitor_get_refresh_rate(monitor) : 0;
    if (rate >= 10000 && rate <= 1000000) interval = 1000000000000ULL / rate;
  }
  if (widget) g_object_unref(widget);
  const uint64_t start = now_();
  for (auto baton : pending) deliver_(engine_, baton, start, start + interval);
}
void AetheriaVsync::Stop() {
  g_mutex_lock(&mutex_);
  stopped_ = true;
  if (dispatch_) { g_source_remove(dispatch_); dispatch_ = 0; }
  batons_.clear();
  g_mutex_unlock(&mutex_);
  if (timeout_) { g_source_remove(timeout_); timeout_ = 0; }
}
