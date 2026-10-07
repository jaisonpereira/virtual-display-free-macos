#import <Foundation/Foundation.h>

typedef struct {
    uint32_t width, height, mirror;
    BOOL headless, list, help, version;
    double duration;
} VDFOptions;

BOOL VDFParseOptions(int argc, const char *argv[], VDFOptions *options, NSString **error);
