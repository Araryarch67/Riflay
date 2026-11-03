// Now Playing's abstract backdrops (Aurora, Silk, Orbits, Prism) as one full-window pass. It mirrors
// the CustomPainter in player_backdrop.dart, which stays as the fallback: same colour fields, motion
// and veil, composited in the same (non-linear) space so the two look alike.
#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uStyle;   // 0 aurora, 1 silk, 2 orbits, 3 prism
uniform float uPhase;
uniform float uEnergy;
uniform float uLight;   // 1 on light themes
uniform vec3 uC0;       // cover, accent, and the two cover-hue shifts
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
uniform vec3 uBg;
uniform vec3 uBase;     // background washed with the cover colour

out vec4 fragColor;

const float PI = 3.14159265358979;

vec3 pick(int i) {
  int k = i - (i / 4) * 4;
  if (k == 0) return uC0;
  if (k == 1) return uC1;
  if (k == 2) return uC2;
  return uC3;
}

// A soft pool of light: alpha falls off 1 -> 0.45 -> 0 across the (stretched) circle.
float glowAlpha(vec2 p, vec2 center, float radius, float stretch, float opacity) {
  vec2 d = p - center;
  d.x /= stretch;
  float t = length(d) / radius;
  if (t >= 1.0) return 0.0;
  return t < 0.48 ? mix(opacity, opacity * 0.45, t / 0.48) : mix(opacity * 0.45, 0.0, (t - 0.48) / 0.52);
}

float bez(float a, float b, float c, float d, float t) {
  float u = 1.0 - t;
  return u * u * u * a + 3.0 * u * u * t * b + 3.0 * u * t * t * c + t * t * t * d;
}

float bezSlope(float a, float b, float c, float d, float t) {
  float u = 1.0 - t;
  return 3.0 * (u * u * (b - a) + 2.0 * u * t * (c - b) + t * t * (d - c));
}

// y of a cubic whose x grows steadily with t, at a given x (Newton from the straight-line guess).
float curveY(float x, vec2 p0, vec2 p1, vec2 p2, vec2 p3) {
  float t = clamp((x - p0.x) / (p3.x - p0.x), 0.0, 1.0);
  for (int i = 0; i < 5; i++) {
    float slope = bezSlope(p0.x, p1.x, p2.x, p3.x, t);
    t = clamp(t - (bez(p0.x, p1.x, p2.x, p3.x, t) - x) / max(slope, 1.0), 0.0, 1.0);
  }
  return bez(p0.y, p1.y, p2.y, p3.y, t);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float w = uSize.x;
  float h = uSize.y;
  float longest = max(w, h);
  float phase = uPhase;
  float energy = uEnergy;
  bool light = uLight > 0.5;
  vec3 col = uBase;
  int style = int(uStyle + 0.5);

  if (style == 0) {
    for (int i = 0; i < 5; i++) {
      float fi = float(i);
      vec2 c = vec2(w * (0.15 + fi * 0.19 + 0.12 * sin(phase + fi * 1.7)), h * (0.25 + 0.24 * cos(phase * 0.7 + fi * 1.3)));
      float a = glowAlpha(p, c, longest * (0.36 + energy * 0.09), 1.3, light ? 0.16 : 0.3);
      col = mix(col, pick(i), a);
    }
  } else if (style == 1) {
    float diagonal = clamp(dot(p, vec2(w, h)) / (w * w + h * h), 0.0, 1.0);
    for (int i = 0; i < 5; i++) {
      float fi = float(i);
      float y = h * (0.15 + fi * 0.15);
      float drift = sin(phase + fi * 0.9) * h * (0.08 + 0.04 * energy);
      float upper = curveY(p.x, vec2(-40.0, y + drift), vec2(w * 0.25, y - h * 0.28), vec2(w * 0.65, y + h * 0.35),
          vec2(w + 40.0, y - drift));
      float lower = curveY(p.x, vec2(-40.0, y + h * 0.15 + drift), vec2(w * 0.25, y - h * 0.15),
          vec2(w * 0.65, y + h * 0.45), vec2(w + 40.0, y + h * 0.22 - drift));
      float top = min(upper, lower);
      float bottom = max(upper, lower);
      float cover = clamp(0.5 + min(p.y - top, bottom - p.y), 0.0, 1.0);
      if (cover > 0.0) {
        vec3 from = pick(i);
        vec3 to = pick(i + 1);
        float peak = light ? 0.11 : 0.22;
        float a;
        vec3 c;
        if (diagonal < 0.5) {
          float s = diagonal * 2.0;
          c = mix(from, to, s);
          a = mix(0.0, peak, s);
        } else {
          float s = diagonal * 2.0 - 1.0;
          c = mix(to, from, s);
          a = mix(peak, 0.04, s);
        }
        col = mix(col, c, a * cover);
      }
    }
  } else if (style == 2) {
    // Opposing pools of light on a slow orbit.
    for (int i = 0; i < 2; i++) {
      float angle = phase * 0.18 + float(i) * PI;
      vec2 c = vec2(w * (0.5 + 0.28 * cos(angle)), h * (0.48 + 0.16 * sin(angle)));
      vec3 tint = i == 0 ? uC0 : mix(uC0, uC1, 0.3);
      float a = glowAlpha(p, c, longest * (0.34 + energy * 0.035), 1.25, light ? 0.14 : 0.28);
      col = mix(col, tint, a);
    }
  } else {
    vec2 c = vec2(w * (0.48 + 0.04 * sin(phase)), h * (0.45 + 0.04 * cos(phase)));
    vec2 d = p - c;
    float t = clamp(length(d) / (1.2 * min(w, h)), 0.0, 1.0);
    for (int i = 0; i < 7; i++) {
      float angle = float(i) * 2.0 * PI / 7.0 + sin(phase * 0.6) * 0.14;
      vec2 u = vec2(cos(angle), sin(angle));
      vec2 v = vec2(cos(angle + 0.9), sin(angle + 0.9));
      // Between the two rays: counter-clockwise of the first, clockwise of the second.
      float cover = clamp(0.5 + (u.x * d.y - u.y * d.x), 0.0, 1.0) * clamp(0.5 - (v.x * d.y - v.y * d.x), 0.0, 1.0);
      if (cover > 0.0) {
        vec3 tint = mix(pick(i), pick(i + 1), t);
        float a = mix(0.04 + energy * 0.06, light ? 0.06 : 0.17, t);
        col = mix(col, tint, a * cover);
      }
    }
  }

  // Quiet contrast veil underneath text.
  col = mix(col, uBg, light ? 0.15 : 0.25);
  fragColor = vec4(col, 1.0);
}
