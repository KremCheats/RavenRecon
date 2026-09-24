// RavenRecon v3 — filtered IL2CPP runtime dumper for non-JB iOS
// drop-in replacement for RavenRecon/Tweak.mm
// arm64e-safe. UIKit-free. writes to app Documents.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <dlfcn.h>
#include <stdint.h>
#include <string.h>

#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif

// ============================================================
// config
// ============================================================

static NSString * const kOutName   = @"recon_dump.txt";
static NSString * const kMagic     = @"=== RAVEN RECON DUMP v3 ===";

// only these assemblies get walked. exact name match against il2cpp image name.
static NSArray<NSString*> *kTargetAssemblies = nil;

// class name substrings to match. case-sensitive.
// "Player" matches Player, LocalPlayer, PlayerController, etc.
static NSArray<NSString*> *kTargetClasses = nil;

static const NSTimeInterval kPollInterval = 2.0;
static const NSTimeInterval kPollTimeout  = 300.0;

// ============================================================
// il2cpp opaque types
// ============================================================

typedef struct Il2CppDomain   Il2CppDomain;
typedef struct Il2CppAssembly Il2CppAssembly;
typedef struct Il2CppImage    Il2CppImage;
typedef struct Il2CppClass    Il2CppClass;
typedef struct Il2CppField    Il2CppField;
typedef struct Il2CppMethod   Il2CppMethod;
typedef struct Il2CppType     Il2CppType;

// ============================================================
// resolved symbols
// ============================================================

static void* (*p_domain_get)(void) = NULL;
static const Il2CppAssembly** (*p_domain_get_assemblies)(const Il2CppDomain*, size_t*) = NULL;
static const Il2CppImage* (*p_assembly_get_image)(const Il2CppAssembly*) = NULL;
static const char* (*p_image_get_name)(const Il2CppImage*) = NULL;
static const Il2CppClass** (*p_image_get_classes)(const Il2CppImage*, size_t*) = NULL;
static const char* (*p_class_get_name)(const Il2CppClass*) = NULL;
static const char* (*p_class_get_namespace)(const Il2CppClass*) = NULL;
static const Il2CppClass* (*p_class_get_parent)(const Il2CppClass*) = NULL;
static const Il2CppField* (*p_class_get_fields)(const Il2CppClass*, void**) = NULL;
static const Il2CppMethod* (*p_class_get_methods)(const Il2CppClass*, void**) = NULL;
static const char* (*p_field_get_name)(const Il2CppField*) = NULL;
static size_t (*p_field_get_offset)(const Il2CppField*) = NULL;
static const Il2CppType* (*p_field_get_type)(const Il2CppField*) = NULL;
static const char* (*p_type_get_name)(const Il2CppType*) = NULL;
static const char* (*p_method_get_name)(const Il2CppMethod*) = NULL;
static uint32_t (*p_method_get_param_count)(const Il2CppMethod*) = NULL;
static void* (*p_method_get_pointer)(const Il2CppMethod*) = NULL;

// ============================================================
// module base
// ============================================================

static const void* g_moduleBase  = NULL;
static intptr_t    g_moduleSlide = 0;

static void ra_find_module(void) {
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char* nm = _dyld_get_image_name(i);
        if (!nm) continue;
        if (strstr(nm, "UnityFramework")) {
            g_moduleBase  = _dyld_get_image_header(i);
            g_moduleSlide = _dyld_get_image_vmaddr_slide(i);
            return;
        }
    }
    // fallback: main executable
    g_moduleBase  = _dyld_get_image_header(0);
    g_moduleSlide = _dyld_get_image_vmaddr_slide(0);
}

// ============================================================
// pac strip
// ============================================================

static inline uintptr_t ra_strip_pac(void* p) {
#if __has_feature(ptrauth_calls)
    return (uintptr_t)ptrauth_strip(p, ptrauth_key_asia);
#else
    return (uintptr_t)p;
#endif
}

// ============================================================
// symbol resolution
// ============================================================

#define RZ(handle, sym, var) do { \
    var = (__typeof__(var))dlsym(handle, sym); \
} while (0)

