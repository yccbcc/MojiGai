//
//  SceneDelegate.m
//  MojiGai
//
//  Created by zhaohongbin on 2019/6/20.
//  Copyright © 2019 zhaohongbin. All rights reserved.
//

#import "SceneDelegate.h"
#import "AccessControlController.h"

@interface SceneDelegate ()

@end

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;

    // 每次打开 app 先进入门禁页,通过后再由 AccessControlController 切换根控制器到 MainController 主页
    self.window.rootViewController = [[AccessControlController alloc] init];
    [self.window makeKeyAndVisible];

    // 冷启动时通过分享进入的文件链接
    [self handleURLContexts:connectionOptions.URLContexts];
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    // 热启动(已在运行)时接收分享进来的文件
    [self handleURLContexts:URLContexts];
}

// 处理其它 App 通过"分享到 MojiGai"传入的本地文件链接
- (void)handleURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    for (UIOpenURLContext *ctx in URLContexts) {
        NSURL *url = ctx.URL;
        if (!url) {
            continue;
        }
        NSString *fileName = url.lastPathComponent; // 从路径中获得完整的文件名（带后缀）
        // path 是文件在本机的完整地址，类似这种格式：file:///private/var/mobile/Containers/Data/Application/83643509-E90E-40A6-92EA-47A44B40CBBF/Documents/jfkdfj123a.pdf
        // 旧系统（iOS 26 前）分享进来会先复制到 Documents/Inbox，现已改为直传文件原位置
        NSString *path = url.absoluteString; // 完整的url字符串
        // 文件名为中文时 URL 会带 %XX 编码,需还原;解码失败(非法转义)时保留原串
        NSString *decoded = [path stringByRemovingPercentEncoding];
        path = decoded ?: path;

        NSMutableString *string = [[NSMutableString alloc] initWithString:path];

        if ([path hasPrefix:@"file://"]) { // 通过前缀来判断是文件
            // 去除前缀得到本地路径：/private/var/mobile/Containers/Data/Application/83643509-E90E-40A6-92EA-47A44B40CBBF/Documents/jfkdfj123a.pdf
            [string replaceOccurrencesOfString:@"file://" withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, path.length)];

            // 此时获取到文件存储在本地的路径，就可以在自己需要使用的页面使用了
            NSDictionary *dict = @{@"fileName":fileName,
                                   @"filePath":string};
            [[NSNotificationCenter defaultCenter] postNotificationName:@"FileNotification" object:nil userInfo:dict];
        }
    }
}

@end
