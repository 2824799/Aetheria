#ifndef AETHERIA_LYRIC_RENDERER_H_
#define AETHERIA_LYRIC_RENDERER_H_
#include <cstdint>
#include <string>
#include <pango/pangocairo.h>
namespace aetheria {
struct Rgba {
  double r;
  double g;
  double b;
  double a;
};

struct LineLayout {
  PangoLayout* layout;
  double height;
};

Rgba ToRgba(uint32_t argb, double opacity);
LineLayout CreateLineLayout(cairo_t* cr, const std::string& text, double font_size,
                            bool bold, const std::string& align, double max_width);
void DrawLineWithShadow(cairo_t* cr, PangoLayout* layout, double x, double y,
                        const Rgba& color, const Rgba& shadow, bool shadow_enabled);
void DrawProgressLine(cairo_t* cr, PangoLayout* layout, double x, double y,
                      double progress, const Rgba& played, const Rgba& unplayed,
                      const Rgba& shadow, bool shadow_enabled);
}
#endif
