// RavenRecon — IL2CPP class dumper.
// Container-only output. No PHPhotoLibrary, no pasteboard.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

typedef void* (*t_domain_get)();
typedef void* (*t_thread_attach)(void*);
typedef void* (*t_assembly_get_image)(void*);
typedef size_t (*t_domain_get_assemblies)(void*, size_t*);
typedef size_t (*t_image_get_class_count)(void*);
typedef void* (*t_image_get_class)(void*, size_t);
typedef const char* (*t_class_get_name)(void*);
typedef const char* (*t_class_get_namespace)(void*);
typedef void* (*t_class_get_fields)(void*, void**);
typedef const char* (*t_field_get_name)(void*);
typedef size_t (*t_field_get_offset)(void*);
typedef void* (*t_class_get_methods)(void*, void**);
typedef const char* (*t_method_get_name)(void*);
typedef uint32_t (*t_method_get_param_count)(void*);

static t_domain_get p_domain_get = NULL;
static t_thread_attach p_thread_attach = NULL;
static t_assembly_get_image p_assembly_get_image = NULL;
static t_domain_get_assemblies p_domain_get_assemblies = NULL;
static t_image_get_class_count p_image_get_class_count = NULL;
static t_image_get_class p_image_get_class = NULL;
static t_class_get_name p_class_get_name = NULL;
static t_class_get_namespace p_class_get_namespace = NULL;
static t_class_get_fields p_class_get_fields = NULL;
static t_field_get_name p_field_get_name = NULL;
static t_field_get_offset p_field_get_offset = NULL;
static t_class_get_methods p_class_get_methods = NULL;
static t_method_get_name p_method_get_name = NULL;
static t_method_get_param_count p_method_get_param_count = NULL;

static void* rs(const char* n) {
    void* p = dlsym(RTLD_DEFAULT, n);
    if (!p) p = dlsym(RTLD_SELF, n);
    return p;
}

