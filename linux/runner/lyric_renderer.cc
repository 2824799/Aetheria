#include "lyric_renderer.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

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
  return LineLayout{layout, static_cast<double>(std::max(1, height)), font_size};
}

namespace {

void BlurAlpha(cairo_surface_t* surface, int radius) {
  if (radius <= 0) return;
  cairo_surface_flush(surface);
  const int width = cairo_image_surface_get_width(surface);
  const int height = cairo_image_surface_get_height(surface);
  const int stride = cairo_image_surface_get_stride(surface);
  auto* data = cairo_image_surface_get_data(surface);
  std::vector<uint8_t> source(static_cast<size_t>(width) * height);
  std::vector<uint8_t> horizontal(source.size());
  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      source[static_cast<size_t>(y) * width + x] = data[y * stride + x];
    }
  }
  const int diameter = radius * 2 + 1;
  for (int y = 0; y < height; ++y) {
    int sum = 0;
    for (int i = -radius; i <= radius; ++i) {
      const int x = std::clamp(i, 0, width - 1);
      sum += source[static_cast<size_t>(y) * width + x];
    }
    for (int x = 0; x < width; ++x) {
      horizontal[static_cast<size_t>(y) * width + x] =
          static_cast<uint8_t>(sum / diameter);
      const int remove_x = std::clamp(x - radius, 0, width - 1);
      const int add_x = std::clamp(x + radius + 1, 0, width - 1);
      sum += source[static_cast<size_t>(y) * width + add_x] -
             source[static_cast<size_t>(y) * width + remove_x];
    }
  }
  for (int x = 0; x < width; ++x) {
    int sum = 0;
    for (int i = -radius; i <= radius; ++i) {
      const int y = std::clamp(i, 0, height - 1);
      sum += horizontal[static_cast<size_t>(y) * width + x];
    }
    for (int y = 0; y < height; ++y) {
      data[y * stride + x] = static_cast<uint8_t>(sum / diameter);
      const int remove_y = std::clamp(y - radius, 0, height - 1);
      const int add_y = std::clamp(y + radius + 1, 0, height - 1);
      sum += horizontal[static_cast<size_t>(add_y) * width + x] -
             horizontal[static_cast<size_t>(remove_y) * width + x];
    }
  }
  cairo_surface_mark_dirty(surface);
}

void DrawSoftShadow(cairo_t* cr, PangoLayout* layout, double x, double y,
                    const Rgba& shadow, double font_size) {
  if (shadow.a <= 0.01) return;
  PangoRectangle ink{};
  pango_layout_get_pixel_extents(layout, &ink, nullptr);
  if (ink.width <= 0 || ink.height <= 0) return;

  // A proportional sub-pixel offset and a small alpha blur keep small text
  // readable. A hard fixed offset renders the shadow as a second glyph.
  double device_scale_x = 1.0;
  double device_scale_y = 1.0;
  cairo_surface_get_device_scale(cairo_get_target(cr), &device_scale_x,
                                 &device_scale_y);
  const double scale = std::max(1.0, device_scale_x);
  const double offset = std::clamp(font_size * 0.018, 0.35, 0.85);
  const double blur = std::clamp(font_size * 0.035, 0.8, 1.8);
  const int padding = static_cast<int>(std::ceil((blur * 3.0 + offset + 1.0) * scale));
  const int mask_width = std::max(1, static_cast<int>(std::ceil(ink.width * scale)) + padding * 2);
  const int mask_height = std::max(1, static_cast<int>(std::ceil(ink.height * scale)) + padding * 2);
  cairo_surface_t* mask = cairo_image_surface_create(CAIRO_FORMAT_A8, mask_width, mask_height);
  cairo_surface_set_device_scale(mask, scale, scale);
  cairo_t* mask_cr = cairo_create(mask);
  cairo_set_source_rgba(mask_cr, 1, 1, 1, 1);
  cairo_move_to(mask_cr, padding / scale - ink.x + offset,
               padding / scale - ink.y + offset);
  pango_cairo_show_layout(mask_cr, layout);
  cairo_destroy(mask_cr);

  BlurAlpha(mask, std::max(1, static_cast<int>(std::lround(blur * scale))));
  cairo_save(cr);
  cairo_set_source_rgba(cr, shadow.r, shadow.g, shadow.b, shadow.a);
  cairo_mask_surface(cr, mask, x + ink.x - padding / scale,
                     y + ink.y - padding / scale);
  cairo_restore(cr);
  cairo_surface_destroy(mask);
}

}  // namespace

void DrawLineWithShadow(cairo_t* cr, PangoLayout* layout, double x, double y,
                        const Rgba& color, const Rgba& shadow,
                        double font_size, bool shadow_enabled) {
  if (shadow_enabled && shadow.a > 0.01) {
    DrawSoftShadow(cr, layout, x, y, shadow, font_size);
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
                      double font_size, bool shadow_enabled) {
  if (shadow_enabled && shadow.a > 0.0) {
    DrawSoftShadow(cr, layout, x, y, shadow, font_size);
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
