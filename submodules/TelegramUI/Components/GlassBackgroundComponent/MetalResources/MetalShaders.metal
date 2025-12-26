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

static inline float smin_poly(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
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

    // ---------- tuning knobs ----------
    const float baseAlpha      = 0.80;
    const float edgeAlphaBoost = 0.35;
    const float hazeStrength   = 0.80;
    const float rimStrength    = 0.28;
    const float highlightStr   = 0.25;
    const float shadowStr      = 0.0;
    const float grainStr       = 0.03;
    const float strokeW        = 1.5;

    const float liquidK     = 14;
    const float contactEps  = 1;
    
    uint n = (U.count < 16u) ? U.count : 16u;
    if (n == 0u) return float4(0.0);

    float bestDHard = 1e9;
    float4 bestRect = float4(0.0);
    float  bestIntensity = 1.0;
    float3 bestTint = float3(1.0);

    float bestD = 1e9;
    bool first = true;
    
    for (uint i = 0; i < n; i++) {
        float4 r = E[i].rect;
        float2 c = r.xy + r.zw * 0.5;
        float2 h = r.zw * 0.5;

        float di = sdRoundRect(px - c, h, E[i].radius);
        
        if (di < bestDHard) {
            bestDHard = di;
            bestRect = r;
            bestIntensity = E[i].intensity;
            bestTint = E[i].tint.rgb;
        }

        if (first) {
            bestD = di;
            first = false;
        } else {
            if (bestD <= contactEps && di <= contactEps) {
                bestD = smin_poly(bestD, di, liquidK);
            } else {
                bestD = min(bestD, di);
            }
        }
    }
    
    float aa = 1.25;

    float fill = 1.0 - smoothstep(0.0, aa, bestD);
    if (fill <= 0.0005) return float4(0.0);

    float edge = 1.0 - smoothstep(0.0, aa, abs(bestD));
    
    float2 local = (px - bestRect.xy) / max(bestRect.zw, float2(1.0));
    float y = clamp(local.y, 0.0, 1.0);

    // alpha
    float a = fill * (baseAlpha + edgeAlphaBoost * pow(edge, 0.7)) * bestIntensity;
    
    float stroke = 1.0 - smoothstep(strokeW, strokeW + aa, abs(bestD));
    a = max(a, stroke * 0.10 * bestIntensity);

    // lighting
    float rim = pow(edge, 0.55) * rimStrength * bestIntensity;

    float topBand = smoothstep(0.22, 0.02, y);
    float highlight = topBand * highlightStr * fill;

    float bottom = smoothstep(0.55, 1.0, y) * shadowStr * fill;

    // grain
    float g = (hash21(px + U.time * 6.0) - 0.5) * 2.0;
    float grain = g * grainStr;
    
    float haze = hazeStrength * fill + 0.18 * rim;

    float3 col = bestTint;
    col = mix(col, float3(1.0), haze);
    col += (rim + highlight) * float3(1.0);
    col -= bottom * float3(1.0);
    col *= (1.0 + grain);

    return float4(col, a);
}
