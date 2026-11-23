#version 450

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform Buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float end;
    float beginning;
    int keepInner;
} ubuf;

layout(binding = 1) uniform sampler2D source;

void main() {
    float x = qt_TexCoord0.x - 0.5;
    float y = qt_TexCoord0.y - 0.5;
    float distSq = x * x + y * y;

    vec4 texColor = texture(source, qt_TexCoord0);
    // nothing past end: the smoothstep below takes the pixel's distance as its first edge, which GLSL
    // leaves undefined past end (it came out as 1, so a radius under the screen's clipped nothing);
    // with end = 0.25 (every user but the face picker's reveal) the result is the same as before
    float inner = distSq < ubuf.end ? smoothstep(distSq, ubuf.end, ubuf.beginning) : 0.0;
    float mask = step(distSq, 0.25) * inner;

    if (ubuf.keepInner == 1) {
        fragColor = texColor * mask * ubuf.qt_Opacity;
    } else {
        fragColor = texColor * (1.0 - mask) * ubuf.qt_Opacity;
    }
}