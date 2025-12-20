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

fragment float4 bubbleCapsule(
    VertexOut in                   [[stage_in]],
    texture2d<float> background    [[texture(0)]],
    sampler sampler                [[sampler(0)]],
    constant float2 &viewSize      [[buffer(4)]],
    constant float  &stretch       [[buffer(5)]],
    constant float2 &bubbleCenter  [[buffer(6)]],
    constant float  &appear        [[buffer(7)]],
    constant float2 &bubbleViewSize [[buffer(8)]]
)
{
    float2 uv = in.uv;
    float a = saturate(appear);

    if (a <= 0.001) {
        return float4(0.0, 0.0, 0.0, 0.0);
    }

    // ---------- APPEAR: fade + scale ----------
    float fade = smoothstep(0.0, 1, a);
    float grow = smoothstep(0.25, 1.0, a);
    
    const float extraScale = 0.20;
    float scale = 1.0 + extraScale * grow;

    // ---------- aspect-correct space ----------
    float aspect = viewSize.x / viewSize.y;
    float2 p      = float2(uv.x * aspect, uv.y);
    float2 center = float2(bubbleCenter.x * aspect, bubbleCenter.y);

    // ---------- capsule geometry ----------
    float ratio  = bubbleViewSize.x / bubbleViewSize.y;
    float height = bubbleViewSize.y / viewSize.y;
    
    float2 baseSize   = float2(height * ratio, height);
    float  baseCorner = baseSize.y * 0.5;

    float s  = clamp(stretch, -0.6, 0.6);
    float sx = 1.0 - abs(s) * 1.2;
    float sy = 1.0 + 0.5 * abs(s);

    float2 boxSize = float2(baseSize.x * sx * scale,
                            baseSize.y * sy * scale);
    float  corner  = baseCorner * sy * scale;

    // ---------- SDF ----------
    float sdf  = smoothRectSDF(p, center, boxSize, corner, 2.15);
    float absS = abs(sdf);
    
    // ---------- masks ----------
    float shapeMask = 1.0 - smoothstep(0.0, 0.028, sdf);
    
    const float topFracFull    = 0.30;
    const float bottomFracFull = 0.20;
    
    const float sideFracFull = 0.30;
    
    float fullH = 2.0 * boxSize.y;
    float fullW = 2.0 * boxSize.x;
    
    float topOffset    = topFracFull    * fullH;
    float bottomOffset = bottomFracFull * fullH;

    float outerTop    = center.y + boxSize.y;
    float outerBottom = center.y - boxSize.y;
    
    float innerTop    = outerTop    - topOffset;
    float innerBottom = outerBottom + bottomOffset;
    
    float innerHalfH   = 0.5 * (innerTop - innerBottom);
    innerHalfH = max(innerHalfH, 0.05 * fullH);

    float innerCenterY = 0.5 * (innerTop + innerBottom);
    float2 innerCenter = float2(center.x, innerCenterY);

    float innerHalfW = boxSize.x - sideFracFull * fullW;
    innerHalfW = max(innerHalfW, 0.05 * fullW);

    float2 innerBoxSize = float2(innerHalfW, innerHalfH);

    float heightScale = innerHalfH / boxSize.y;
    float innerCorner = corner * heightScale;

    float sdfInner = smoothRectSDF(p, innerCenter, innerBoxSize, innerCorner, 2.15);

    float aa = max(fwidth(sdf), 0.0015);

    float outerMask = smoothstep(aa, 0.0, sdf);
    float innerMask = smoothstep(aa, 0.0, sdfInner);

    float rimMask = outerMask * (1.0 - innerMask);

    shapeMask *= fade;
    rimMask   *= fade;
    
    float gate = shapeMask * rimMask;
    
    if (gate <= 0.001) {
        return float4(0.0, 0.0, 0.0, 0.0);
    }

    float3 base = background.sample(sampler, uv).rgb;
    
    // ---------- SDF normal ----------
    float2 grad = float2(dfdx(sdf), dfdy(sdf));
    float2 n    = normalize(grad + 1e-6);
    
    float depth = saturate(absS / 0.2);
    float refMask = pow(1.0 - depth, 1.2);

    // =====================================================
    //                 REFRACTION
    // =====================================================
    
    float refBase = 0.10;
    float refMax  = 0.70;
    float refStrength = refBase + refMax * refMask;
    
    float2 offset = n * refStrength * 0.035;

    float chroma = 0.35 * refMask;

    float3 s1 = background.sample(sampler, uv - offset * (1.0 + chroma)).rgb;
    float3 s2 = background.sample(sampler, uv - offset * (1.0 - chroma)).rgb;

    float r = mix(s1.r, s2.r, 0.7);
    float g = mix(s1.g, s2.g, 0.10);
    float b = pow(mix(s1.b, s2.b, 0.9), 1.20);

    float3 baseRGB = float3(r, g, b);
    float purpleAmount = 0.7 * refMask;
    
    float3 refractedChromatic = mix(
        baseRGB,
        baseRGB,
        purpleAmount
    );
    
    float brightnessBoost = 0.10 * refMask;
    float3 refracted = refractedChromatic * (1.0 + brightnessBoost);
    
    // =====================================================
    //                 MIPMAP BLUR
    // =====================================================
    
    float thickness = 0.5;
    float t = saturate(absS / thickness);
    float blurMask = smoothstep(0.5, 0.0, t);
    float blurLOD = mix(0.0, 7, blurMask);
    float3 blurred = background.sample(sampler, uv, level(blurLOD)).rgb;

    // =====================================================
    //                 COMPOSITION
    // =====================================================
    
    float3 lens  = mix(base, refracted, refMask * 2);
    float3 glass = mix(lens, blurred, blurMask);

    float mask = rimMask * shapeMask * fade;
    float3 final = mix(base, glass, mask);
    float bubbleAlpha = a * rimMask;
    
    return float4(final * bubbleAlpha, bubbleAlpha);
}
