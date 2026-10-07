#ifndef AETHERIA_WINDOW_STATE_H_
#define AETHERIA_WINDOW_STATE_H_
#include <gtk/gtk.h>

// Stores normal (not maximized/fullscreen) content size in GTK logical pixels.
// Each window owns its state, and closing flushes any pending debounced write.
void RestoreAndTrackWindowState(GtkWindow* window);
#endif
