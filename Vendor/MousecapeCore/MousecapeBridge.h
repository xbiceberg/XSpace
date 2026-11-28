//
//  MousecapeBridge.h
//  XSpace
//
//  为 Swift 设置页提供的精简接口；底层实现来自 Alex Zielenski 的 Mousecape。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MousecapeBridge : NSObject

/// 应用一个 .cape 光标主题文件
+ (BOOL)applyCapeAtPath:(NSString *)path;
/// 直接应用内存中的 .cape 字典（用于 VNC 静态光标等运行时变换）
+ (BOOL)applyCapeDictionary:(NSDictionary *)cape;
/// 恢复 macOS 系统默认光标
+ (void)resetCursors;
/// 当前已应用的主题 Identifier（Mousecape 偏好域）
+ (NSString *)appliedCapeIdentifier;
/// 左手模式：鼠标光标水平镜像
+ (BOOL)isLeftHanded;
+ (void)setLeftHanded:(BOOL)enabled;
/// 兼容 Mousecape 的主题目录：~/Library/Application Support/Mousecape/capes
+ (NSString *)capesDirectory;

@end

NS_ASSUME_NONNULL_END