// Container dump directory: <Documents>/ravenrecon/
static NSString* raven_dump_dir(void) {
    NSArray* paths = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* docs = paths.firstObject ?: NSTemporaryDirectory();
    NSString* dir = [docs stringByAppendingPathComponent:@"ravenrecon"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return dir;
}

// Render the dump string into PNG pages, write to the app container.
// No Photos, no TCC.
static void saveDumpAsImages(NSString* dump) {
    if (dump.length == 0) return;

    NSArray* lines = [dump componentsSeparatedByString:@"\n"];
    const NSUInteger kLinesPerPage = 55;
    const NSUInteger kMaxPages = 200;

    NSUInteger total = lines.count;
    NSUInteger totalPages = (total + kLinesPerPage - 1) / kLinesPerPage;
    NSUInteger pageCount = MIN(totalPages, kMaxPages);
    if (pageCount == 0) return;

    NSString* pagesDir = [raven_dump_dir() stringByAppendingPathComponent:@"pages"];
    [[NSFileManager defaultManager] createDirectoryAtPath:pagesDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    UIFont* mono = [UIFont monospacedSystemFontOfSize:9
                                               weight:UIFontWeightRegular];
    NSDictionary* attrs = @{
        NSFontAttributeName: mono,
        NSForegroundColorAttributeName: [UIColor blackColor]
    };

    for (NSUInteger p = 0; p < pageCount; p++) {
        @autoreleasepool {
            NSUInteger start = p * kLinesPerPage;
            NSUInteger len = MIN(kLinesPerPage, total - start);
            NSArray* sub = [lines subarrayWithRange:NSMakeRange(start, len)];
            NSString* pageText = [NSString stringWithFormat:
                @"RAVEN RECON - page %lu/%lu\n\n%@",
                (unsigned long)(p + 1), (unsigned long)pageCount,
                [sub componentsJoinedByString:@"\n"]];

            CGSize maxSize = CGSizeMake(1400, 2400);
            CGRect rect = [pageText boundingRectWithSize:maxSize
                                                 options:NSStringDrawingUsesLineFragmentOrigin
                                              attributes:attrs
                                                 context:nil];
            CGSize size = CGSizeMake(ceil(rect.size.width) + 24,
                                     ceil(rect.size.height) + 24);

            UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
            [[UIColor whiteColor] setFill];
            UIRectFill(CGRectMake(0, 0, size.width, size.height));
            [pageText drawWithRect:CGRectMake(12, 12, size.width - 24,
                                              size.height - 24)
                           options:NSStringDrawingUsesLineFragmentOrigin
                        attributes:attrs
                           context:nil];
            UIImage* img = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();

            if (!img) continue;

            NSString* outPath = [pagesDir stringByAppendingPathComponent:
                [NSString stringWithFormat:@"raven_%04lu.png", (unsigned long)p]];
            NSData* png = UIImagePNGRepresentation(img);
            [png writeToFile:outPath atomically:YES];

            NSLog(@"[recon] page %lu/%lu -> %@",
                  (unsigned long)(p + 1), (unsigned long)pageCount, outPath);
        }
    }

    NSLog(@"[recon] wrote %lu page(s) to %@",
          (unsigned long)pageCount, pagesDir);
}

static void dumpEverything(void) {
    NSLog(@"[recon] dump starting");

    p_domain_get = (t_domain_get)rs("il2cpp_domain_get");
    p_thread_attach = (t_thread_attach)rs("il2cpp_thread_attach");
    p_assembly_get_image = (t_assembly_get_image)rs("il2cpp_assembly_get_image");
    p_domain_get_assemblies = (t_domain_get_assemblies)rs("il2cpp_domain_get_assemblies");
    p_image_get_class_count = (t_image_get_class_count)rs("il2cpp_image_get_class_count");
    p_image_get_class = (t_image_get_class)rs("il2cpp_image_get_class");
    p_class_get_name = (t_class_get_name)rs("il2cpp_class_get_name");
    p_class_get_namespace = (t_class_get_namespace)rs("il2cpp_class_get_namespace");
    p_class_get_fields = (t_class_get_fields)rs("il2cpp_class_get_fields");
    p_field_get_name = (t_field_get_name)rs("il2cpp_field_get_name");
    p_field_get_offset = (t_field_get_offset)rs("il2cpp_field_get_offset");
    p_class_get_methods = (t_class_get_methods)rs("il2cpp_class_get_methods");
    p_method_get_name = (t_method_get_name)rs("il2cpp_method_get_name");
    p_method_get_param_count = (t_method_get_param_count)rs("il2cpp_method_get_param_count");

    NSMutableString* out = [NSMutableString string];
    [out appendString:@"=== RAVEN RECON DUMP v2 ===\n"];
    [out appendFormat:@"date: %@\n", [NSDate date]];
    [out appendFormat:@"bundle: %@\n", [[NSBundle mainBundle] bundleIdentifier]];

    if (!p_domain_get || !p_domain_get_assemblies || !p_assembly_get_image) {
        [out appendString:@"ERROR: il2cpp core API missing\n"];
        goto writefile;
    }

    {
        void* domain = p_domain_get();
        if (!domain) {
            [out appendString:@"ERROR: null domain\n"];
            goto writefile;
        }
        if (p_thread_attach) p_thread_attach(domain);

        size_t assemblyCount = 0;
        void** assemblies = (void**)p_domain_get_assemblies(domain, &assemblyCount);
        [out appendFormat:@"assembly_count: %zu\n\n", assemblyCount];

        for (size_t a = 0; a < assemblyCount; a++) {
            void* asm_ = assemblies[a];
            if (!asm_) continue;
            void* img = p_assembly_get_image(asm_);
            if (!img) continue;
            size_t cc = p_image_get_class_count ? p_image_get_class_count(img) : 0;

            [out appendFormat:@"\n=========================================\n"];
            [out appendFormat:@"ASSEMBLY %zu (classes: %zu)\n", a, cc];
            [out appendFormat:@"=========================================\n"];

            size_t dumped = 0;
            for (size_t i = 0; i < cc; i++) {
                void* klass = p_image_get_class(img, i);
                if (!klass) continue;
                const char* cname = p_class_get_name ? p_class_get_name(klass) : NULL;
                const char* cns = p_class_get_namespace ? p_class_get_namespace(klass) : NULL;
                if (!cname) continue;
                dumped++;
                [out appendFormat:@"\nCLASS %s::%s\n", cns ? cns : "", cname];

                void* fiter = NULL;
                while (p_class_get_fields) {
                    void* fld = p_class_get_fields(klass, &fiter);
                    if (!fld) break;
                    const char* fn = p_field_get_name ? p_field_get_name(fld) : NULL;
                    size_t off = p_field_get_offset ? p_field_get_offset(fld) : 0;
                    [out appendFormat:@"    F %s @ 0x%lX\n",
                        fn ? fn : "?", (unsigned long)off];
                }

                void* miter = NULL;
                while (p_class_get_methods) {
                    void* m = p_class_get_methods(klass, &miter);
                    if (!m) break;
                    const char* mn = p_method_get_name ? p_method_get_name(m) : NULL;
                    uint32_t pc = p_method_get_param_count
                        ? p_method_get_param_count(m) : 0;
                    [out appendFormat:@"    M %s (%u)\n", mn ? mn : "?", pc];
                }
            }
            [out appendFormat:@"\nassembly %zu dumped %zu classes.\n", a, dumped];
        }
    }

writefile:;
    NSString* dir = raven_dump_dir();
    NSString* path = [dir stringByAppendingPathComponent:@"recon_dump.txt"];
    [out writeToFile:path
          atomically:YES
            encoding:NSUTF8StringEncoding
               error:nil];
    NSLog(@"[recon] wrote %@ (%lu bytes)", path, (unsigned long)out.length);

    // PNG pages — container only. No pasteboard write (TCC-protected
    // on iOS 16+), no Photos save.
    saveDumpAsImages(out);
}

__attribute__((constructor))
static void recon_entry(void) {
    @autoreleasepool {
        NSLog(@"[recon] loaded into %@", [[NSBundle mainBundle] bundleIdentifier]);
        NSArray* delays = @[@8, @45, @90];
        for (NSNumber* d in delays) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)([d doubleValue] * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                dumpEverything();
            });
        }
    }
}
