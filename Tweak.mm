// ────────────────────────────────────────────────────────────────
// RavenRecon — IL2CPP class dumper tweak.
// Container-only output. No PHPhotoLibrary, no pasteboard.
// Writes to <Documents>/ravenrecon/ (text + PNG pages).
// ────────────────────────────────────────────────────────────────

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

// ════════════════════════════════════════════════════════════════
// IL2CPP opaque types
// ════════════════════════════════════════════════════════════════
typedef struct Il2CppDomain   Il2CppDomain;
typedef struct Il2CppAssembly Il2CppAssembly;
typedef struct Il2CppImage    Il2CppImage;
typedef struct Il2CppClass    Il2CppClass;
typedef struct FieldInfo      FieldInfo;
typedef struct MethodInfo     MethodInfo;

// ════════════════════════════════════════════════════════════════
// Resolved IL2CPP API
// ════════════════════════════════════════════════════════════════
typedef struct {
    Il2CppDomain*   (*domain_get)(void);
    Il2CppAssembly**(*domain_get_assemblies)(Il2CppDomain*, size_t*);
    Il2CppImage*    (*assembly_get_image)(const Il2CppAssembly*);
    const char*     (*image_get_name)(const Il2CppImage*);
    size_t          (*image_get_class_count)(const Il2CppImage*);
    Il2CppClass*    (*image_get_class)(const Il2CppImage*, size_t);
    const char*     (*class_get_name)(Il2CppClass*);
    const char*     (*class_get_namespace)(Il2CppClass*);
    uint32_t        (*class_get_field_count)(Il2CppClass*);
    FieldInfo*      (*class_get_fields)(Il2CppClass*, void**);
    const char*     (*field_get_name)(FieldInfo*);
    size_t          (*field_get_offset)(FieldInfo*);
    size_t          (*class_get_method_count)(Il2CppClass*);
    MethodInfo*     (*class_get_methods)(Il2CppClass*, void**);
    const char*     (*method_get_name)(MethodInfo*);
    uint32_t        (*method_get_param_count)(MethodInfo*);
} Il2CppApi;

static Il2CppApi api = {0};

// ════════════════════════════════════════════════════════════════
// Container paths
// ════════════════════════════════════════════════════════════════
static NSString* raven_dump_dir(void) {
    NSArray<NSString*>* paths =
        NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                            NSUserDomainMask, YES);
    NSString* docs = paths.firstObject ?: NSTemporaryDirectory();
    NSString* dir  = [docs stringByAppendingPathComponent:@"ravenrecon"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return dir;
}

// ════════════════════════════════════════════════════════════════
// IL2CPP resolution
//   1. dlsym against the whole process
//   2. dlopen UnityFramework by image name, dlsym against the handle
// ════════════════════════════════════════════════════════════════
static void* raven_resolve_handle(void) {
    const char* names[] = {
        "UnityFramework",
        "UnityFramework.framework/UnityFramework",
        NULL
    };
    for (int i = 0; names[i]; i++) {
        void* h = dlopen(names[i], RTLD_NOW | RTLD_NOLOAD);
        if (h) return h;
    }
    return RTLD_DEFAULT;
}

static void* raven_sym(void* handle, const char* name) {
    void* p = dlsym(handle, name);
    if (!p) p = dlsym(RTLD_DEFAULT, name);
    if (!p) p = dlsym(RTLD_SELF, name);
    return p;
}

static BOOL raven_load_il2cpp(void) {
    void* h = raven_resolve_handle();

    #define BIND(field, sym) \
        api.field = (void*)raven_sym(h, sym); \
        if (!api.field) { NSLog(@"[raven] missing symbol: %s", sym); return NO; }

    BIND(domain_get,             "il2cpp_domain_get")
    BIND(domain_get_assemblies,  "il2cpp_domain_get_assemblies")
    BIND(assembly_get_image,     "il2cpp_assembly_get_image")
    BIND(image_get_name,         "il2cpp_image_get_name")
    BIND(image_get_class_count,  "il2cpp_image_get_class_count")
    BIND(image_get_class,        "il2cpp_image_get_class")
    BIND(class_get_name,         "il2cpp_class_get_name")
    BIND(class_get_namespace,    "il2cpp_class_get_namespace")
    BIND(class_get_field_count,  "il2cpp_class_get_field_count")
    BIND(class_get_fields,       "il2cpp_class_get_fields")
    BIND(field_get_name,         "il2cpp_field_get_name")
    BIND(field_get_offset,       "il2cpp_field_get_offset")
    BIND(class_get_method_count, "il2cpp_class_get_method_count")
    BIND(class_get_methods,      "il2cpp_class_get_methods")
    BIND(method_get_name,        "il2cpp_method_get_name")
    BIND(method_get_param_count, "il2cpp_method_get_param_count")

    #undef BIND
    return YES;
}

