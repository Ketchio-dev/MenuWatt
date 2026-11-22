#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT BOOL MWMenuBarRuntimeAvailable(void);

/// A process-scoped macOS 27 visibility session. Invalidating it restores
/// the system's own layout; no system preferences are written.
@interface MWMenuBarVisibility : NSObject
- (nullable instancetype)initWithSystemItems:(NSArray<NSNumber *> *)systemItems
                          bundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers
                                 completion:(void (^)(NSError * _Nullable))completion;
- (void)invalidate;
@end

/// Carbon hotkeys do not require Accessibility or Input Monitoring permission.
@interface MWMenuBarHotKeys : NSObject
- (nullable instancetype)initWithHandler:(void (^)(NSUInteger action))handler;
@end

NS_ASSUME_NONNULL_END
