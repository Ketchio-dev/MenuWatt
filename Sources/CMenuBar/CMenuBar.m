#import "CMenuBar.h"
#import <Carbon/Carbon.h>
#import <dlfcn.h>
#import <objc/message.h>

static void completeOnMain(void (^completion)(NSError *), NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
}

static Class configurationClass(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_LAZY);
    });
    return NSClassFromString(@"MBAssessmentModeConfiguration");
}

BOOL MWMenuBarRuntimeAvailable(void) {
    Class configuration = configurationClass();
    Class assertion = NSClassFromString(@"MBAssessmentModeAssertion");
    return [configuration instancesRespondToSelector:NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:")]
        && [assertion instancesRespondToSelector:NSSelectorFromString(@"activateWithConfiguration:completionHandler:")]
        && [assertion instancesRespondToSelector:NSSelectorFromString(@"invalidate")];
}

@implementation MWMenuBarVisibility {
    id _assertion;
}

- (instancetype)initWithSystemItems:(NSArray<NSNumber *> *)systemItems
                 bundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers
                        completion:(void (^)(NSError *))completion {
    self = [super init];
    if (!self || !MWMenuBarRuntimeAvailable()) return nil;
    @try {
        Class type = configurationClass();
        SEL initializer = NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:");
        id configuration = ((id (*)(id, SEL, id, id))objc_msgSend)([type alloc], initializer, systemItems, bundleIdentifiers);
        if (!configuration) return nil;
        _assertion = [[NSClassFromString(@"MBAssessmentModeAssertion") alloc] init];
        if (!_assertion) return nil;
        SEL activation = NSSelectorFromString(@"activateWithConfiguration:completionHandler:");
        // The private API replies on its XPC queue. Swift UI closures inherit
        // MainActor isolation, so cross the queue boundary before calling one.
        void (^mainCompletion)(NSError *) = ^(NSError *error) {
            completeOnMain(completion, error);
        };
        ((void (*)(id, SEL, id, id))objc_msgSend)(_assertion, activation, configuration, mainCompletion);
        return self;
    } @catch (NSException *exception) {
        [self invalidate];
        completeOnMain(completion, [NSError errorWithDomain:@"MenuWatt.MenuBar" code:1 userInfo:@{
            NSLocalizedDescriptionKey: exception.reason ?: @"The menu bar could not be updated."
        }]);
        return nil;
    }
}

- (void)invalidate {
    if (!_assertion) return;
    id retiring = _assertion;
    _assertion = nil;
    @try {
        ((void (*)(id, SEL))objc_msgSend)(retiring, NSSelectorFromString(@"invalidate"));
    } @catch (NSException *exception) {
        NSLog(@"MenuWatt: restoring menu bar: %@", exception.reason);
    }
}

- (void)dealloc {
    [self invalidate];
}
@end

@interface MWMenuBarHotKeys ()
@property (copy) void (^handler)(NSUInteger);
@end

static OSStatus handleMenuBarHotKey(EventHandlerCallRef next, EventRef event, void *context) {
    EventHotKeyID identifier = {0};
    OSStatus result = GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL,
                                      sizeof(identifier), NULL, &identifier);
    if (result != noErr || identifier.signature != 'MWMB') return eventNotHandledErr;
    MWMenuBarHotKeys *owner = (__bridge MWMenuBarHotKeys *)context;
    void (^callback)(NSUInteger) = owner.handler;
    if (callback) {
        NSUInteger action = identifier.id;
        dispatch_async(dispatch_get_main_queue(), ^{ callback(action); });
    }
    return noErr;
}

@implementation MWMenuBarHotKeys {
    EventHandlerRef _eventHandler;
    EventHotKeyRef _toggle;
    EventHotKeyRef _restore;
}
- (instancetype)initWithHandler:(void (^)(NSUInteger))handler {
    self = [super init];
    if (!self) return nil;
    self.handler = handler;
    EventTypeSpec type = { kEventClassKeyboard, kEventHotKeyPressed };
    EventTargetRef target = GetEventDispatcherTarget();
    if (InstallEventHandler(target, handleMenuBarHotKey, 1, &type,
                            (__bridge void *)self, &_eventHandler) != noErr) return nil;
    UInt32 modifiers = controlKey | optionKey | cmdKey;
    EventHotKeyID toggleID = { 'MWMB', 1 }, restoreID = { 'MWMB', 2 };
    if (RegisterEventHotKey(kVK_ANSI_M, modifiers, toggleID, target, 0, &_toggle) != noErr
        || RegisterEventHotKey(kVK_ANSI_R, modifiers, restoreID, target, 0, &_restore) != noErr) {
        return nil;
    }
    return self;
}
- (void)dealloc {
    if (_toggle) UnregisterEventHotKey(_toggle);
    if (_restore) UnregisterEventHotKey(_restore);
    if (_eventHandler) RemoveEventHandler(_eventHandler);
}
@end
