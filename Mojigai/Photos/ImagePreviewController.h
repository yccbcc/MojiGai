//
//  ImagePreviewController.h
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/15.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

/*
 图片全屏预览页(基于 YBImageBrowser)
 微信朋友圈式交互:双指/双击缩放、左右翻页、下拉关闭
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ImagePreviewController : UIViewController

/// 待预览的图片本地路径数组
@property (nonatomic, copy) NSArray<NSString *> *imagePaths;

/// 起始展示的下标
@property (nonatomic, assign) NSInteger index;

@end

NS_ASSUME_NONNULL_END