/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The assistant's glow on the bottom bezel, as the stock Assistant draws it
 * (PixelWatchAssistant qhg.m, qxq.a/b, qxd): a sweep of 'sweep' degrees
 * centred at 6 o'clock; a band of 14 % of the height whose inner edge fades
 * (radial mask 0 to 86 % of the radius, then up), a line of 6 dp on top of
 * it over 90 % of the sweep, both faded out at the two ends (mask 0, 1 at
 * 25 %, 1 at 75 %, 0). Three palettes crossfade with 'flavor' (0 flourish,
 * 1 resting, 2 talking); the flourish palette is stretched about its centre
 * by 'flourish'; a 62 degree bead (palette f) travels through the arc as
 * 'bead' goes from -1 to 1. Gradients interpolate straight (not
 * premultiplied) colours, as Skia does by default; the result is
 * premultiplied. AssistantGlow.qml drives the uniforms.
 */
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float sweep;     // degrees, 0 = nothing
    float flourish;  // width of the flourish palette, 0 .. 1.7
    float flavor;    // 0 flourish, 1 resting, 2 talking
    float bead;      // -1 .. 1, outside: no bead
    float sizePx;    // the item's width and height
    float linePx;    // half the width of the line: 3 dp
};

float seg(float t, float a, float b) {
    return clamp((t - a) / max(b - a, 0.0001), 0.0, 1.0);
}
float sc(float p, float w) {
    return (p - 0.5) * w + 0.5;
}
vec4 pre(vec4 c) {
    return vec4(c.rgb * c.a, c.a);
}
vec4 over(vec4 src, float a, vec4 dst) {
    src *= a;
    return src + dst * (1.0 - src.a);
}

vec4 flourishAt(float t, float w) {
    vec4 c = vec4(0.2000, 0.5255, 1.0000, 1.00);
    c = mix(c, vec4(0.2000, 0.5255, 1.0000, 1.00), seg(t, sc(0.0, w), sc(0.13, w)));
    c = mix(c, vec4(0.0549, 0.7373, 0.3725, 1.00), seg(t, sc(0.13, w), sc(0.21, w)));
    c = mix(c, vec4(0.4235, 0.7725, 0.0000, 1.00), seg(t, sc(0.21, w), sc(0.23, w)));
    c = mix(c, vec4(1.0000, 0.8275, 0.0784, 1.00), seg(t, sc(0.23, w), sc(0.28, w)));
    c = mix(c, vec4(1.0000, 0.8000, 0.0000, 1.00), seg(t, sc(0.28, w), sc(0.3, w)));
    c = mix(c, vec4(1.0000, 0.8275, 0.0784, 1.00), seg(t, sc(0.3, w), sc(0.33, w)));
    c = mix(c, vec4(1.0000, 0.2980, 0.2706, 1.00), seg(t, sc(0.33, w), sc(0.35, w)));
    c = mix(c, vec4(0.8471, 0.3843, 0.4941, 1.00), seg(t, sc(0.35, w), sc(0.37, w)));
    c = mix(c, vec4(0.6784, 0.4627, 0.6824, 1.00), seg(t, sc(0.37, w), sc(0.41, w)));
    c = mix(c, vec4(0.3725, 0.5176, 0.9843, 1.00), seg(t, sc(0.41, w), sc(0.44, w)));
    c = mix(c, vec4(0.2000, 0.5255, 1.0000, 1.00), seg(t, sc(0.44, w), sc(0.6, w)));
    c = mix(c, vec4(0.2431, 0.4157, 0.9412, 1.00), seg(t, sc(0.6, w), sc(0.7, w)));
    c = mix(c, vec4(0.0549, 0.7373, 0.3725, 1.00), seg(t, sc(0.7, w), sc(0.8, w)));
    c = mix(c, vec4(0.1804, 0.5255, 1.0000, 1.00), seg(t, sc(0.8, w), sc(0.88, w)));
    c = mix(c, vec4(0.2118, 0.4706, 0.9686, 1.00), seg(t, sc(0.88, w), sc(1.0, w)));
    return c;
}

