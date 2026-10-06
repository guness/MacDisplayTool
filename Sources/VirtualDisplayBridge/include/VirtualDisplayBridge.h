#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// Owns the private macOS virtual display for the lifetime of this object.
@interface MDTVirtualDisplay : NSObject
@property(nonatomic, readonly) CGDirectDisplayID displayID;
+ (nullable instancetype)displayWithWidth:(NSUInteger)width
                                  height:(NSUInteger)height
                             refreshRate:(double)refreshRate
                                    name:(NSString *)name
                                   error:(NSError **)error
    NS_SWIFT_NAME(create(width:height:refreshRate:name:));
- (void)invalidate;
@end

NS_ASSUME_NONNULL_END
