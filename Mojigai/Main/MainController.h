//
//  MainController.h
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/15.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

/*
 分发主页
 分组列表提供 Editor/视频/相册/Source/Web 五个入口;Web 入口把全局网页视图单例挂到 window,长按 Web 行可重置销毁并清缓存
 */
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MainController : UITableViewController

@end

NS_ASSUME_NONNULL_END