vec4 restingAt(float t) {
    vec4 c = vec4(0.3255, 0.5882, 0.9882, 1.00);
    c = mix(c, vec4(0.2118, 0.4706, 0.9686, 1.00), seg(t, 0.0, 1.0));
    return c;
}

vec4 talkingAt(float t) {
    vec4 c = vec4(0.8078, 0.8863, 1.0000, 1.00);
    c = mix(c, vec4(0.4980, 0.6627, 0.9765, 1.00), seg(t, 0.0, 1.0));
    return c;
}

vec4 beadAt(float t) {
    vec4 c = vec4(0.3255, 0.5882, 0.9882, 0.00);
    c = mix(c, vec4(0.5176, 0.7020, 0.9804, 1.00), seg(t, 0.0, 0.25));
    c = mix(c, vec4(0.7059, 0.8118, 0.9725, 1.00), seg(t, 0.25, 0.5));
    c = mix(c, vec4(0.4588, 0.6431, 0.9725, 1.00), seg(t, 0.5, 0.75));
    c = mix(c, vec4(0.2118, 0.4706, 0.9686, 0.00), seg(t, 0.75, 1.0));
    return c;
}

// the palettes at t (0 .. 1 along an arc of f degrees), premultiplied
vec4 stack(float t, float f) {
    float ae = max(1.0 - flavor, 0.0);
    float ac = max(1.0 - abs(flavor - 1.0), 0.0);
    float ad = max(flavor - 1.0, 0.0);
    vec4 d = vec4(0.0);
    if (ae > 0.0)
        d = over(pre(flourishAt(t, flourish)), ae, d);
    if (ac > 0.0)
        d = over(pre(restingAt(t)), ac, d);
    if (ad > 0.0)
        d = over(pre(talkingAt(t)), ad, d);
    if (bead > -1.0 && bead < 1.0) {
        float w = 62.0 / f;
        float c = 0.5 - (w + 1.0) * bead * 0.5;
        d = over(pre(beadAt((t - c) / w + 0.5)), 1.0, d);
    }
    return d;
}

void main() {
    vec2 p = (qt_TexCoord0 - 0.5) * sizePx;
    float R = 0.5 * sizePx;
    float r = length(p);
    float hw = 0.07 * sizePx + 0.5;
    if (sweep < 0.5 || r < R - hw - 1.0 || r > R + hw + 1.0) {
        fragColor = vec4(0.0);
        return;
    }
    // degrees from 6 o'clock, clockwise (to the left of the screen) positive
    float delta = degrees(atan(p.y, p.x)) - 90.0;
    delta = mod(delta + 180.0, 360.0) - 180.0;

    // the band, its inner edge faded out
    float tb = (delta + 0.5 * sweep) / sweep;
    vec4 col = vec4(0.0);
    if (tb >= 0.0 && tb <= 1.0) {
        float inner = R - hw;
        float cov = smoothstep(inner - 0.5, inner + 0.5, r) * (1.0 - smoothstep(R + hw - 0.5, R + hw + 0.5, r));
        float rm = clamp((r - 0.86 * R) / (0.14 * R), 0.0, 1.0);
        col = stack(tb, sweep) * (cov * rm);
    }
    // the line over 90 % of the sweep
    float s9 = 0.9 * sweep;
    float tl = (delta + 0.5 * s9) / s9;
    if (tl >= 0.0 && tl <= 1.0) {
        float cl = 1.0 - smoothstep(linePx - 0.5, linePx + 0.5, abs(r - R));
        vec4 line = stack(tl, s9) * cl;
        col = line + col * (1.0 - line.a);
    }
    // both fade out at the ends
    float s1 = sweep + 1.0;
    float tm = (delta + 0.5 * s1) / s1;
    float m = clamp(min(tm, 1.0 - tm) / 0.25, 0.0, 1.0);
    fragColor = col * (m * qt_Opacity);
}
