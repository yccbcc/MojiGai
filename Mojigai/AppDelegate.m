//
//  AppDelegate.m
//  MojiGai
//
//  Created by zhaohongbin on 2019/6/20.
//  Copyright © 2019 zhaohongbin. All rights reserved.
//

#import "AppDelegate.h"
#import "UIWindow+CurrentWindow.h"

@interface AppDelegate ()

@end

@implementation AppDelegate

// UIApplicationDelegate 协议里带着预 scene 时代的可选 window 属性,此处只实现读取:
// 返回当前前台窗口供第三方库算安全区;不持有窗口,窗口仍由 SceneDelegate 管理
- (UIWindow *)window {
    return [UIWindow currentKeyWindow];
}


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 仅用于 App 级(非界面)初始化;窗口与根控制器创建已迁至 SceneDelegate。
    // 界面级前后台/激活回调由 SceneDelegate 的 scene:* 方法接手,此处不再保留空实现。
    return YES;
}


@end
