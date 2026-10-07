#import "../src/Options.h"
#include <assert.h>

static void accepts(int argc, const char **argv, uint32_t width, uint32_t height) {
    VDFOptions options; NSString *error = nil;
    assert(VDFParseOptions(argc, argv, &options, &error));
    assert(options.width == width && options.height == height);
}
static void rejects(int argc, const char **argv) {
    VDFOptions options; NSString *error = nil;
    assert(!VDFParseOptions(argc, argv, &options, &error));
    assert(error.length > 0);
}
int main(void) {
    @autoreleasepool {
        const char *defaults[] = {"vdf"}; accepts(1,defaults,1920,1080);
        const char *qhd[] = {"vdf","--width","2560","--height","1440"}; accepts(5,qhd,2560,1440);
        const char *missing[] = {"vdf","--width"}; rejects(2,missing);
        const char *negative[] = {"vdf","--width","-1920"}; rejects(3,negative);
        const char *overflow[] = {"vdf","--mirror","4294967296"}; rejects(3,overflow);
        const char *large[] = {"vdf","--width","8192"}; rejects(3,large);
        const char *floatValue[] = {"vdf","--height","1080.5"}; rejects(3,floatValue);
        const char *junk[] = {"vdf","--height","1080abc"}; rejects(3,junk);
        const char *zero[] = {"vdf","--mirror","0"}; rejects(3,zero);
        const char *unknown[] = {"vdf","--random"}; rejects(2,unknown);
        const char *duration[] = {"vdf","--duration","3"}; rejects(3,duration);
        const char *valid[] = {"vdf","--headless","--mirror","42","--duration","2"};
        VDFOptions options; NSString *error = nil;
        assert(VDFParseOptions(6,valid,&options,&error));
        assert(options.headless && options.mirror == 42 && options.duration == 2);
        puts("12 testes de argumentos passaram.");
    }
}
