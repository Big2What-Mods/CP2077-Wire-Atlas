module WireAtlas

// This script directory is registered by WireAtlasNative.dll through RED4ext's
// Scripts API. CET uses this method as an end-to-end native-loader check.

@addMethod(GameInstance)
public static func WireAtlasNativeMarker() -> String {
  return "WireAtlas.RED4ext/0.2.1";
}
