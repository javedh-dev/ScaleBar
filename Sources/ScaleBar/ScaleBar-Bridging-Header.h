// Private macOS APIs (no public headers). Virtual displays live in CoreGraphics, DDC/CI in IOKit.
// Same declarations DeskPad / m1ddc / MonitorControl use. A macOS update can change them, so everything is
// weak-imported: if Apple removes one, the app still launches and reports the feature as unsupported.
#define WEAK __attribute__((weak_import))
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/IOKitLib.h>

@class CGVirtualDisplay;

WEAK @interface CGVirtualDisplayDescriptor : NSObject
@property (retain, nonatomic) NSString *name;
@property (nonatomic) unsigned int maxPixelsWide, maxPixelsHigh, vendorID, productID, serialNum;
@property (nonatomic) CGSize sizeInMillimeters;
@property (copy, nonatomic) void (^terminationHandler)(id, CGVirtualDisplay *);
- (void)setDispatchQueue:(dispatch_queue_t)queue;
@end

WEAK @interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(CGFloat)refreshRate;
@end

WEAK @interface CGVirtualDisplaySettings : NSObject
@property (retain, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;
@property (nonatomic) unsigned int hiDPI;
@end

WEAK @interface CGVirtualDisplay : NSObject
@property (readonly, nonatomic) CGDirectDisplayID displayID;
- (nullable instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

typedef CFTypeRef IOAVServiceRef;
WEAK IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service) CF_RETURNS_RETAINED;
WEAK IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t offset, void *buffer, uint32_t size);
WEAK IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t dataAddress, void *buffer, uint32_t size);
