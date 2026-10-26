#version 440
// Liquid fill for typing/liquid.qml. Reveals the logo's ink below a wavy
// surface, with an accent meniscus line and an optional submit ripple.
// Rebuild: /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o liquid.frag.qsb liquid.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec4 ink;        // inkRect in item pixels: x, y, w, h
  vec4 lineColor;  // meniscus colour
  vec2 px;         // item size in pixels
  float level;     // fill 0..1
  float levelFrom; // reduced motion: cross-fade from this level
  float xf;        // cross-fade 0..1 (1 = only `level`)
  float amp;       // wave amplitude, px
  float phase;     // wave phase, radians
  float tilt;      // surface slope, px per px from the centre
  float glint;     // meniscus strength 0..1
  float ripple;    // submit ripple progress 0..1 (0 = none)
  float lineW;     // meniscus thickness, px
};

layout(binding = 1) uniform sampler2D source;

// Height of the surface above the ink bottom at x, for fill level l.
float surface(float x, float l) {
  float h = ink.w;
  // Margin so level 0 and 1 sit just past the ink ends (meniscus hidden).
  float m = lineW * 2.0 + 2.0;
  // Calm the wave near empty and full so it never peeks past the ends.
  float calm = clamp(min(l, 1.0 - l) * 10.0, 0.0, 1.0);
  float k = 6.2831853 / max(ink.w * 1.7, 24.0);
  float w = amp * calm * (0.62 * sin(x * k + phase) + 0.38 * sin(x * k * 2.3 - phase * 1.7 + 1.3));
  return l * (h + 2.0 * m) - m + w + tilt * calm * (x - (ink.x + ink.z * 0.5));
}

void main() {
  vec4 src = texture(source, qt_TexCoord0);
  vec2 p = qt_TexCoord0 * px;
  float above = ink.y + ink.w - p.y;

  float d1 = surface(p.x, level) - above;     // px below the surface
  float d0 = surface(p.x, levelFrom) - above;
  float fill = mix(smoothstep(-0.75, 0.75, d0), smoothstep(-0.75, 0.75, d1), xf);
  float band1 = smoothstep(-0.75, 0.5, d1) * (1.0 - smoothstep(lineW * 0.6, lineW * 1.6, d1));
  float band0 = smoothstep(-0.75, 0.5, d0) * (1.0 - smoothstep(lineW * 0.6, lineW * 1.6, d0));
  float band = mix(band0, band1, xf);
  // Soft light falling off below the surface.
  float sheen = exp(-max(d1, 0.0) / max(ink.w * 0.14, 4.0)) * 0.4 * xf * fill;

  float tint = clamp(band * glint + sheen * glint, 0.0, 1.0);

  // Submit ripple: an accent ring spreading from the centre, stretched to
  // the ink's shape so it sweeps a wide wordmark and a square symbol alike.
  if (ripple > 0.0 && ripple < 1.0) {
    vec2 c = ink.xy + ink.zw * 0.5;
    vec2 q = (p - c) / max(ink.zw * 0.5, vec2(1.0));
    float r = ripple * 1.5;
    float ring = exp(-pow((length(q) - r) / 0.16, 2.0)) * (1.0 - ripple) * (1.0 - ripple);
    tint = clamp(tint + ring * 0.9, 0.0, 1.0);
  }

  vec4 col = src * fill;
  col.rgb = mix(col.rgb, lineColor.rgb * col.a, tint);
  fragColor = col * qt_Opacity;
}
