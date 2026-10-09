#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float phase;
    float density;
};
layout(binding = 1) uniform sampler2D source;
vec4 frame(float index, vec2 uv) {
    vec2 tile = vec2(mod(index, 8.0), floor(index / 8.0));
    return texture(source, (tile + clamp(uv, vec2(0.001), vec2(0.999))) / vec2(8.0, 4.0));
}
void main() {
    float position = fract(phase) * 32.0;
    float index = floor(position);
    vec2 uv = qt_TexCoord0;
    vec4 cloud = mix(frame(index, uv), frame(mod(index + 1.0, 32.0), uv), fract(position));
    cloud *= min(density, 1.0 / max(cloud.a, 0.0001));
    fragColor = cloud * qt_Opacity;
}
