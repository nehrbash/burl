#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float phase;
    float ritualPhase;
};
layout(binding = 1) uniform sampler2D source;
void main() {
    vec4 art = texture(source, qt_TexCoord0);
    // The painted disc occupies 80% of the sprite; the corona stays emissive.
    vec2 p = (qt_TexCoord0 - vec2(0.5, 0.485)) / 0.4;
    float radius = length(p);
    vec3 normal = vec3(p.x, -p.y, sqrt(max(0.0, 1.0 - dot(p, p))));
    float angle = phase * 6.28318530718;
    float day = smoothstep(-0.025, 0.055, dot(normal, vec3(sin(angle), 0.0, -cos(angle))));
    float disc = 1.0 - smoothstep(0.96, 1.015, radius);
    vec3 shade = mix(vec3(0.16, 0.12, 0.24), vec3(1.0), day);
    float gold = smoothstep(0.04, 0.2, art.g - art.b) * smoothstep(0.15, 0.55, art.g);
    float sweep = pow(0.5 + 0.5 * cos(atan(p.y, p.x) - ritualPhase), 10.0);
    float breath = 0.5 + 0.5 * sin(ritualPhase * 8.0);
    art.rgb *= mix(vec3(1.12 + breath * 0.22), shade, disc);
    art.rgb += vec3(1.0, 0.62, 0.2) * gold * (0.3 + sweep * 0.85) * disc;
    art.rgb = min(art.rgb, vec3(art.a));
    fragColor = art * qt_Opacity;
}