static int ra_resolve_symbols(void) {
    void* h = RTLD_DEFAULT;
    RZ(h, "il2cpp_domain_get",            p_domain_get);
    RZ(h, "il2cpp_domain_get_assemblies", p_domain_get_assemblies);
    RZ(h, "il2cpp_assembly_get_image",    p_assembly_get_image);
    RZ(h, "il2cpp_image_get_name",        p_image_get_name);
    RZ(h, "il2cpp_image_get_classes",     p_image_get_classes);
    RZ(h, "il2cpp_class_get_name",        p_class_get_name);
    RZ(h, "il2cpp_class_get_namespace",   p_class_get_namespace);
    RZ(h, "il2cpp_class_get_parent",      p_class_get_parent);
    RZ(h, "il2cpp_class_get_fields",      p_class_get_fields);
    RZ(h, "il2cpp_class_get_methods",     p_class_get_methods);
    RZ(h, "il2cpp_field_get_name",        p_field_get_name);
    RZ(h, "il2cpp_field_get_offset",      p_field_get_offset);
    RZ(h, "il2cpp_field_get_type",        p_field_get_type);
    RZ(h, "il2cpp_type_get_name",         p_type_get_name);
    RZ(h, "il2cpp_method_get_name",       p_method_get_name);
    RZ(h, "il2cpp_method_get_param_count", p_method_get_param_count);
    // not always exported. optional.
    RZ(h, "il2cpp_method_get_method_pointer", p_method_get_pointer);

    if (!p_domain_get || !p_domain_get_assemblies || !p_assembly_get_image ||
        !p_image_get_name || !p_image_get_classes || !p_class_get_name ||
        !p_class_get_fields || !p_class_get_methods || !p_field_get_name ||
        !p_field_get_offset || !p_method_get_name || !p_method_get_param_count) {
        // try RTLD_SELF as fallback for any missing
        void* self = RTLD_SELF;
        if (!p_domain_get)             RZ(self, "il2cpp_domain_get", p_domain_get);
        if (!p_domain_get_assemblies)  RZ(self, "il2cpp_domain_get_assemblies", p_domain_get_assemblies);
        if (!p_assembly_get_image)     RZ(self, "il2cpp_assembly_get_image", p_assembly_get_image);
        if (!p_image_get_name)         RZ(self, "il2cpp_image_get_name", p_image_get_name);
        if (!p_image_get_classes)      RZ(self, "il2cpp_image_get_classes", p_image_get_classes);
        if (!p_class_get_name)         RZ(self, "il2cpp_class_get_name", p_class_get_name);
        if (!p_class_get_namespace)    RZ(self, "il2cpp_class_get_namespace", p_class_get_namespace);
        if (!p_class_get_parent)       RZ(self, "il2cpp_class_get_parent", p_class_get_parent);
        if (!p_class_get_fields)       RZ(self, "il2cpp_class_get_fields", p_class_get_fields);
        if (!p_class_get_methods)      RZ(self, "il2cpp_class_get_methods", p_class_get_methods);
        if (!p_field_get_name)         RZ(self, "il2cpp_field_get_name", p_field_get_name);
        if (!p_field_get_offset)       RZ(self, "il2cpp_field_get_offset", p_field_get_offset);
        if (!p_field_get_type)         RZ(self, "il2cpp_field_get_type", p_field_get_type);
        if (!p_type_get_name)          RZ(self, "il2cpp_type_get_name", p_type_get_name);
        if (!p_method_get_name)        RZ(self, "il2cpp_method_get_name", p_method_get_name);
        if (!p_method_get_param_count) RZ(self, "il2cpp_method_get_param_count", p_method_get_param_count);
    }

    return (p_domain_get && p_domain_get_assemblies && p_assembly_get_image &&
            p_image_get_name && p_image_get_classes && p_class_get_name &&
            p_class_get_fields && p_class_get_methods && p_field_get_name &&
            p_field_get_offset && p_method_get_name && p_method_get_param_count) ? 0 : -1;
}

// ============================================================
// helpers
// ============================================================

static BOOL ra_string_matches_any(NSString* s, NSArray<NSString*>* patterns) {
    if (!s || !patterns) return NO;
    for (NSString* p in patterns) {
        if ([s isEqualToString:p]) return YES;
    }
    return NO;
}

static BOOL ra_string_contains_any(NSString* s, NSArray<NSString*>* patterns) {
    if (!s || !patterns) return NO;
    for (NSString* p in patterns) {
        if ([s containsString:p]) return YES;
    }
    return NO;
}

