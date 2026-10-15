module WireAtlas

// CP2077 Wire Atlas REDscript bridge.
// Read-only helpers that expose Codeware reflection/resource capability to CET.

@addMethod(GameInstance)
public static func WireAtlasBridgeVersion() -> String {
  return "WireAtlas.REDscript/0.2";
}

@addMethod(GameInstance)
public static func WireAtlasCodewareClassCount() -> Int32 {
  let classes: array<ref<ReflectionClass>> = Reflection.GetClasses();
  return ArraySize(classes);
}

@addMethod(GameInstance)
public static func WireAtlasCodewareGlobalFunctionCount() -> Int32 {
  let funcs: array<ref<ReflectionStaticFunc>> = Reflection.GetGlobalFunctions();
  return ArraySize(funcs);
}

@addMethod(GameInstance)
public static func WireAtlasResourceExists(path: ResRef) -> Bool {
  let depot: ref<ResourceDepot> = GameInstance.GetResourceDepot();
  if !IsDefined(depot) {
    return false;
  };
  return depot.ResourceExists(path);
}
