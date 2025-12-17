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
    constant float  &appear        [[buffer(7)]]
)
{
    float2 uv = in.uv;

    // ---------- aspect-correct space ----------
    float aspect = viewSize.x / viewSize.y;
    float2 p      = float2(uv.x * aspect, uv.y);
    float2 center = float2(bubbleCenter.x * aspect, bubbleCenter.y);

    // ---------- capsule geometry ----------
    float2 baseSize   = float2(1.2, 0.8);
    float  baseCorner = baseSize.y * 0.5;

    float s  = clamp(stretch, -0.6, 0.6);
    float sx = 1.0 - abs(s) * 1.2;
    float sy = 1.0 + 0.5 * abs(s);

    // ---------- APPEAR ANIM (scale + fade) ----------
    float a = saturate(appear);
    float grow = smoothstep(0.0, 1.0, a);
    float scale = mix(0.4, 1.0, grow);

    float2 boxSize = float2(baseSize.x * sx * scale,
                            baseSize.y * sy * scale);
    float  corner  = baseCorner * sy * scale;

    // ---------- SDF ----------
    float sdf  = smoothRectSDF(p, center, boxSize, corner, 2.15);
    float absS = abs(sdf);
    
    // ---------- masks ----------
    float shapeMask = 1.0 - smoothstep(0.0, 0.028, sdf);

    float rimOuter = 0.09;
    float rimInner = 0.02;
    float rimMask  = smoothstep(rimOuter, rimInner, absS);

    float gate = shapeMask * rimMask;
    
    if (gate <= 0.001) {
        discard_fragment();
    }

    float3 base = background.sample(sampler, uv).rgb;

    // ---------- SDF normal ----------
    float2 grad = float2(dfdx(sdf), dfdy(sdf));
    float2 n    = normalize(grad + 1e-6);
    
    float thickness = 0.2;
    float t = saturate(absS / thickness);

    float refMask  = smoothstep(0.6, 0.0, t);

    // =====================================================
    //                 REFRACTION
    // =====================================================
    
    float blurOuter = smoothstep(0.6, 0.0, absS);
    float refBase = 0.08;
    float refMax  = 0.65;
    float refStrength = refBase + refMax * blurOuter;
    float2 offset = n * refStrength * 0.2;
    
    float chroma = 0.20 * blurOuter;

    float3 s1 = background.sample(sampler, uv - offset * (1.0 + chroma)).rgb;
    float3 s2 = background.sample(sampler, uv - offset * (1.0 - chroma)).rgb;

    float3 refractedChromatic = float3(
        s1.r,
        mix(s1.g, s2.g, 0.55),
        s2.b * 1.12
    );
    
    float3 refracted = refractedChromatic;
    
    // =====================================================
    //                 MIPMAP BLUR
    // =====================================================
    
    float blurMask = smoothstep(1, 0.0, t);
    float blurLOD = mix(0.0, 4, blurMask);
    float3 blurred = background.sample(sampler, uv, level(blurLOD)).rgb;

    // =====================================================
    //                 COMPOSITION
    // =====================================================
    
    float3 lens = mix(base, refracted, refMask);
    float3 glass = mix(lens, blurred, blurMask);

    // fade-ин: на старте пузырь ещё маленький и прозрачный
    float fade = smoothstep(0.0, 0.15, a);    // 0..1, первые ~15% пути

    float3 final = mix(base, glass, shapeMask * fade);

    return float4(final, shapeMask * fade);
}
