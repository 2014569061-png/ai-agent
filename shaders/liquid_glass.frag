#version 460 core
#include <flutter/runtime_effect.glsl>

// Liquid Glass 边缘折射着色器。
//
// 供 ImageFilter.shader(FragmentShader) 使用，作用于 BackdropFilter 的背景纹理。
// 契约（见 dart:ui painting.dart:4461）：
//   1. 第一个 uniform 必须是 vec2
//   2. 必须至少有一个 sampler uniform
//   3. uniform 的 float 下标 = 声明顺序，sampler 不占下标
//      本例：u_size=(0,1) u_radius=2 u_refraction=3 u_edge=4 u_gloss=5

uniform vec2 u_size;         // [0,1] 面板尺寸（逻辑像素）
uniform float u_radius;      // [2]   圆角半径（逻辑像素）
uniform float u_refraction;  // [3]   边缘折射位移强度（逻辑像素）
uniform float u_edge;        // [4]   折射带宽度（逻辑像素）
uniform float u_gloss;       // [5]   左上镜面高光强度 0..1
uniform float u_chromatic;   // [6]   边缘色差强度

uniform sampler2D u_texture_input;

out vec4 frag_color;

// 圆角矩形有符号距离场：内部为负、边界为 0、外部为正
float sdRoundedBox(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - halfSize + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

void main() {
    vec2 size = max(u_size, vec2(1.0));
    vec2 p = FlutterFragCoord().xy;

    vec2 halfSize = size * 0.5;
    float r = clamp(u_radius, 0.0, min(halfSize.x, halfSize.y));
    float d = sdRoundedBox(p - halfSize, halfSize, r);

    // t: 0 = 贴着边缘，1 = 已进入内核
    float edge = max(u_edge, 1.0);
    float t = clamp(-d / edge, 0.0, 1.0);

    // 边缘邻近度，smoothstep 过渡避免出现硬边
    float prox = 1.0 - t;
    float smoothProx = prox * prox * (3.0 - 2.0 * prox);

    // 采样点沿法线向内位移：越靠边折射越强，形成透镜边缘
    vec2 inward = halfSize - p;
    float len = max(length(inward), 1e-4);
    vec2 dir = inward / len;

    float strength = u_refraction * smoothProx * smoothProx;
    vec2 samplePos = p + dir * strength;

    vec2 uv = samplePos / size;
#ifdef IMPELLER_TARGET_OPENGLES
    uv.y = 1.0 - uv.y;
#endif
    uv = clamp(uv, vec2(0.0), vec2(1.0));

    vec2 outward = -dir;
    vec2 chromaticOffset = normalize(outward) *
        (u_chromatic * smoothProx / size);
    vec4 redSample = texture(
        u_texture_input,
        clamp(uv + chromaticOffset, vec2(0.0), vec2(1.0))
    );
    vec4 centerSample = texture(u_texture_input, uv);
    vec4 blueSample = texture(
        u_texture_input,
        clamp(uv - chromaticOffset, vec2(0.0), vec2(1.0))
    );
    vec4 color = vec4(redSample.r, centerSample.g, blueSample.b, centerSample.a);

    // 左上方向的镜面高光：只在贴近边缘处出现
    vec2 lightDir = normalize(vec2(-0.7, -0.7));
    float facing = clamp(dot(outward, lightDir), 0.0, 1.0);
    float rim = smoothProx * smoothProx;
    // Keep the highlight directional and add a restrained lower bevel. The
    // old shader only added white to the sampled color, which made the panel
    // read as a transparent tint when the backdrop was already pale.
    float spec = u_gloss * 0.34 * rim * facing;
    vec2 lowerLightDir = normalize(vec2(0.7, 0.7));
    float lowerFacing = clamp(dot(outward, lowerLightDir), 0.0, 1.0);
    float lowerShade = u_gloss * 0.16 * rim * lowerFacing;
    vec3 surfaceColor = color.rgb * (1.0 - lowerShade) + vec3(spec);

    frag_color = vec4(surfaceColor, color.a);
}
