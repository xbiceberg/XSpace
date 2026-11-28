//
//  MousecapeBridge.m
//  XSpace
//
//  为 Swift 设置页提供的精简接口；底层实现来自 Alex Zielenski 的 Mousecape。
//

#import "MousecapeBridge.h"
#import "apply.h"
#import "restore.h"
#import "MCPrefs.h"

@implementation MousecapeBridge

+ (BOOL)applyCapeAtPath:(NSString *)path {
    return applyCapeAtPath(path);
}

+ (void)resetCursors {
    resetAllCursors();
}

+ (NSString *)appliedCapeIdentifier {
    CFPropertyListRef value = CFPreferencesCopyValue(
        (CFStringRef)MCPreferencesAppliedCursorKey,
        (CFStringRef)kMCDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesCurrentHost
    );
    // 项目以 MRR 方式编译 Objective-C：CFPreferencesCopyValue 返回 +1，需手动释放
    NSString *identifier = value ? [(NSString *)value autorelease] : nil;
    return identifier ?: @"";
}

+ (BOOL)isLeftHanded {
    BOOL value = MCFlag(MCPreferencesHandednessKey);
    return value;
}

+ (void)setLeftHanded:(BOOL)enabled {
    MCSetDefaultFor(@(enabled), MCPreferencesHandednessKey,
                    (__bridge NSString *)kCFPreferencesCurrentUser,
                    (__bridge NSString *)kCFPreferencesCurrentHost);
    CFPreferencesAppSynchronize((CFStringRef)kMCDomain);
}

+ (NSString *)capesDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *support = paths.firstObject ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
    return [[support stringByAppendingPathComponent:@"Mousecape"] stringByAppendingPathComponent:@"capes"];
}

@end
