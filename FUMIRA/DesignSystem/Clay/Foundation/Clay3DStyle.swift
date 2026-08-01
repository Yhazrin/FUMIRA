import SwiftUI

/// Shared clay style contract for 3D renderers (RealityKit / Three.js).
/// Defines the material properties, lighting, and surface language
/// that must be consistent between SwiftUI 2.5D and 3D scenes.
///
/// Import this file's values into your RealityKit Material or Three.js MeshStandardMaterial.
enum Clay3DStyle {

    // MARK: - Material roughness (0 = mirror, 1 = fully rough)

    /// Default clay surface roughness — matte but not dead flat.
    static let surfaceRoughness: Float = 0.52

    /// Slightly smoother for interactive elements (buttons, dials).
    static let interactiveRoughness: Float = 0.44

    /// Very rough for background / environment surfaces.
    static let environmentRoughness: Float = 0.76

    // MARK: - Material metalness

    /// Clay is non-metallic.
    static let metalness: Float = 0.0

    // MARK: - Base colors (sRGB hex for 3D pipelines)

    static let charcoalHex: UInt32 = 0x202425
    static let warmWhiteHex: UInt32 = 0xF2EEE5
    static let orangeHex: UInt32 = 0xFF672A
    static let limeHex: UInt32 = 0xB7D83D
    static let yellowHex: UInt32 = 0xFFC52A

    // MARK: - Rim / shadow colors (darker variants for depth)

    static let warmWhiteRimHex: UInt32 = 0xCEC7B8
    static let orangeRimHex: UInt32 = 0xC9441D
    static let limeRimHex: UInt32 = 0x7E9A27
    static let yellowRimHex: UInt32 = 0xC18B14

    // MARK: - Lighting

    /// Primary light direction — top-left, slightly forward.
    static let primaryLightDirection = (x: Float(-0.4), y: Float(0.8), z: Float(0.6))

    /// Ambient light intensity multiplier.
    static let ambientIntensity: Float = 0.50

    /// Key light intensity multiplier.
    static let keyLightIntensity: Float = 1.20

    /// Fill light intensity multiplier.
    static let fillLightIntensity: Float = 0.40

    // MARK: - Contact shadow

    /// Shadow softness for contact shadows in 3D scenes.
    static let contactShadowSoftness: Float = 0.78

    /// Shadow opacity at contact point.
    static let contactShadowOpacity: Float = 0.24

    // MARK: - Corners

    /// Default corner radius in meters for 3D objects.
    /// Scale proportionally to object size.
    static let defaultCornerRadiusRatio: Float = 0.08

    /// Large surface corner radius ratio.
    static let largeCornerRadiusRatio: Float = 0.12

    // MARK: - Grain / texture

    /// Grain scale — controls the density of surface noise.
    /// Lower = finer grain, higher = coarser.
    static let grainScale: Float = 18.0

    /// Grain intensity — how visible the surface texture is.
    static let grainIntensity: Float = 0.045

    // MARK: - Vegetation / organic shapes

    static let vegetationBaseColorHex: UInt32 = 0x7E9A27
    static let vegetationTipColorHex: UInt32 = 0xB7D83D
    static let trunkColorHex: UInt32 = 0x5C4033

    // MARK: - Character / figure

    static let characterSkinHex: UInt32 = 0xF2D5B5
    static let characterClothHex: UInt32 = 0xFF672A
}

// MARK: - Three.js export helper

#if canImport(JavaScriptCore)
extension Clay3DStyle {
    /// Returns a JS-compatible object literal string for Three.js MeshStandardMaterial config.
    static func threeJSMaterial(hex: UInt32, roughness: Float = surfaceRoughness) -> String {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        return """
        {
          color: new THREE.Color(\(r), \(g), \(b)),
          roughness: \(roughness),
          metalness: \(metalness),
          flatShading: false
        }
        """
    }
}
#endif
