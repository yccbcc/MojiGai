//
//  UIWindow+CurrentWindow.m
//  Mojigai
//
//  Created by zhaohongbin on 2026/10/26.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import "UIWindow+CurrentWindow.h"

@implementation UIWindow (CurrentWindow)

+ (UIWindow *)currentKeyWindow {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState != UISceneActivationStateForegroundActive) {
            continue;
        }
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) { return w; }
            if (!window) { window = w; }
        }
    }
    return window;
}

@end
