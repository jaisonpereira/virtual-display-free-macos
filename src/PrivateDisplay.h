// Runtime declarations for undocumented CoreGraphics APIs. No private framework
// is linked. The implementation checks availability before sending messages.
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

@class CGVirtualDisplayDescriptor, CGVirtualDisplaySettings;
@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(double)rate;
@end
@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic) unsigned int hiDPI;
@property(nonatomic, strong) NSArray *modes;
@end
@interface CGVirtualDisplayDescriptor : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic) unsigned int maxPixelsWide, maxPixelsHigh;
@property(nonatomic) unsigned int vendorID, productID, serialNum;
@property(nonatomic) CGSize sizeInMillimeters;
- (void)setDispatchQueue:(dispatch_queue_t)queue;
- (void)setQueue:(dispatch_queue_t)queue;
@end
@interface CGVirtualDisplay : NSObject
@property(nonatomic, readonly) CGDirectDisplayID displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end