// read method pointer without il2cpp_method_get_method_pointer if it's missing.
// on modern IL2CPP (27+), MethodInfo.methodPointer is the first field.
static void* ra_method_pointer_raw(const Il2CppMethod* m) {
    if (p_method_get_pointer) {
        return p_method_get_pointer(m);
    }
    if (!m) return NULL;
    void** raw = (void**)m;
    return raw[0];
}

// ============================================================
// dumper
// ============================================================

static void ra_dump(void) {
    NSString* bundle = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
    NSMutableString* out = [NSMutableString stringWithCapacity:1 << 20];

    [out appendFormat:@"%@\n", kMagic];
    [out appendFormat:@"date: %@\n", [NSDate date]];
    [out appendFormat:@"bundle: %@\n", bundle];
    [out appendFormat:@"module_base: %p\n", g_moduleBase];
    [out appendFormat:@"module_slide: 0x%lX\n", (unsigned long)g_moduleSlide];
    [out appendFormat:@"filter.assemblies: %@\n", [kTargetAssemblies componentsJoinedByString:@","]];
    [out appendFormat:@"filter.classes: %@\n", [kTargetClasses componentsJoinedByString:@","]];

    Il2CppDomain* domain = (Il2CppDomain*)p_domain_get();
    if (!domain) {
        [out appendString:@"ERROR: il2cpp_domain_get returned NULL\n"];
        goto write_out;
    }

    size_t asmCount = 0;
    const Il2CppAssembly** asms = p_domain_get_assemblies(domain, &asmCount);
    [out appendFormat:@"assembly_count: %zu\n\n", asmCount];
    if (!asms) {
        [out appendString:@"ERROR: assembly list NULL\n"];
        goto write_out;
    }

    for (size_t i = 0; i < asmCount; i++) {
        const Il2CppAssembly* asm_ = asms[i];
        if (!asm_) continue;

        const Il2CppImage* img = p_assembly_get_image(asm_);
        if (!img) continue;
        const char* an = p_image_get_name(img);
        if (!an) continue;

        NSString* asmName = [NSString stringWithUTF8String:an];
        if (!ra_string_matches_any(asmName, kTargetAssemblies)) continue;

        size_t classCount = 0;
        const Il2CppClass** classes = p_image_get_classes(img, &classCount);
        if (!classes) continue;

        NSMutableString* body = [NSMutableString stringWithCapacity:1 << 16];
        size_t matched = 0;

        for (size_t c = 0; c < classCount; c++) {
            const Il2CppClass* klass = classes[c];
            if (!klass) continue;

            const char* cn = p_class_get_name(klass);
            if (!cn) continue;
            NSString* clsName = [NSString stringWithUTF8String:cn];
            if (!ra_string_contains_any(clsName, kTargetClasses)) continue;
            matched++;

            const char* ns = p_class_get_namespace(klass);
            NSString* nsName = ns ? [NSString stringWithUTF8String:ns] : @"";

            const Il2CppClass* parent = p_class_get_parent(klass);
            NSString* parentName = @"";
            if (parent) {
                const char* pn = p_class_get_name(parent);
                const char* pns = p_class_get_namespace(parent);
                parentName = [NSString stringWithFormat:@"%s%s%s",
                              pns ? pns : "",
                              (pns && *pns) ? "." : "",
                              pn ? pn : "?"];
            }

            [body appendFormat:@"CLASS: %s%s%s\n",
             nsName.length ? [nsName UTF8String] : "",
             nsName.length ? "." : "",
             [clsName UTF8String]];
            if (parentName.length) {
                [body appendFormat:@"  parent: %@\n", parentName];
            }

            // ---- instance fields ----
            [body appendString:@"  fields (instance):\n"];
            void* fiter = NULL;
            const Il2CppField* fld = NULL;
            int fieldCount = 0;
            while ((fld = p_class_get_fields(klass, &fiter)) != NULL) {
                const char* fn = p_field_get_name(fld);
                size_t off = p_field_get_offset(fld);
                const char* tn = "?";
                if (p_field_get_type && p_type_get_name) {
                    const Il2CppType* ft = p_field_get_type(fld);
                    if (ft) {
                        const char* t = p_type_get_name(ft);
                        if (t) tn = t;
                    }
                }
                [body appendFormat:@"    +0x%04zX  %s  %s\n",
                 off, tn, fn ? fn : "?"];
                fieldCount++;
                if (fieldCount > 4096) break; // sanity
            }
            if (fieldCount == 0) {
                [body appendString:@"    (none)\n"];
            }
            [body appendString:@"  fields (static): STATIC: not implemented (v4)\n"];

            // ---- methods ----
            [body appendString:@"  methods:\n"];
            void* miter = NULL;
            const Il2CppMethod* m = NULL;
            int methodCount = 0;
            while ((m = p_class_get_methods(klass, &miter)) != NULL) {
                const char* mn = p_method_get_name(m);
                uint32_t pc = p_method_get_param_count(m);
                void* mp = ra_method_pointer_raw(m);
                uintptr_t mpAddr = mp ? ra_strip_pac(mp) : 0;
                if (mpAddr && g_moduleBase) {
                    uintptr_t baseAddr = (uintptr_t)g_moduleBase;
                    if (mpAddr >= baseAddr) {
                        [body appendFormat:@"    M %s (%u) @ 0x%lx (rva 0x%lx)\n",
                         mn ? mn : "?", pc,
                         (unsigned long)mpAddr,
                         (unsigned long)(mpAddr - baseAddr)];
                    } else {
                        [body appendFormat:@"    M %s (%u) @ 0x%lx\n",
                         mn ? mn : "?", pc, (unsigned long)mpAddr];
                    }
                } else {
                    [body appendFormat:@"    M %s (%u)\n", mn ? mn : "?", pc];
                }
                methodCount++;
                if (methodCount > 8192) break;
            }
            if (methodCount == 0) {
                [body appendString:@"    (none)\n"];
            }

            [body appendString:@"\n"];
        }

        [out appendFormat:@"=========================================\n"];
        [out appendFormat:@"ASSEMBLY: %@ (classes: %zu, matched: %zu)\n",
         asmName, classCount, matched];
        [out appendFormat:@"=========================================\n\n"];
        [out appendString:body];
        [out appendString:@"\n"];
    }

write_out:;
    NSString* docs = [NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    if (!docs) docs = NSTemporaryDirectory();
    NSString* path = [docs stringByAppendingPathComponent:kOutName];

    NSError* err = nil;
    BOOL ok = [out writeToFile:path atomically:YES
                      encoding:NSUTF8StringEncoding error:&err];
    if (ok) {
        NSLog(@"[RavenRecon] wrote %lu bytes to %@",
              (unsigned long)[out lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
              path);
    } else {
        NSLog(@"[RavenRecon] write failed: %@", err);
    }
}

// ============================================================
// poll loop
// ============================================================

static void ra_poll(NSTimeInterval start) {
    if (ra_resolve_symbols() == 0) {
        Il2CppDomain* d = (Il2CppDomain*)p_domain_get();
        if (d) {
            size_t n = 0;
            const Il2CppAssembly** a = p_domain_get_assemblies(d, &n);
            if (a && n > 0) {
                NSLog(@"[RavenRecon] domain ready: %zu assemblies", n);
                ra_find_module();
                ra_dump();
                return;
            }
        }
    }

    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:
        [NSDate dateWithTimeIntervalSince1970:start]];
    if (elapsed > kPollTimeout) {
        NSLog(@"[RavenRecon] timeout waiting for il2cpp domain");
        return;
    }
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPollInterval * NSEC_PER_SEC)),
        dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0),
        ^{ ra_poll(start); });
}

// ============================================================
// entry
// ============================================================

%ctor {
    static dispatch_once_t onceT;
    dispatch_once(&onceT, ^{
        kTargetAssemblies = @[ @"Assembly-CSharp" ];
        kTargetClasses = @[
            @"GameManager", @"Player", @"LocalPlayer",
            @"Weapon", @"WeaponController", @"Gun", @"Projectile",
            @"AimAssist", @"AimBot", @"CameraController",
            @"Hitbox", @"HitBox", @"Bone",
            @"Team", @"Faction", @"Room", @"MatchManager",
            @"Health", @"Damageable", @"CharacterController",
            @"NetworkController", @"PhotonView", @"PhotonPlayer",
            @"PhotonNetwork", @"Entity", @"Pawn", @"Character",
            @"Target", @"Enemy"
        ];

        NSLog(@"[RavenRecon] loaded. polling for il2cpp domain...");
        NSTimeInterval t0 = [[NSDate date] timeIntervalSince1970];
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
            dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0),
            ^{ ra_poll(t0); });
    });
}
