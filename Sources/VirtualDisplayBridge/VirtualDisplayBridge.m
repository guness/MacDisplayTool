#import "VirtualDisplayBridge.h"

// Private CoreGraphics API, resolved at runtime so missing classes fail cleanly.
// API references: Stengo/DeskPad and Chromium's virtual_display_mac_util.mm.
@interface CGVirtualDisplayDescriptor : NSObject
@property(nonatomic, retain) dispatch_queue_t queue;
@property(nonatomic, retain) NSString *name;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int vendorID;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int serialNum;
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(double)rate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic, retain) NSArray *modes;
@property(nonatomic) unsigned int hiDPI;
@end

@interface CGVirtualDisplay : NSObject
@property(nonatomic, readonly) CGDirectDisplayID displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

@implementation MDTVirtualDisplay {
  CGVirtualDisplay *_display;
}

+ (instancetype)displayWithWidth:(NSUInteger)width height:(NSUInteger)height
                    refreshRate:(double)refreshRate name:(NSString *)name error:(NSError **)error {
  NSString *failure = nil;
  MDTVirtualDisplay *owner = nil;
  @try {
    Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");
    if (!descriptorClass || !modeClass || !settingsClass || !displayClass) {
      failure = @"This macOS version does not provide the private virtual display API.";
    } else {
      CGVirtualDisplayDescriptor *descriptor = [[descriptorClass alloc] init];
      descriptor.queue = dispatch_get_main_queue();
      descriptor.name = name;
      descriptor.maxPixelsWide = (unsigned int)width;
      descriptor.maxPixelsHigh = (unsigned int)height;
      descriptor.sizeInMillimeters = CGSizeMake(width * 25.4 / 96.0, height * 25.4 / 96.0);
      descriptor.vendorID = 0x4D44;
      descriptor.productID = 1;
      // Distinct identity for concurrent invocations.
      descriptor.serialNum = arc4random_uniform(UINT32_MAX - 1) + 1;
      CGVirtualDisplay *display = [[displayClass alloc] initWithDescriptor:descriptor];
      CGVirtualDisplayMode *mode = [[modeClass alloc] initWithWidth:width height:height refreshRate:refreshRate];
      CGVirtualDisplaySettings *settings = [[settingsClass alloc] init];
      settings.hiDPI = 0;
      settings.modes = mode ? @[mode] : @[];
      if (!display || !mode || ![display applySettings:settings] || display.displayID == 0) {
        failure = @"macOS rejected the custom virtual display. Try smaller dimensions or a lower refresh rate.";
      } else {
        owner = [[self alloc] init];
        owner->_display = display;
      }
    }
  } @catch (NSException *exception) {
    failure = [NSString stringWithFormat:@"The private virtual display API failed: %@", exception.reason];
  }
  if (!owner && error) {
    *error = [NSError errorWithDomain:@"MacDisplayTool.VirtualDisplay" code:1
                            userInfo:@{NSLocalizedDescriptionKey: failure ?: @"Unable to create a virtual display."}];
  }
  return owner;
}

- (CGDirectDisplayID)displayID { return _display.displayID; }
- (void)invalidate { _display = nil; }
@end
