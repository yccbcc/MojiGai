//
//  UIWindow+CurrentWindow.h
//  Mojigai
//
//  Created by zhaohongbin on 2026/10/26.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIWindow (CurrentWindow)

// UIScene 生命周期下 UIApplication.keyWindow/windows 已废弃,
// 从当前前台活跃的 UIWindowScene 中取 key window(取不到时回退首个窗口)
+ (UIWindow *)currentKeyWindow;

@end
