#include <metal_stdlib>
using namespace metal;

struct VSOut { float4 pos [[position]]; float2 uv; };

struct GlassElement {
    float4 rect;      // x,y,w,h in px
    float  radius;    // px
    float  intensity;
    uint   kind;
    float4 tint;      // rgba
};

struct Uniforms {
    float2 viewSize;
    float  time;
    uint   count;
    uint   _pad;
};

vertex VSOut glassVS(uint vid [[vertex_id]],
                     const device float4* vbuf [[buffer(0)]])
{
    float4 v = vbuf[vid];
    VSOut o;
    o.pos = float4(v.xy, 0.0, 1.0);
    o.uv  = v.zw;
    return o;
}

static inline float sdRoundRect(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

static inline float hash21(float2 p) {
    float n = sin(dot(p, float2(12.9898, 78.233)));
    return fract(n * 43758.5453);
}

fragment float4 glassFS(VSOut in [[stage_in]],
                        constant Uniforms& U [[buffer(0)]],
                        const device GlassElement* E [[buffer(1)]])
{
    float2 px = in.uv * U.viewSize;

    float alpha = 0.0;
    float rim = 0.0;
    float3 tintAcc = float3(1.0);

    uint n = min(U.count, 16u);
    for (uint i = 0; i < n; i++) {
        float4 r = E[i].rect;
        float2 center = r.xy + r.zw * 0.5;
        float2 halfSize   = r.zw * 0.5;

        float2 p = px - center;
        float d  = sdRoundRect(p, halfSize, E[i].radius);

        float aa = 1.2;
        float fill = 1.0 - smoothstep(0.0, aa, d);
        float edge = 1.0 - smoothstep(0.0, aa, abs(d));

        float a = fill * (0.18 + 0.10 * edge) * E[i].intensity;
        alpha = max(alpha, a);

        rim = max(rim, pow(edge, 0.65) * 0.35 * E[i].intensity);
        tintAcc = max(tintAcc, E[i].tint.rgb);
    }

    if (alpha <= 0.0005) return float4(0.0);

    float top = smoothstep(0.9, 0.2, in.uv.y);
    float highlight = top * 0.12 * alpha;

    float g = (hash21(px + U.time * 10.0) - 0.5) * 0.03;

    float3 col = tintAcc * (0.98 + g) + float3(1.0) * (0.10 * alpha);
    col += float3(1.0) * (rim + highlight);

    return float4(col, alpha);
}
