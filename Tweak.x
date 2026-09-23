#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <string.h>
#import <stdio.h>
#import <mach-o/dyld.h>

// ============================================================
// PASTE YOUR WEBHOOK URL HERE
//   Example:  @"https://webhook.site/1234abcd-5678-... "
//   Leave as-is and the dumper will only write locally.
// ============================================================
static NSString* const kUploadURL = @"https://webhook.site/7ae342da-9360-4f2a-b137-097969a4b214";

typedef void*       (*t_domain_get)();
typedef void*       (*t_thread_attach)(void*);
typedef void*       (*t_domain_assembly_open)(void*, const char*);
typedef void*       (*t_assembly_get_image)(void*);
typedef size_t      (*t_image_get_class_count)(void*);
typedef void*       (*t_image_get_class)(void*, size_t);
typedef const char* (*t_class_get_name)(void*);
typedef const char* (*t_class_get_namespace)(void*);
typedef void*       (*t_class_get_fields)(void*, void**);
typedef const char* (*t_field_get_name)(void*);
typedef size_t      (*t_field_get_offset)(void*);
typedef void*       (*t_class_get_methods)(void*, void**);
typedef const char* (*t_method_get_name)(void*);
typedef uint32_t    (*t_method_get_param_count)(void*);

static t_domain_get             p_domain_get = NULL;
static t_thread_attach          p_thread_attach = NULL;
static t_domain_assembly_open   p_domain_assembly_open = NULL;
static t_assembly_get_image     p_assembly_get_image = NULL;
static t_image_get_class_count  p_image_get_class_count = NULL;
static t_image_get_class        p_image_get_class = NULL;
static t_class_get_name         p_class_get_name = NULL;
static t_class_get_namespace    p_class_get_namespace = NULL;
static t_class_get_fields       p_class_get_fields = NULL;
static t_field_get_name         p_field_get_name = NULL;
static t_field_get_offset       p_field_get_offset = NULL;
static t_class_get_methods      p_class_get_methods = NULL;
static t_method_get_name        p_method_get_name = NULL;
static t_method_get_param_count p_method_get_param_count = NULL;

static void* rs(const char* n) {
    void* p = dlsym(RTLD_DEFAULT, n);
    if (!p) p = dlsym(RTLD_SELF, n);
    return p;
}

// Case-insensitive substring search.
static bool containsCI(const char* hay, const char* needle) {
    if (!hay || !needle) return false;
    size_t hn = strlen(hay);
    size_t nn = strlen(needle);
    if (nn == 0 || hn < nn) return false;
    for (size_t i = 0; i + nn <= hn; i++) {
        if (strncasecmp(hay + i, needle, nn) == 0) return true;
    }
    return false;
}

static bool isRelevantClass(const char* name, const char* ns) {
    if (!name) return false;
    const char* keys[] = {
        "Player", "Camera", "Weapon", "Shoot", "Aim", "Health", "Team",
        "Bone", "Entity", "Pawn", "Character", "Game", "Local", "Manager",
        "Controller", "Hitbox", "Target", "Enemy", "Damage",
        NULL
    };
    for (int i = 0; keys[i]; i++) {
        if (containsCI(name, keys[i])) return true;
        if (ns && containsCI(ns, keys[i])) return true;
    }
    return false;
}