// ════════════════════════════════════════════════════════════════
// IL2CPP dump
// ════════════════════════════════════════════════════════════════
static NSString* raven_dump_il2cpp(void) {
    NSMutableString* out = [NSMutableString stringWithCapacity:1 << 20];
    [out appendString:@"// RavenRecon dump\n"];
    [out appendString:@"// IL2CPP class layout\n\n"];

    if (!raven_load_il2cpp()) {
        [out appendString:@"!! failed to resolve IL2CPP symbols\n"];
        return out;
    }

    Il2CppDomain* domain = api.domain_get();
    if (!domain) {
        [out appendString:@"!! no IL2CPP domain (is the runtime up?)\n"];
        return out;
    }

    size_t asmCount = 0;
    Il2CppAssembly** assemblies = api.domain_get_assemblies(domain, &asmCount);
    if (!assemblies) {
        [out appendString:@"!! no assemblies\n"];
        return out;
    }

    [out appendFormat:@"// assemblies: %zu\n\n", asmCount];

    for (size_t a = 0; a < asmCount; a++) {
        @autoreleasepool {
            Il2CppImage* image = api.assembly_get_image(assemblies[a]);
            if (!image) continue;

            const char* imgName = api.image_get_name(image);
            [out appendFormat:@"\n// ==== %s ====\n",
                imgName ? imgName : "<unnamed>"];

            size_t classCount = api.image_get_class_count(image);
            for (size_t c = 0; c < classCount; c++) {
                Il2CppClass* klass = api.image_get_class(image, c);
                if (!klass) continue;

                const char* ns   = api.class_get_namespace(klass);
                const char* name = api.class_get_name(klass);
                if (!name) continue;

                NSString* fullName = (ns && ns[0])
                    ? [NSString stringWithFormat:@"%s.%s", ns, name]
                    : [NSString stringWithFormat:@"%s", name];

                [out appendFormat:@"class %@  // size:0x%zx\n",
                    fullName, (size_t)0];

                // fields
                void* fIter = NULL;
                FieldInfo* field = NULL;
                while ((field = api.class_get_fields(klass, &fIter))) {
                    const char* fname = api.field_get_name(field);
                    size_t off = api.field_get_offset(field);
                    [out appendFormat:@"    [F] +0x%04zx  %s\n",
                        off, fname ? fname : "<anon>"];
                }

                // methods
                void* mIter = NULL;
                MethodInfo* method = NULL;
                while ((method = api.class_get_methods(klass, &mIter))) {
                    const char* mname = api.method_get_name(method);
                    uint32_t pc = api.method_get_param_count(method);
                    [out appendFormat:@"    [M] %s(%u)\n",
                        mname ? mname : "<anon>", pc];
                }
            }
        }
    }

    return out;
}

// ════════════════════════════════════════════════════════════════
// TCC-safe page renderer.
// Writes PNGs to <Documents>/ravenrecon/pages/, no Photos, no TCC.
// ════════════════════════════════════════════════════════════════
static void raven_save_pages(NSString* dump) {
    @autoreleasepool {
        if (dump.length == 0) return;

        NSArray<NSString*>* lines = [dump componentsSeparatedByString:@"\n"];
        const NSUInteger kLinesPerPage = 55;
        const NSUInteger kMaxPages     = 200;

        NSUInteger totalPages = (lines.count + kLinesPerPage - 1) / kLinesPerPage;
        NSUInteger pageCount  = MIN(totalPages, kMaxPages);
        if (pageCount == 0) return;

        NSString* pagesDir = [raven_dump_dir() stringByAppendingPathComponent:@"pages"];
        [[NSFileManager defaultManager] createDirectoryAtPath:pagesDir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];

        UIFont* font = [UIFont monospacedSystemFontOfSize:11
                                                   weight:UIFontWeightRegular];
        NSDictionary* attrs = @{
            NSFontAttributeName            : font,
            NSForegroundColorAttributeName : UIColor.blackColor
        };

        const CGSize kPageSize = CGSizeMake(1242, 2208);

        for (NSUInteger p = 0; p < pageCount; p++) {
            @autoreleasepool {
                UIGraphicsBeginImageContextWithOptions(kPageSize, YES, 1.0);
                [[UIColor whiteColor] setFill];
                UIRectFill((CGRect){ .origin = CGPointZero, .size = kPageSize });

                NSUInteger start = p * kLinesPerPage;
                NSUInteger end   = MIN(start + kLinesPerPage, lines.count);
                NSString* pageText =
                    [[lines subarrayWithRange:NSMakeRange(start, end - start)]
                        componentsJoinedByString:@"\n"];

                [pageText drawWithRect:(CGRect){ .origin = { 12, 24 },
                                                 .size   = kPageSize }
                               options:NSStringDrawingUsesLineFragmentOrigin
                            attributes:attrs
                               context:nil];

                UIImage* img = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
                if (!img) continue;

                NSString* outPath = [pagesDir stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"raven_%04lu.png",
                        (unsigned long)p]];

                NSData* png = UIImagePNGRepresentation(img);
                [png writeToFile:outPath atomically:YES];

                NSLog(@"[raven] page %lu/%lu -> %@",
                      (unsigned long)p, (unsigned long)pageCount, outPath);
            }
        }

        NSLog(@"[raven] wrote %lu pages to %@",
              (unsigned long)pageCount, pagesDir);
    }
}

// ════════════════════════════════════════════════════════════════
// Full recon pass
// ════════════════════════════════════════════════════════════════
static void raven_dump_everything(void) {
    @autoreleasepool {
        NSLog(@"[raven] recon starting");

        NSString* dump = raven_dump_il2cpp();

        NSString* txtPath = [raven_dump_dir()
            stringByAppendingPathComponent:@"recon_dump.txt"];
        [dump writeToFile:txtPath
               atomically:YES
                 encoding:NSUTF8StringEncoding
                    error:nil];
        NSLog(@"[raven] text dump -> %@ (%lu bytes)",
              txtPath, (unsigned long)[dump lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);

        raven_save_pages(dump);

        NSLog(@"[raven] recon complete");
    }
}

// ════════════════════════════════════════════════════════════════
// Entry — fires on load, schedules three passes.
// ════════════════════════════════════════════════════════════════
__attribute__((constructor))
static void recon_entry(void) {
    NSLog(@"[raven] loaded, scheduling recon passes");

    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)( 8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            raven_dump_everything();
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(45 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            raven_dump_everything();
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(90 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            raven_dump_everything();
        });
    });
}
