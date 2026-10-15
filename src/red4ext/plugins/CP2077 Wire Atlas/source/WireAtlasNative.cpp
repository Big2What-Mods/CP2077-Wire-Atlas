// CP2077 Wire Atlas RED4ext native bootstrap
// Built against RED4ext loader API v1 ABI.
// Read-only: registers this plugin's REDscript folder with RED4ext.

using u8  = unsigned char;
using u16 = unsigned short;
using u32 = unsigned int;

namespace RED4ext::v1 {
struct SemVer {
    struct PrereleaseInfo { u32 type; u32 number; };
    u8 major;
    u16 minor;
    u32 patch;
    PrereleaseInfo prerelease;
};
struct FileVer { u16 major; u16 minor; u16 build; u16 revision; };
using PluginHandle = void*;
enum class EMainReason : u8 { Load = 0, Unload = 1 };
struct Scripts {
    bool (*Add)(PluginHandle, const wchar_t*);
    bool (*RegisterNeverRefType)(const char*);
    bool (*RegisterMixedRefType)(const char*);
};
struct Sdk {
    SemVer* runtime;
    void* logger;
    void* hooking;
    void* gameStates;
    Scripts* scripts;
};
struct PluginInfo {
    SemVer sdk;
    const wchar_t* name;
    const wchar_t* author;
    SemVer version;
    FileVer runtime;
};
}

#define RED4EXT_C_EXPORT extern "C" __declspec(dllexport)
#define RED4EXT_CALL __fastcall

static constexpr u32 API_V1 = 1;
static constexpr RED4ext::v1::SemVer SDK_1_0_0{1, 0, 0, {0, 0}};
static constexpr RED4ext::v1::SemVer PLUGIN_0_2_1{0, 2, 1, {0, 0}};
static constexpr RED4ext::v1::FileVer CP2077_2_31{3, 0, 80, 51928};

RED4EXT_C_EXPORT u32 RED4EXT_CALL Supports()
{
    return API_V1;
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* info)
{
    static const wchar_t name[] = L"CP2077 Wire Atlas Native";
    static const wchar_t author[] = L"Big2What & ChatGPT GPT-5.6 Sol";
    if (!info) return;
    info->sdk = SDK_1_0_0;
    info->name = name;
    info->author = author;
    info->version = PLUGIN_0_2_1;
    info->runtime = CP2077_2_31;
}

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle handle,
                                        RED4ext::v1::EMainReason reason,
                                        const RED4ext::v1::Sdk* sdk)
{
    if (reason == RED4ext::v1::EMainReason::Load)
    {
        if (!sdk || !sdk->scripts || !sdk->scripts->Add)
            return false;

        // IMPORTANT: RED4ext resolves relative script paths against the plugin
        // directory itself. Therefore the correct path is simply "scripts".
        // The previous build incorrectly passed the full game-relative path,
        // which RED4ext appended to the plugin directory and could not find.
        if (!sdk->scripts->Add(handle, L"scripts"))
            return false;
    }
    return true;
}

extern "C" int __stdcall DllMain(void*, unsigned long, void*)
{
    return 1;
}
