#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float phase;
    vec4 accent;
    float goldMix;
    float brightness;
    float bend;
};
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D growthMap;

void main() {
    vec2 uv = qt_TexCoord0;
    uv.y += bend * sin(3.14159265 * uv.x);
    vec4 wood = texture(source, uv);
    float arrival = texture(growthMap, uv).r;
    float threshold = progress * 1.04 - 0.02;
    float reveal = smoothstep(arrival - 0.018, arrival + 0.018, threshold);
    reveal *= smoothstep(0.0, 0.025, progress);
    float front = exp(-pow((arrival - threshold + 0.018) / 0.026, 2.0));
    front *= 1.0 - smoothstep(0.92, 1.0, progress);
    float pulse = pow(0.5 + 0.5 * cos(6.283185 * (arrival * 1.5 - phase)), 18.0);
    float ridge = dot(wood.rgb, vec3(0.2126, 0.7152, 0.0722));
    float inscription = smoothstep(0.025, 0.13, wood.r - wood.b);
    vec3 gold = vec3(1.55, 1.08, 0.46) * ridge;
    vec3 bark = mix(wood.rgb, gold, goldMix) * brightness;
    vec3 light = accent.rgb * wood.a * (front * 0.45 + pulse * (ridge * 0.24 + inscription * 0.32));
    fragColor = vec4(min(bark + light, vec3(wood.a)), wood.a) * reveal * qt_Opacity;
}
