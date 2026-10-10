//
//  HadithSurface.metal
//  shukr
//
//  The hadith page's easter egg (setup's first page): a finger through calm water (owner: "pushing through it like calm
//  water", not "dragging a color around"). Every touch, and every little way along a drag, drops a ripple: a ring that
//  spreads out from where it fell and fades, bending what's under it (the gradient and its grain) with light and shade on
//  its slope — nothing is carried along. Applied with `.layerEffect` by `HadithSurface` in FirstRunSetup.swift.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// - time: seconds since the page opened. ripples: x, y, the time it fell, its strength — four floats a ripple.
[[ stitchable ]] half4 hadithWater(float2 position, SwiftUI::Layer layer, float time, device const float *ripples,
                                   int count) {
    float2 offset = float2(0.0);
    float shade = 0.0;
    for (int i = 0; i + 3 < count; i += 4) {
        float age = time - ripples[i + 2];
        if (age < 0.0 || age > 3.4) { continue; }
        float2 d = position - float2(ripples[i], ripples[i + 1]);
        float dist = length(d);
        if (dist < 0.001) { continue; }
        // A ring travelling out slowly (160 pt/s): a long, gentle wave packet round its front (calmer — owner: "kinda
        // erratic").
        float band = dist - age * 160.0;
        float packet = exp(-(band * band) / (2.0 * 40.0 * 40.0));
        float wave = sin(band * 0.06) * packet;
        // Fading slowly as it ages and as it spreads.
        float fade = exp(-age * 1.1) * ripples[i + 3] / (1.0 + dist * 0.004);
        offset += (d / dist) * wave * fade * 7.0;
        // Light on the ring's slope: crests catch it, troughs fall into shade (how a ripple shows on calm water).
        shade += cos(band * 0.06) * packet * fade;
    }
    half4 colour = layer.sample(position + offset);
    colour.rgb *= half(1.0 + 0.15 * shade);
    colour.rgb += half3(0.035, 0.05, 0.04) * half(max(shade, 0.0));
    return colour;
}
