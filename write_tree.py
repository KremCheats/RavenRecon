#!/usr/bin/env python3
"""
RavenRecon — single-source generator.
Edits go here, never in the generated files.
"""

import os


def w(path, content):
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, "w") as f:
        f.write(content.lstrip("\n"))


w("Tweak.mm", r"""
// RavenRecon v3.3 — no assembly filter, class-name only. Scans all 163 asm.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#include <string.h>
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif

static NSString* const kOutName   = @"recon_dump.txt";
static NSString* const kHeartbeat = @"recon_alive.txt";
static NSString* const kMagic     = @"=== RAVEN RECON DUMP v3.3 ===";

// nil = scan every assembly. class filter still applies.
static NSArray* kTargetAssemblies = nil;
static NSArray* kTargetClasses = nil;

static const NSTimeInterval kPollInterval = 2.0;
static const NSTimeInterval kPollTimeout  = 300.0;

static NSString* ra_docs_dir(void) {
    NSString* d = [NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    if (!d) d = NSTemporaryDirectory();
    return d;
}

static void ra_write(NSString* filename, NSString* contents) {
    NSString* path = [ra_docs_dir() stringByAppendingPathComponent:filename];
    NSError* err = nil;
    [contents writeToFile:path atomically:YES
                 encoding:NSUTF8StringEncoding error:&err];
    if (err) NSLog(@"[RavenRecon] write %@ failed: %@", filename, err);
}

static void ra_append(NSString* filename, NSString* line) {
    NSString* path = [ra_docs_dir() stringByAppendingPathComponent:filename];
    NSString* existing = [NSString stringWithContentsOfFile:path
                                                   encoding:NSUTF8StringEncoding
                                                      error:nil];
    NSString* merged = existing ? [existing stringByAppendingString:line] : line;
    [merged writeToFile:path atomically:YES
               encoding:NSUTF8StringEncoding error:nil];
}

static void ra_log_stage(NSString* stage) {
    NSString* line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], stage];
    ra_append(kHeartbeat, line);
    NSLog(@"[RavenRecon] %@", stage);
}

typedef struct Il2CppDomain   Il2CppDomain;
typedef struct Il2CppAssembly Il2CppAssembly;
typedef struct Il2CppImage    Il2CppImage;
typedef struct Il2CppClass    Il2CppClass;
typedef struct Il2CppField    Il2CppField;
typedef struct Il2CppMethod   Il2CppMethod;
typedef struct Il2CppType     Il2CppType;

static void*              (*p_domain_get)(void)                                     = NULL;
static const Il2CppAssembly** (*p_domain_get_assemblies)(const Il2CppDomain*, size_t*) = NULL;
static const Il2CppImage* (*p_assembly_get_image)(const Il2CppAssembly*)           = NULL;
static const char*        (*p_image_get_name)(const Il2CppImage*)                   = NULL;
static size_t             (*p_image_get_class_count)(const Il2CppImage*)            = NULL;
static const Il2CppClass* (*p_image_get_class)(const Il2CppImage*, size_t)          = NULL;
static const char*        (*p_class_get_name)(const Il2CppClass*)                   = NULL;
static const char*        (*p_class_get_namespace)(const Il2CppClass*)              = NULL;
static const Il2CppClass* (*p_class_get_parent)(const Il2CppClass*)                 = NULL;
static const Il2CppField* (*p_class_get_fields)(const Il2CppClass*, void**)         = NULL;
static const Il2CppMethod*(*p_class_get_methods)(const Il2CppClass*, void**)        = NULL;
static const char*        (*p_field_get_name)(const Il2CppField*)                   = NULL;
static size_t             (*p_field_get_offset)(const Il2CppField*)                 = NULL;
static const Il2CppType*  (*p_field_get_type)(const Il2CppField*)                   = NULL;
static const char*        (*p_type_get_name)(const Il2CppType*)                     = NULL;
static const char*        (*p_method_get_name)(const Il2CppMethod*)                 = NULL;
static uint32_t           (*p_method_get_param_count)(const Il2CppMethod*)          = NULL;
static void*              (*p_method_get_pointer)(const Il2CppMethod*)              = NULL;

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
    g_moduleBase  = _dyld_get_image_header(0);
    g_moduleSlide = _dyld_get_image_vmaddr_slide(0);
}

static inline uintptr_t ra_strip_pac(void* p) {
#if __has_feature(ptrauth_calls)
    return (uintptr_t)ptrauth_strip(p, ptrauth_key_asia);
#else
    return (uintptr_t)p;
#endif
}

#define RZ(handle, sym, var) do { \
    var = (__typeof__(var))dlsym(handle, sym); \
    if (!var) [missing appendFormat:@"%s ", sym]; \
} while (0)

static int ra_resolve_symbols(void) {
    void* h = RTLD_DEFAULT;
    NSMutableString* missing = [NSMutableString string];

    RZ(h, "il2cpp_domain_get",              p_domain_get);
    RZ(h, "il2cpp_domain_get_assemblies",   p_domain_get_assemblies);
    RZ(h, "il2cpp_assembly_get_image",      p_assembly_get_image);
    RZ(h, "il2cpp_image_get_name",          p_image_get_name);
    RZ(h, "il2cpp_image_get_class_count",   p_image_get_class_count);
    RZ(h, "il2cpp_image_get_class",         p_image_get_class);
    RZ(h, "il2cpp_class_get_name",          p_class_get_name);
    RZ(h, "il2cpp_class_get_namespace",     p_class_get_namespace);
    RZ(h, "il2cpp_class_get_parent",        p_class_get_parent);
    RZ(h, "il2cpp_class_get_fields",        p_class_get_fields);
    RZ(h, "il2cpp_class_get_methods",       p_class_get_methods);
    RZ(h, "il2cpp_field_get_name",          p_field_get_name);
    RZ(h, "il2cpp_field_get_offset",        p_field_get_offset);
    RZ(h, "il2cpp_field_get_type",          p_field_get_type);
    RZ(h, "il2cpp_type_get_name",           p_type_get_name);
    RZ(h, "il2cpp_method_get_name",         p_method_get_name);
    RZ(h, "il2cpp_method_get_param_count",  p_method_get_param_count);
    p_method_get_pointer = (__typeof__(p_method_get_pointer))
        dlsym(h, "il2cpp_method_get_method_pointer");

    if (!p_domain_get || !p_domain_get_assemblies || !p_assembly_get_image ||
        !p_image_get_name || !p_image_get_class_count || !p_image_get_class ||
        !p_class_get_name || !p_class_get_fields || !p_class_get_methods ||
        !p_field_get_name || !p_field_get_offset ||
        !p_method_get_name || !p_method_get_param_count) {
        if (missing.length > 0) {
            ra_log_stage([NSString stringWithFormat:@"resolve: MISSING %@", missing]);
        }
        return -1;
    }
    return 0;
}

static BOOL ra_string_matches_any(NSString* s, NSArray* patterns) {
    if (!patterns) return YES;
    if (!s) return NO;
    for (NSString* p in patterns) if ([s isEqualToString:p]) return YES;
    return NO;
}

static BOOL ra_string_contains_any(NSString* s, NSArray* patterns) {
    if (!s || !patterns) return NO;
    for (NSString* p in patterns) if ([s containsString:p]) return YES;
    return NO;
}

static void* ra_method_pointer_raw(const Il2CppMethod* m) {
    if (p_method_get_pointer) return p_method_get_pointer(m);
    if (!m) return NULL;
    void** raw = (void**)m;
    return raw[0];
}

static void ra_dump(void) {
    ra_log_stage(@"dump: starting");

    NSString* bundle = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
    NSMutableString* out = [NSMutableString stringWithCapacity:1 << 20];

    [out appendFormat:@"%@\n", kMagic];
    [out appendFormat:@"date: %@\n", [NSDate date]];
    [out appendFormat:@"bundle: %@\n", bundle];
    [out appendFormat:@"module_base: %p\n", g_moduleBase];
    [out appendFormat:@"filter.assemblies: %@\n",
        kTargetAssemblies ? [kTargetAssemblies componentsJoinedByString:@","] : @"(all)"];
    [out appendFormat:@"filter.classes: %@\n", [kTargetClasses componentsJoinedByString:@","]];

    Il2CppDomain* domain = (Il2CppDomain*)p_domain_get();
    if (!domain) {
        ra_log_stage(@"dump: domain NULL");
        [out appendString:@"ERROR: il2cpp_domain_get returned NULL\n"];
        ra_write(kOutName, out);
        return;
    }

    size_t asmCount = 0;
    const Il2CppAssembly** asms = p_domain_get_assemblies(domain, &asmCount);
    [out appendFormat:@"assembly_count: %zu\n\n", asmCount];

    if (!asms) {
        ra_log_stage(@"dump: assemblies NULL");
        [out appendString:@"ERROR: assembly list NULL\n"];
        ra_write(kOutName, out);
        return;
    }

    size_t asmScanned = 0;
    size_t totalClasses = 0;
    size_t totalMatched = 0;

    for (size_t i = 0; i < asmCount; i++) {
        const Il2CppAssembly* asm_ = asms[i];
        if (!asm_) continue;
        const Il2CppImage* img = p_assembly_get_image(asm_);
        if (!img) continue;
        const char* an = p_image_get_name(img);
        if (!an) continue;

        asmScanned++;
        NSString* asmName = [NSString stringWithUTF8String:an];

        if (kTargetAssemblies && !ra_string_matches_any(asmName, kTargetAssemblies)) continue;

        size_t classCount = p_image_get_class_count(img);
        NSMutableString* body = [NSMutableString stringWithCapacity:1 << 16];
        size_t matchedInAsm = 0;

        for (size_t c = 0; c < classCount; c++) {
            const Il2CppClass* klass = p_image_get_class(img, c);
            if (!klass) continue;
            const char* cn = p_class_get_name(klass);
            if (!cn) continue;
            NSString* clsName = [NSString stringWithUTF8String:cn];
            if (!ra_string_contains_any(clsName, kTargetClasses)) continue;

            matchedInAsm++;
            totalMatched++;

            const char* ns = p_class_get_namespace(klass);
            NSString* nsName = ns ? [NSString stringWithUTF8String:ns] : @"";
            const Il2CppClass* parent = p_class_get_parent(klass);
            NSString* parentName = @"";
            if (parent) {
                const char* pn  = p_class_get_name(parent);
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
            [body appendFormat:@"  assembly: %@\n", asmName];

            [body appendString:@"  fields:\n"];
            void* fiter = NULL;
            const Il2CppField* fld = NULL;
            int fc = 0;
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
                fc++;
                if (fc > 4096) break;
            }
            if (fc == 0) [body appendString:@"    (none)\n"];

            [body appendString:@"  methods:\n"];
            void* miter = NULL;
            const Il2CppMethod* m = NULL;
            int mc = 0;
            while ((m = p_class_get_methods(klass, &miter)) != NULL) {
                const char* mn = p_method_get_name(m);
                uint32_t pc = p_method_get_param_count(m);
                void* mp = ra_method_pointer_raw(m);
                uintptr_t mpAddr = mp ? ra_strip_pac(mp) : 0;
                if (mpAddr && g_moduleBase && mpAddr >= (uintptr_t)g_moduleBase) {
                    [body appendFormat:@"    M %s (%u) @ 0x%lx (rva 0x%lx)\n",
                     mn ? mn : "?", pc,
                     (unsigned long)mpAddr,
                     (unsigned long)(mpAddr - (uintptr_t)g_moduleBase)];
                } else if (mpAddr) {
                    [body appendFormat:@"    M %s (%u) @ 0x%lx\n",
                     mn ? mn : "?", pc, (unsigned long)mpAddr];
                } else {
                    [body appendFormat:@"    M %s (%u)\n", mn ? mn : "?", pc];
                }
                mc++;
                if (mc > 8192) break;
            }
            if (mc == 0) [body appendString:@"    (none)\n"];
            [body appendString:@"\n"];
        }

        if (matchedInAsm > 0) {
            [out appendFormat:@"=========================================\n"];
            [out appendFormat:@"ASSEMBLY: %@ (classes: %zu, matched: %zu)\n",
             asmName, classCount, matchedInAsm];
            [out appendFormat:@"=========================================\n\n"];
            [out appendString:body];
            [out appendString:@"\n"];
            ra_log_stage([NSString stringWithFormat:
                @"dump: asm %@ matched %zu classes", asmName, matchedInAsm]);
        }
        totalClasses += classCount;
    }

    [out appendFormat:@"\n// scanned %zu asm, %zu classes, %zu matched\n",
        asmScanned, totalClasses, totalMatched];

    ra_write(kOutName, out);
    ra_log_stage([NSString stringWithFormat:
        @"dump: done. scanned=%zu matched=%zu wrote=%lu bytes",
        asmScanned, totalMatched,
        (unsigned long)[out lengthOfBytesUsingEncoding:NSUTF8StringEncoding]]);
}

static void ra_poll(NSTimeInterval start, BOOL firstTick) {
    if (firstTick) ra_log_stage(@"poll: first tick");

    if (ra_resolve_symbols() == 0) {
        Il2CppDomain* d = (Il2CppDomain*)p_domain_get();
        if (d) {
            size_t n = 0;
            const Il2CppAssembly** a = p_domain_get_assemblies(d, &n);
            if (a && n > 0) {
                ra_log_stage([NSString stringWithFormat:@"poll: domain ready (%zu asm)", n]);
                ra_find_module();
                ra_dump();
                return;
            }
        }
    }

    NSTimeInterval elapsed = [[NSDate date] timeIntervalSince1970] - start;
    if (elapsed > kPollTimeout) {
        ra_log_stage(@"poll: timeout waiting for il2cpp domain");
        return;
    }

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPollInterval * NSEC_PER_SEC)),
        dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
            ra_poll(start, NO);
        });
}

__attribute__((constructor))
static void ra_entry(void) {
    static dispatch_once_t onceT;
    dispatch_once(&onceT, ^{
        ra_write(kHeartbeat, [NSString stringWithFormat:
            @"=== RavenRecon heartbeat v3.3 ===\n"
            @"loaded at: %@\n"
            @"bundle: %@\n"
            @"docs dir: %@\n",
            [NSDate date],
            [[NSBundle mainBundle] bundleIdentifier] ?: @"?",
            ra_docs_dir()]);

        ra_log_stage(@"entry: constructor fired");

        kTargetAssemblies = nil;

        kTargetClasses = @[
            @"PlayerRoot", @"PlayerHealth", @"PlayerMovement", @"CameraController",
            @"PlayerMobView", @"ActiveMobView", @"MapPlayer", @"PlayerState",
            @"PlayerMetadata", @"PlayerCommand"
        ];

        NSTimeInterval t0 = [[NSDate date] timeIntervalSince1970];
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
            dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
                ra_poll(t0, YES);
            });
    });
}
""")


w("Makefile", r"""
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = CombatMaster

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RavenRecon
RavenRecon_FILES = Tweak.mm
RavenRecon_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
RavenRecon_FRAMEWORKS = Foundation UIKit
RavenRecon_LIBRARIES =

include $(THEOS_MAKE_PATH)/tweak.mk
""")


w("RavenRecon.plist", r"""
{ Filter = { Bundles = ( "com.AlfaBravo.CombatMaster" ); }; }
""")


w("control", r"""
Package: com.mahi.ravenrecon
Name: RavenRecon
Version: 1.1.5
Architecture: iphoneos-arm64
Description: IL2CPP class dumper — container-only output
Maintainer: mahi
Author: mahi
Section: Tweaks
Depends: firmware (>= 14.0)
""")


print("done - RavenRecon v3.3 sources generated")
