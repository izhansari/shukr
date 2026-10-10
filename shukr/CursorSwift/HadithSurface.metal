//
//  HadithSurface.metal
//  shukr
//
//  The hadith page's easter egg (setup's first page): a finger pushes through the gradient's colours like a hand through
//  water — they part round it, swirl a little, smear the way it moves and catch a touch of light; let go and they spring
//  back (the strength overshoots, so the surface wobbles once before it settles). Applied with `.layerEffect` by
//  `HadithPush` in FirstRunSetup.swift.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// - touch: the finger (points, in the layer); velocity: its speed (points/s); strength: 0 at rest, 1 pressed (may
///   swing a little negative as it springs back); radius: how far the push reaches.
[[ stitchable ]] half4 hadithPush(float2 position, SwiftUI::Layer layer, float2 touch, float2 velocity, float strength,
                                  float radius) {
    float2 d = position - touch;
    float dist = length(d);
    float falloff = exp(-(dist * dist) / (radius * radius));
    // Eased to nothing right under the fingertip: at full strength the centre folded in on itself (a dark pinch point).
    float core = smoothstep(0.0, radius * 0.35, dist);
    float2 dir = dist > 0.001 ? d / dist : float2(0.0);
    // Parted round the finger: each point shows the colour from nearer the finger.
    float2 push = dir * falloff * core * strength * radius * 0.45;
    // Smeared along the way it moves.
    float2 drag = velocity * falloff * strength * 0.03;
    // A little swirl.
    float angle = falloff * core * strength * 0.8;
    float c = cos(angle), s = sin(angle);
    float2 swirl = float2(d.x * c - d.y * s, d.x * s + d.y * c) - d;
    half4 colour = layer.sample(position - push - drag - swirl);
    // A touch of light where it's pressed.
    colour.rgb += half3(0.05, 0.11, 0.07) * half(max(strength, 0.0) * falloff);
    return colour;
}
