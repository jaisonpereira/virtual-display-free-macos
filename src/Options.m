#import "Options.h"
#include <errno.h>
#include <stdlib.h>
#include <string.h>

static BOOL parseInteger(const char *text, uint32_t min, uint32_t max, uint32_t *value) {
    if (!text || !*text) return NO;
    for (const char *p = text; *p; p++) if (*p < '0' || *p > '9') return NO;
    errno = 0;
    char *end;
    unsigned long long number = strtoull(text, &end, 10);
    if (errno || *end || number < min || number > max) return NO;
    *value = (uint32_t)number;
    return YES;
}

BOOL VDFParseOptions(int argc, const char *argv[], VDFOptions *options, NSString **error) {
    *options = (VDFOptions){.width = 1920, .height = 1080};
    for (int i = 1; i < argc; i++) {
        const char *arg = argv[i];
        if (!strcmp(arg, "--help") || !strcmp(arg, "-h")) options->help = YES;
        else if (!strcmp(arg, "--version")) options->version = YES;
        else if (!strcmp(arg, "--list-displays")) options->list = YES;
        else if (!strcmp(arg, "--headless")) options->headless = YES;
        else if (!strcmp(arg, "--width") || !strcmp(arg, "--height") ||
                 !strcmp(arg, "--mirror") || !strcmp(arg, "--duration")) {
            uint32_t number = 0;
            uint32_t min = !strcmp(arg, "--mirror") || !strcmp(arg, "--duration") ? 1 : 640;
            uint32_t max = !strcmp(arg, "--mirror") ? UINT32_MAX :
                           !strcmp(arg, "--duration") ? 60 : 4096;
            if (++i >= argc || !parseInteger(argv[i], min, max, &number)) {
                if (error) *error = [NSString stringWithFormat:@"Valor inválido para %s (%u a %u).", arg, min, max];
                return NO;
            }
            if (!strcmp(arg, "--width")) options->width = number;
            else if (!strcmp(arg, "--height")) options->height = number;
            else if (!strcmp(arg, "--mirror")) options->mirror = number;
            else options->duration = number;
        } else {
            if (error) *error = [NSString stringWithFormat:@"Argumento desconhecido: %s", arg];
            return NO;
        }
    }
    if (options->duration && !options->headless) {
        if (error) *error = @"--duration exige --headless.";
        return NO;
    }
    return YES;
}
