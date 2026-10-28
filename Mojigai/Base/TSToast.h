//
//  TSToast.h
//  Mojigai
//
//  Created by zhaohongbin on 2026/10/13.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

/*
 轻量提示工具
 在窗口底部弹出一条短暂提示(toast),全 app 通用
 */
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSToast : NSObject

/// 在窗口底部弹出一条提示，1.5 秒后淡出消失
+ (void)show:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
