#import "PrivateDisplay.h"
#import "Options.h"
#include <signal.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>

static const uint32_t VDFVendor = 0xF0F0, VDFProduct = 0x5644;
static NSString *const AppName = @"virtual-display-free-macos";
static int exitStatus = 0;

static NSArray<NSNumber *> *onlineDisplays(void) {
    CGDirectDisplayID ids[64]; uint32_t count = 0;
    if (CGGetOnlineDisplayList(64, ids, &count) != kCGErrorSuccess) return @[];
    NSMutableArray *result = [NSMutableArray array];
    for (uint32_t i = 0; i < count; i++) [result addObject:@(ids[i])];
    return result;
}

static NSString *displayName(CGDirectDisplayID display) {
    for (NSScreen *screen in NSScreen.screens)
        if ([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == display)
            return screen.localizedName;
    return [NSString stringWithFormat:@"Monitor %u", display];
}

static void printDisplays(void) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSNumber *number in onlineDisplays()) {
        CGDirectDisplayID display = number.unsignedIntValue;
        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(display);
        CGRect bounds = CGDisplayBounds(display);
        [result addObject:@{@"id": number, @"name": displayName(display),
            @"builtIn": @(CGDisplayIsBuiltin(display) != 0),
            @"main": @(CGDisplayIsMain(display) != 0),
            @"x": @(bounds.origin.x), @"y": @(bounds.origin.y),
            @"vendor": @(CGDisplayVendorNumber(display)),
            @"product": @(CGDisplayModelNumber(display)),
            @"width": @(mode ? CGDisplayModeGetWidth(mode) : 0),
            @"height": @(mode ? CGDisplayModeGetHeight(mode) : 0),
            @"refreshRate": @(mode ? CGDisplayModeGetRefreshRate(mode) : 0),
            @"mirrorOf": @(CGDisplayMirrorsDisplay(display))}];
        if (mode) CGDisplayModeRelease(mode);
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
    puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
}

@interface DisplaySession : NSObject {
    CGDisplayModeRef _originalMode;
    CGPoint _originalOrigin;
}
@property(nonatomic, strong) CGVirtualDisplay *virtualDisplay;
@property(nonatomic) CGDirectDisplayID target;
- (BOOL)startWidth:(uint32_t)width height:(uint32_t)height mirror:(CGDirectDisplayID)target error:(NSString **)error;
- (BOOL)stop:(NSString **)error;
@end

