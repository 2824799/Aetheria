#include "lyric_renderer.h"
#include <algorithm>

namespace aetheria {
Rgba ToRgba(uint32_t argb, double opacity) {
  return Rgba{
      ((argb >> 16) & 0xFF) / 255.0,
      ((argb >> 8) & 0xFF) / 255.0,
      (argb & 0xFF) / 255.0,
      (((argb >> 24) & 0xFF) / 255.0) * opacity,
  };
}

PangoAlignment ResolveAlignment(const std::string& align) {
  if (align == "left") {
    return PANGO_ALIGN_LEFT;
  }
  if (align == "right") {
    return PANGO_ALIGN_RIGHT;
  }
  return PANGO_ALIGN_CENTER;
}

LineLayout CreateLineLayout(cairo_t* cr, const std::string& text,
                            double font_size, bool bold,
                            const std::string& align, double max_width) {
  PangoLayout* layout = pango_cairo_create_layout(cr);
  PangoFontDescription* desc = pango_font_description_new();
  pango_font_description_set_family(
      desc, "Noto Sans CJK SC, WenQuanYi Micro Hei, Microsoft YaHei, sans-serif");
  pango_font_description_set_absolute_size(desc, font_size * PANGO_SCALE);
  pango_font_description_set_weight(
      desc, bold ? PANGO_WEIGHT_BOLD : PANGO_WEIGHT_NORMAL);
  pango_layout_set_font_description(layout, desc);
  pango_font_description_free(desc);
  pango_layout_set_alignment(layout, ResolveAlignment(align));
  pango_layout_set_width(layout, static_cast<int>(max_width * PANGO_SCALE));
  pango_layout_set_single_paragraph_mode(layout, TRUE);
  pango_layout_set_height(layout, -1);
  pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END);
  pango_layout_set_text(layout, text.c_str(), -1);

  int width = 0;
  int height = 0;
  pango_layout_get_pixel_size(layout, &width, &height);
  return LineLayout{layout, static_cast<double>(std::max(1, height))};
}

void DrawLineWithShadow(cairo_t* cr, PangoLayout* layout, double x, double y,
                        const Rgba& color, const Rgba& shadow,
                        bool shadow_enabled) {
  if (shadow_enabled && shadow.a > 0.01) {
    cairo_save(cr);
    cairo_move_to(cr, x + 1.5, y + 1.5);
    cairo_set_source_rgba(cr, shadow.r, shadow.g, shadow.b, shadow.a);
    pango_cairo_show_layout(cr, layout);
    cairo_restore(cr);
  }
  cairo_save(cr);
  cairo_move_to(cr, x, y);
  cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
  pango_cairo_show_layout(cr, layout);
  cairo_restore(cr);
}

// Color the glyph mask once. Painting played text over unplayed text changes
// alpha/antialiasing and leaves the original color visible around glyph edges.
void DrawProgressLine(cairo_t* cr, PangoLayout* layout, double x, double y,
                      double progress, const Rgba& played,
                      const Rgba& unplayed, const Rgba& shadow,
                      bool shadow_enabled) {
  if (shadow_enabled && shadow.a > 0.0) {
    cairo_save(cr);
    cairo_move_to(cr, x + 1.5, y + 1.5);
    cairo_set_source_rgba(cr, shadow.r, shadow.g, shadow.b, shadow.a);
    pango_cairo_show_layout(cr, layout);
    cairo_restore(cr);
  }
  PangoRectangle ink{};
  pango_layout_get_pixel_extents(layout, &ink, nullptr);
  progress = std::clamp(progress, 0.0, 1.0);
  cairo_save(cr);
  cairo_move_to(cr, x, y);
  if (progress == 0.0 || progress == 1.0 || ink.width == 0) {
    const Rgba& color = progress == 1.0 ? played : unplayed;
    cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
  } else {
    double left = x + ink.x;
    double right = left + ink.width;
    if (pango_layout_get_direction(layout, 0) == PANGO_DIRECTION_RTL) {
      std::swap(left, right);
    }
    cairo_pattern_t* gradient = cairo_pattern_create_linear(left, 0, right, 0);
    cairo_pattern_add_color_stop_rgba(gradient, 0, played.r, played.g, played.b, played.a);
    cairo_pattern_add_color_stop_rgba(gradient, progress, played.r, played.g, played.b, played.a);
    cairo_pattern_add_color_stop_rgba(gradient, progress, unplayed.r, unplayed.g, unplayed.b, unplayed.a);
    cairo_pattern_add_color_stop_rgba(gradient, 1, unplayed.r, unplayed.g, unplayed.b, unplayed.a);
    cairo_set_source(cr, gradient);
    cairo_pattern_destroy(gradient);
  }
  pango_cairo_show_layout(cr, layout);
  cairo_restore(cr);
}

}
