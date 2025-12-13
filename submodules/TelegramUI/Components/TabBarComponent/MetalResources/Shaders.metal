//
//  Shaders.metal
//  TabBarComponent
//
//  Created by Максим Стегниенко on 11.12.2025.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct Vertex {
    float2 position;
    float2 uv;
};

float smoothRectSDF(float2 p, float2 center, float2 size, float radius, float smoothness)
{
    float2 d = abs(p - center) - (size * 0.5 - radius);
    float2 k = max(d, 0.0);
    float outside = (pow(k.x, smoothness) + pow(k.y, smoothness));
    outside = pow(outside, 1.0/smoothness);

    float inside = min(max(d.x, d.y), 0.0);
    return outside + inside - radius;
}

vertex VertexOut bubbleVertex(uint vid [[vertex_id]],
                              const device Vertex* verts [[buffer(0)]])
{
    VertexOut out;
    out.position = float4(verts[vid].position, 0.0, 1.0);
    out.uv = verts[vid].uv;
    return out;
}

fragment float4 bubbleCapsule_Final(
    VertexOut in [[stage_in]],
    texture2d<float> background [[texture(0)]],
    sampler sampler [[sampler(0)]],
    constant float2 &viewSize   [[buffer(4)]],
    constant float  &stretch    [[buffer(5)]],
    constant float2 &bubbleCenter [[buffer(6)]])
{
    float2 uv = in.uv;
    float aspect = viewSize.x / viewSize.y;
    float2 p = float2(uv.x * aspect, uv.y);
    float2 center = float2(bubbleCenter.x * aspect, bubbleCenter.y);

    // ------------------------ ГЕОМЕТРИЯ КАПСУЛЫ ------------------------
    float2 baseSize   = float2(1.3, 0.76);
    float  baseCorner = baseSize.y * 0.5;

    float s  = clamp(stretch, -0.6, 0.6);
    float sx = 1.0 - abs(s) * 1.2;
    float sy = 1.0 + 1.3 * abs(s);

    float2 boxSize = float2(baseSize.x * sx, baseSize.y * sy);
    float  corner  = baseCorner * sy;

    // SDF (лучше < 0 внутри)
    float sdf = smoothRectSDF(p, center, boxSize, corner, 2.15);
    float absS = abs(sdf);

    float mask = 1.0 - smoothstep(0.0, 0.028, sdf);
    float4 base = background.sample(sampler, uv);

    // ------------------------ НОРМАЛЬ SDF ДЛЯ РЕФРАКЦИИ ------------------------
    float2 grad = float2(dfdx(sdf), dfdy(sdf));
    float2 n    = normalize(grad + 1e-6);

    // ---------------------------------------
    // 2. РЕФРАКЦИЯ (как была, но поправим edgeWide)
    // ---------------------------------------
    float edgeWide = smoothstep(0.20, 0.0, absS);
    
    // ---- 1. Blur mask: inside of the rim
    float blurOuter = smoothstep(0.1, 0.0, absS);
    float blurInner = smoothstep(0.0, 0.3, absS);
    float blurMask  = blurOuter * (1.0 - blurInner);

    // ---- 2. Refraction strength
    float refBase = 0.10;
    float refMax  = 0.65;
    float refStrength = refBase + refMax * blurOuter;
    float2 offset = n * refStrength * 0.035;

    // ---- 3. Chromatic aberration
    float chroma = 0.20 * blurOuter;

    float3 s1 = background.sample(sampler, uv - offset * (1.0 + chroma)).rgb;
    float3 s2 = background.sample(sampler, uv - offset * (1.0 - chroma)).rgb;

    float3 refractedChromatic = float3(
        s1.r,
        mix(s1.g, s2.g, 0.55),
        s2.b * 1.12
    );

    // ---- 4. Multi-sample blur
    float blurRadius = 10;
    float2 blurDir   = normalize(offset + n * 1e-4) * blurRadius;

    float3 refractedBlur =
        background.sample(sampler, uv - offset + blurDir).rgb * 0.5 +
        background.sample(sampler, uv - offset - blurDir).rgb * 0.5;

    // ---- 5. Mix blur with refraction
    float blurMix = saturate(pow(blurMask, 1.7));

    float3 refracted = mix(refractedChromatic, refractedBlur, blurMix);

    // ---- 6. Add milk haze
    refracted += blurMask * 0.18;
    
    // --------------------- mix ---------------------
    float3 lensRGB = mix(base.rgb, refracted, edgeWide);
    float centerFill = 1.0 - smoothstep(0.0, 0.14, absS);

    lensRGB = mix(lensRGB, refracted, centerFill * 0.85 + edgeWide);
    // ------------------------ ВНУТРЕННИЙ СВЕТ + ГЛАСС EDTGE (из второго шейдера) ------------------------
    float2 local = (p - center) / boxSize;
    
    float rimOuter=0.02, rimInner=0.01;
    float rimMask = smoothstep(rimOuter, rimInner, absS);

    float rainbowOffset = 0.015;
    float rainbowWidth  = 0.030;
    float innerSdf = sdf + rainbowOffset;
    float rainbowMask = smoothstep(rainbowWidth,0.0,abs(innerSdf));

    float2 dir = normalize(local+1e-5);
    float angle = atan2(dir.y,dir.x);
    float t = angle/(2.0*M_PI_F)+0.5;

    float3 c1=float3(1.4,0.3,1.2);     // насыщенный фиолетовый
    float3 c2=float3(1.4,1.2,0.3);     // яркий жёлтый
    float3 c3=float3(0.2,1.3,1.6);
    
    float3 rainbow = mix(mix(c1,c2,smoothstep(0.0,0.5,t)), c3,smoothstep(0.5,1.0,t));
    float rainbowTopMask = smoothstep(0.2,0.8,abs(local.y));

    float3 edgeColor = mix(float3(1.0), rainbow, rainbowMask);
    edgeColor*=rainbowTopMask;

    float3 bubbleTint = edgeColor * rimMask * 0.7;

    // ------------------------ ФИНАЛ ------------------------
    float3 mixed = mix(base.rgb, lensRGB, mask);
    float3 finalRGB = mixed + bubbleTint * mask;
    
    return float4(finalRGB, 1);
}
