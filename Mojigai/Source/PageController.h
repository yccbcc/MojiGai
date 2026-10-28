//
//  PageController.h
//  MojiGai
//
//  Created by zhaohongbin on 2023/8/25.
//  Copyright © 2023 zhaohongbin. All rights reserved.
//

/*
 阅读单页控制器
 展示分页后的单页正文,承载字号/主题色等阅读样式;滚动事件转发给阅读器联动滑块
 */
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PageController : UIViewController

@property (nonatomic, strong) UITextView *readTXTView;
@property (nonatomic, strong) NSString *content;
@property (nonatomic, assign) int index;

/// 滚动事件转发目标(由阅读器设置,用于滑块跟随滚动)
@property (nonatomic, weak) id<UIScrollViewDelegate> scrollDelegate;

/// 字号(由阅读器统一设置)
@property (nonatomic, assign) CGFloat fontSize;
/// 背景色
@property (nonatomic, strong) UIColor *readerBgColor;
/// 文字色
@property (nonatomic, strong) UIColor *readerTextColor;

/// 应用当前样式(字号/主题变更后调用)
- (void)applyStyle;

@end

NS_ASSUME_NONNULL_END
