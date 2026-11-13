#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // the colour filter's matrix (ModesCore::filterMatrix, the 3x3 in the
    // upper left): Bedtime's Night light 2596 K or Grayscale
    mat4 colorMatrix;
};

layout(binding = 1) uniform sampler2D source;

void main(void) {
    vec4 c = texture(source, qt_TexCoord0);
    // the layer is premultiplied; the matrix works on the colour itself
    vec3 rgb = c.a > 0.0 ? c.rgb / c.a : c.rgb;
    rgb = clamp((colorMatrix * vec4(rgb, 1.0)).rgb, 0.0, 1.0);
    fragColor = vec4(rgb * c.a, c.a) * qt_Opacity;
}
