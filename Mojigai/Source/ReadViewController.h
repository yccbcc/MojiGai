//
//  ReadViewController.h
//  MojiGai
//
//  Created by zhaohongbin on 2023/8/25.
//  Copyright © 2023 zhaohongbin. All rights reserved.
//

/*
 阅读器页
 翻页式展示已保存的文本条目(按 row 索引定位);支持翻页/滚动两种模式,底部工具栏可调字号/主题,滑块跳转阅读进度
 */
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ReadViewController : UIPageViewController<UIPageViewControllerDelegate,UIPageViewControllerDataSource>

/// 对应 Source 数据列表中条目的下标
@property (nonatomic, assign) int row;

@end

NS_ASSUME_NONNULL_END
