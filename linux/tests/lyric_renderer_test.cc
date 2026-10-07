#include "../runner/lyric_renderer.h"
#include <cassert>
#include <cmath>
#include <iostream>
#include <vector>
using namespace aetheria;

std::vector<uint32_t> Render(const std::string& alignment, double progress,
                             bool reference, bool shadow, int scale,
                             const std::string& text = "歌词 Color gy À") {
  constexpr int width = 760, height = 110;
  cairo_surface_t* surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width * scale, height * scale);
  cairo_surface_set_device_scale(surface, scale, scale);
  cairo_t* cr = cairo_create(surface);
  const auto line = CreateLineLayout(cr, text, 34, true, alignment, width - 44);
  Rgba played{1, 0.1, 0, 0.45}, unplayed{0.1, 0.4, 1, 0.45}, shade{0, 0, 0, 0.4};
  if (reference) DrawLineWithShadow(cr, line.layout, 22, 12, played, shade,
                                    line.font_size, shadow);
  else DrawProgressLine(cr, line.layout, 22, 12, progress, played, unplayed,
                        shade, line.font_size, shadow);
  cairo_surface_flush(surface);
  const uint32_t* data = reinterpret_cast<uint32_t*>(cairo_image_surface_get_data(surface));
  std::vector<uint32_t> pixels(data, data + width * height * scale * scale);
  // Visual fixtures for independent inspection at a range of alignments/alphas.
  if (scale == 1 && !reference && !shadow && text == "歌词 Color gy À") {
    const auto name = "/tmp/aetheria-lyric-" + alignment + "-" + std::to_string(int(progress * 100)) + ".png";
    cairo_surface_write_to_png(surface, name.c_str());
  }
  g_object_unref(line.layout);
  cairo_destroy(cr);
  cairo_surface_destroy(surface);
  return pixels;
}

int main() {
  for (const auto& text : {"歌词 Color gy À", "短句", "مرحبا بالعالم", "这是一条很长很长的歌词，用来检查省略号和整个文本的染色边界不会错位或漏色"}) {
    for (const auto& align : {"left", "center", "right"}) {
      for (const int scale : {1, 2}) {
        for (const bool shadow : {false, true}) {
          const auto complete = Render(align, 1, false, shadow, scale, text);
          const auto reference = Render(align, 1, true, shadow, scale, text);
          assert(complete == reference); // No second glyph/shadow pass, including AA edges.
          auto zero = Render(align, 0, false, shadow, scale, text);
          for (double progress : {0.25, 0.5, 0.75}) {
            auto partial = Render(align, progress, false, shadow, scale, text);
            int red = 0, blue = 0, ink = 0;
            for (size_t i = 0; i < partial.size(); ++i) {
              assert((partial[i] >> 24) == (zero[i] >> 24)); // Coloring cannot create holes or double alpha.
              if ((partial[i] >> 24) > 60) {
                ++ink;
                if (((partial[i] >> 16) & 255) > (partial[i] & 255)) ++red;
                else ++blue;
              }
            }
            assert(ink > 0 && red > 0 && blue > 0); // Progress acts on text, including centered short lines.
          }
        }
      }
    }
  }
  std::cout << "Native lyric pixel tests passed (alignment, alpha, shadows, RTL, ellipsis, 1x/2x).\n";
}