@implementation DisplaySession
- (BOOL)startWidth:(uint32_t)width height:(uint32_t)height mirror:(CGDirectDisplayID)target error:(NSString **)error {
    if (self.virtualDisplay) { *error = @"A tela virtual já está ativa."; return NO; }
    if (target && (![onlineDisplays() containsObject:@(target)] || CGDisplayIsBuiltin(target) ||
                   CGDisplayIsInMirrorSet(target) || CGDisplayVendorNumber(target) == VDFVendor)) {
        *error = @"Escolha um monitor externo conectado que não esteja espelhado."; return NO;
    }
    Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");
    Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    if (!descriptorClass || !settingsClass ||
        ![displayClass instancesRespondToSelector:@selector(initWithDescriptor:)] ||
        ![displayClass instancesRespondToSelector:@selector(applySettings:)] ||
        ![modeClass instancesRespondToSelector:@selector(initWithWidth:height:refreshRate:)]) {
        *error = @"As APIs de tela virtual não estão disponíveis nesta versão do macOS."; return NO;
    }
    @try {
        CGVirtualDisplayDescriptor *descriptor = [[descriptorClass alloc] init];
        descriptor.name = @"Virtual Display Free";
        descriptor.vendorID = VDFVendor; descriptor.productID = VDFProduct;
        descriptor.serialNum = 0x5644464D;
        descriptor.maxPixelsWide = width; descriptor.maxPixelsHigh = height;
        descriptor.sizeInMillimeters = CGSizeMake(width * 25.4 / 96, height * 25.4 / 96);
        if ([descriptor respondsToSelector:@selector(setDispatchQueue:)])
            [descriptor setDispatchQueue:dispatch_get_main_queue()];
        else if ([descriptor respondsToSelector:@selector(setQueue:)])
            [descriptor setQueue:dispatch_get_main_queue()];
        CGVirtualDisplayMode *mode = [[modeClass alloc] initWithWidth:width height:height refreshRate:60];
        CGVirtualDisplaySettings *settings = [[settingsClass alloc] init];
        if (!mode || !settings) { *error = @"Falha ao criar o modo virtual."; return NO; }
        settings.hiDPI = 0; settings.modes = @[mode];
        self.virtualDisplay = [[displayClass alloc] initWithDescriptor:descriptor];
        if (!self.virtualDisplay || ![self.virtualDisplay applySettings:settings]) {
            self.virtualDisplay = nil; *error = @"O macOS recusou a criação da tela virtual."; return NO;
        }
    } @catch (NSException *exception) {
        self.virtualDisplay = nil;
        *error = [NSString stringWithFormat:@"API de tela virtual incompatível: %@", exception.reason]; return NO;
    }
    CGDirectDisplayID virtualID = self.virtualDisplay.displayID;
    // Registration is asynchronous; do not configure a nonexistent display ID.
    BOOL ready = NO;
    for (int i = 0; i < 60; i++) {
        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(virtualID);
        ready = CGDisplayIsOnline(virtualID) && mode && CGDisplayModeGetWidth(mode) == width && CGDisplayModeGetHeight(mode) == height;
        if (mode) CGDisplayModeRelease(mode);
        if (ready) break;
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    if (!ready) { [self stop:nil]; *error = @"A tela virtual não ficou disponível no prazo esperado."; return NO; }
    if (target) {
        _originalMode = CGDisplayCopyDisplayMode(target);
        _originalOrigin = CGDisplayBounds(target).origin;
        CGDisplayConfigRef config = NULL;
        CGError result = CGBeginDisplayConfiguration(&config);
        if (result == kCGErrorSuccess) {
            result = CGConfigureDisplayOrigin(config, virtualID, (int32_t)_originalOrigin.x, (int32_t)_originalOrigin.y);
            if (result == kCGErrorSuccess) result = CGConfigureDisplayMirrorOfDisplay(config, target, virtualID);
            if (result == kCGErrorSuccess) result = CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
            else CGCancelDisplayConfiguration(config);
        }
        if (result != kCGErrorSuccess) {
            [self stop:nil]; *error = [NSString stringWithFormat:@"Falha ao espelhar o monitor (CoreGraphics %d).", result]; return NO;
        }
        self.target = target;
        BOOL mirrored = NO;
        for (int i = 0; i < 40; i++) {
            mirrored = CGDisplayMirrorsDisplay(target) == virtualID;
            if (mirrored) break;
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        if (!mirrored) { [self stop:nil]; *error = @"O macOS não confirmou o espelhamento solicitado."; return NO; }
    }
    printf("Tela virtual ativa: %ux%u @ 60 Hz; ID=%u; destino=%u\n", width, height, virtualID, target);
    fflush(stdout);
    return YES;
}
- (BOOL)stop:(NSString **)error {
    BOOL restored = YES;
    // Restore only the mirror relation owned by this instance. Respect external changes.
    if (self.target && self.virtualDisplay && CGDisplayIsOnline(self.target) &&
        CGDisplayMirrorsDisplay(self.target) == self.virtualDisplay.displayID) {
        CGDisplayConfigRef config = NULL;
        CGError result = CGBeginDisplayConfiguration(&config);
        if (result == kCGErrorSuccess) {
            result = CGConfigureDisplayMirrorOfDisplay(config, self.target, kCGNullDirectDisplay);
            if (result == kCGErrorSuccess && _originalMode)
                result = CGConfigureDisplayWithDisplayMode(config, self.target, _originalMode, NULL);
            if (result == kCGErrorSuccess)
                result = CGConfigureDisplayOrigin(config, self.target, (int32_t)_originalOrigin.x, (int32_t)_originalOrigin.y);
            if (result == kCGErrorSuccess) result = CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
            else CGCancelDisplayConfiguration(config);
        }
        restored = result == kCGErrorSuccess;
        if (!restored && error) *error = [NSString stringWithFormat:@"Falha na restauração explícita (CoreGraphics %d). A tela virtual foi removida.", result];
    }
    self.virtualDisplay = nil; self.target = 0;
    if (_originalMode) { CGDisplayModeRelease(_originalMode); _originalMode = NULL; }
    return restored;
}
- (void)dealloc { [self stop:nil]; }
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic) VDFOptions options;
@property(nonatomic, strong) DisplaySession *session;
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSPopUpButton *targets;
@property(nonatomic, strong) NSTextField *widthField, *heightField, *message;
@property(nonatomic, strong) NSButton *startButton, *stopButton;
@property(nonatomic, strong) NSMutableArray *signalSources;
@end

@implementation AppDelegate
- (NSTextField *)label:(NSString *)text frame:(NSRect)frame {
    NSTextField *label = [NSTextField labelWithString:text]; label.frame = frame;
    [self.window.contentView addSubview:label]; return label;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.session = [DisplaySession new];
    self.signalSources = [NSMutableArray array];
    for (NSNumber *number in @[@(SIGINT), @(SIGTERM)]) {
        int sig = number.intValue; signal(sig, SIG_IGN);
        dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, sig, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(source, ^{ [NSApp terminate:nil]; });
        dispatch_resume(source); [self.signalSources addObject:source];
    }
    if (self.options.headless) {
        NSString *error = nil;
        if (![self.session startWidth:self.options.width height:self.options.height mirror:self.options.mirror error:&error]) {
            fprintf(stderr, "%s\n", error.UTF8String); exitStatus = 1; [NSApp terminate:nil]; return;
        }
        if (self.options.duration) [NSTimer scheduledTimerWithTimeInterval:self.options.duration repeats:NO block:^(NSTimer *timer) {
            (void)timer; [NSApp terminate:nil];
        }];
        return;
    }
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,540,355)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title = AppName; self.window.releasedWhenClosed = NO;
    [self.window center];
    NSTextField *title = [self label:@"Mais espaço no seu monitor" frame:NSMakeRect(24,299,492,28)];
    title.font = [NSFont boldSystemFontOfSize:22];
    [self label:@"Crie uma tela virtual e espelhe-a em um monitor externo." frame:NSMakeRect(24,265,492,28)];
    [self label:@"Monitor de destino" frame:NSMakeRect(24,226,492,22)];
    self.targets = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(22,188,496,32) pullsDown:NO];
    [self.targets addItemWithTitle:@"Sem espelhamento — somente tela virtual"];
    self.targets.lastItem.representedObject = @0;
    for (NSNumber *number in onlineDisplays()) {
        CGDirectDisplayID display = number.unsignedIntValue;
        if (CGDisplayIsBuiltin(display) || CGDisplayVendorNumber(display) == VDFVendor) continue;
        [self.targets addItemWithTitle:[NSString stringWithFormat:@"%@ (ID %u)",displayName(display),display]];
        self.targets.lastItem.representedObject = number;
    }
    if (self.targets.numberOfItems == 2) [self.targets selectItemAtIndex:1];
    [self.window.contentView addSubview:self.targets];
    [self label:@"Resolução virtual a 60 Hz" frame:NSMakeRect(24,156,492,22)];
    self.widthField = [[NSTextField alloc] initWithFrame:NSMakeRect(24,117,110,30)];
    self.heightField = [[NSTextField alloc] initWithFrame:NSMakeRect(165,117,110,30)];
    self.widthField.stringValue = [NSString stringWithFormat:@"%u",self.options.width];
    self.heightField.stringValue = [NSString stringWithFormat:@"%u",self.options.height];
    [self.widthField setAccessibilityLabel:@"Largura virtual"];
    [self.heightField setAccessibilityLabel:@"Altura virtual"];
    [self.window.contentView addSubview:self.widthField]; [self.window.contentView addSubview:self.heightField];
    [self label:@"×" frame:NSMakeRect(143,121,20,22)];
    self.startButton = [NSButton buttonWithTitle:@"Ativar" target:self action:@selector(start:)];
    self.startButton.frame = NSMakeRect(298,117,90,32);
    self.stopButton = [NSButton buttonWithTitle:@"Restaurar" target:self action:@selector(stop:)];
    self.stopButton.frame = NSMakeRect(392,117,124,32); self.stopButton.enabled = NO;
    [self.window.contentView addSubview:self.startButton]; [self.window.contentView addSubview:self.stopButton];
    self.message = [self label:@"Pronto. Ao sair, a tela virtual será removida." frame:NSMakeRect(24,53,492,50)];
    self.message.maximumNumberOfLines = 3;
    NSTextField *footnote = [self label:@"Gratuito • Sem avaliação • O painel físico mantém seus pixels" frame:NSMakeRect(24,18,492,22)];
    footnote.font = [NSFont systemFontOfSize:11]; footnote.textColor = NSColor.secondaryLabelColor;
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"VD";
    NSMenu *menu = [NSMenu new]; menu.autoenablesItems = NO;
    for (NSArray *entry in @[@[@"Abrir configurações",NSStringFromSelector(@selector(show:))],
        @[@"Restaurar monitor",NSStringFromSelector(@selector(stop:))],
        @[@"Sair",NSStringFromSelector(@selector(quit:))]]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:@""];
        item.target = self; [menu addItem:item];
    }
    self.statusItem.menu = menu;
    NSMenu *main = [NSMenu new], *app = [NSMenu new];
    NSMenuItem *top = [NSMenuItem new]; top.submenu = app; [main addItem:top];
    [app addItemWithTitle:@"Sair" action:@selector(terminate:) keyEquivalent:@"q"];
    NSApp.mainMenu = main;
    [self show:nil];
}
- (void)show:(id)sender { (void)sender; [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; }
- (void)quit:(id)sender { (void)sender; [NSApp terminate:nil]; }
- (void)start:(id)sender {
    (void)sender;
    const char *args[] = {"vdf", "--width", self.widthField.stringValue.UTF8String, "--height", self.heightField.stringValue.UTF8String};
    VDFOptions parsed; NSString *error = nil;
    if (!VDFParseOptions(5,args,&parsed,&error)) { self.message.stringValue = error; return; }
    uint32_t target = [self.targets.selectedItem.representedObject unsignedIntValue];
    if (![self.session startWidth:parsed.width height:parsed.height mirror:target error:&error]) {
        self.message.stringValue = error; return;
    }
    self.startButton.enabled = NO; self.stopButton.enabled = YES;
    self.widthField.enabled = NO; self.heightField.enabled = NO; self.targets.enabled = NO;
    self.statusItem.button.title = @"VD ●";
    self.message.stringValue = [NSString stringWithFormat:@"Ativa: %u × %u a 60 Hz%@. Use Restaurar para voltar.",parsed.width,parsed.height,target ? @", espelhada no monitor" : @""];
}
- (void)stop:(id)sender {
    (void)sender; NSString *error = nil;
    BOOL restored = [self.session stop:&error];
    self.startButton.enabled = YES; self.stopButton.enabled = NO;
    self.widthField.enabled = YES; self.heightField.enabled = YES; self.targets.enabled = YES;
    self.statusItem.button.title = @"VD";
    self.message.stringValue = restored ? @"Tela virtual removida. Monitor restaurado." : error;
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification; NSString *error = nil;
    if (![self.session stop:&error]) { fprintf(stderr,"%s\n",error.UTF8String); exitStatus = 1; }
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { (void)sender; return NO; }
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        VDFOptions options; NSString *error = nil;
        if (!VDFParseOptions(argc,argv,&options,&error)) { fprintf(stderr,"%s\n",error.UTF8String); return 2; }
        if (options.help) {
            puts("virtual-display-free-macos\n\nSem argumentos: abre o aplicativo.\n"
                 "--list-displays        Lista monitores em JSON, sem alterações.\n"
                 "--headless             Cria uma tela virtual sem interface.\n"
                 "--width N --height N   Resolução (640–4096 por dimensão; padrão 1920x1080).\n"
                 "--mirror ID            Espelha em um monitor externo (veja --list-displays).\n"
                 "--duration N           Encerra após 1–60 segundos; exige --headless.\n"
                 "--version              Mostra a versão.\n\nCtrl+C / SIGTERM remove a tela virtual e restaura o monitor."); return 0;
        }
        if (options.version) { puts("0.1.0"); return 0; }
        if (options.list) { printDisplays(); return 0; }
        NSString *lockPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"virtual-display-free-macos.lock"];
        int lock = open(lockPath.fileSystemRepresentation,O_CREAT|O_RDWR|O_CLOEXEC,0600);
        if (lock < 0 || flock(lock,LOCK_EX|LOCK_NB) != 0) {
            if (lock >= 0) close(lock);
            fprintf(stderr,"Já existe uma instância ativa, ou não foi possível reservar a sessão.\n"); return 1;
        }
        NSApplication *application = NSApplication.sharedApplication;
        [application setActivationPolicy:options.headless ? NSApplicationActivationPolicyProhibited : NSApplicationActivationPolicyRegular];
        AppDelegate *delegate = [AppDelegate new]; delegate.options = options; application.delegate = delegate;
        [application run];
        close(lock); return exitStatus;
    }
}