static void dumpEverything(void) {
    NSLog(@"[recon] dump starting");

    p_domain_get = (t_domain_get)rs("il2cpp_domain_get");
    p_thread_attach = (t_thread_attach)rs("il2cpp_thread_attach");
    p_domain_assembly_open = (t_domain_assembly_open)rs("il2cpp_domain_assembly_open");
    p_assembly_get_image = (t_assembly_get_image)rs("il2cpp_assembly_get_image");
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
    [out appendString:@"=== RAVEN RECON DUMP ===\n"];
    [out appendFormat:@"date: %@\n", [NSDate date]];
    [out appendFormat:@"bundle: %@\n", [[NSBundle mainBundle] bundleIdentifier]];

    if (!p_domain_get || !p_domain_assembly_open || !p_assembly_get_image) {
        [out appendString:@"ERROR: il2cpp API symbols missing via dlsym\n"];
        NSLog(@"[recon] il2cpp API missing — cannot dump");
        [out appendString:@"\n(likely stripped exports — pattern-scan fallback required)\n"];
        [out writeToFile:[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
                           stringByAppendingPathComponent:@"recon_dump.txt"]
              atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }

    void* domain = p_domain_get();
    if (!domain) {
        [out appendString:@"ERROR: null domain\n"];
    } else {
        if (p_thread_attach) p_thread_attach(domain);

        void* asm_ = p_domain_assembly_open(domain, "Assembly-CSharp");
        if (!asm_) {
            [out appendString:@"ERROR: Assembly-CSharp not found\n"];
        } else {
            void* img = p_assembly_get_image(asm_);
            if (!img) {
                [out appendString:@"ERROR: image null\n"];
            } else {
                size_t count = p_image_get_class_count ? p_image_get_class_count(img) : 0;
                [out appendFormat:@"class_count: %zu\n", count];
                [out appendString:@"=========================================\n\n"];

                size_t dumped = 0;
                for (size_t i = 0; i < count; i++) {
                    void* klass = p_image_get_class(img, i);
                    if (!klass) continue;
                    const char* cname = p_class_get_name ? p_class_get_name(klass) : NULL;
                    const char* cns = p_class_get_namespace ? p_class_get_namespace(klass) : NULL;
                    if (!isRelevantClass(cname, cns)) continue;

                    dumped++;
                    [out appendFormat:@"\nCLASS %s::%s\n", cns ? cns : "", cname ? cname : "?"];

                    // Fields
                    void* fiter = NULL;
                    while (p_class_get_fields) {
                        void* fld = p_class_get_fields(klass, &fiter);
                        if (!fld) break;
                        const char* fn = p_field_get_name ? p_field_get_name(fld) : NULL;
                        size_t off = p_field_get_offset ? p_field_get_offset(fld) : 0;
                        [out appendFormat:@"  F %s @ 0x%zX\n", fn ? fn : "?", off];
                    }

                    // Methods
                    void* miter = NULL;
                    while (p_class_get_methods) {
                        void* m = p_class_get_methods(klass, &miter);
                        if (!m) break;
                        const char* mn = p_method_get_name ? p_method_get_name(m) : NULL;
                        uint32_t pc = p_method_get_param_count ? p_method_get_param_count(m) : 0;
                        [out appendFormat:@"  M %s (%u)\n", mn ? mn : "?", pc];
                    }
                }
                [out appendFormat:@"\n=========================================\nDumped %zu relevant classes.\n", dumped];
            }
        }
    }

    // ---- Write to Documents ----
    NSString* dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString* path = [dir stringByAppendingPathComponent:@"recon_dump.txt"];
    [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSLog(@"[recon] wrote %@ (%lu bytes)", path, (unsigned long)out.length);

    // ---- Upload to webhook if configured ----
    if (kUploadURL.length > 0) {
        NSURL* url = [NSURL URLWithString:kUploadURL];
        if (url) {
            NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:url];
            req.HTTPMethod = @"POST";
            [req setValue:@"text/plain" forHTTPHeaderField:@"Content-Type"];
            req.HTTPBody = [out dataUsingEncoding:NSUTF8StringEncoding];
            req.timeoutInterval = 45.0;

            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            NSURLSessionDataTask* task =
                [[NSURLSession sharedSession] dataTaskWithRequest:req
                                            completionHandler:^(NSData* data, NSURLResponse* resp, NSError* err) {
                if (err) {
                    NSLog(@"[recon] upload error: %@", err);
                } else {
                    NSLog(@"[recon] upload done — status %ld", (long)[(NSHTTPURLResponse*)resp statusCode]);
                }
                dispatch_semaphore_signal(sem);
            }];
            [task resume];
            dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_SEC)));
        }
    }
}

__attribute__((constructor))
static void recon_entry(void) {
    @autoreleasepool {
        NSLog(@"[recon] loaded into %@", [[NSBundle mainBundle] bundleIdentifier]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            dumpEverything();
        });
    }
}
