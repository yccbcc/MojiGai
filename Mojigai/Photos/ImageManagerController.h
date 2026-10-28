//
//  ImageManagerController.h
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/15.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

/*
 图片管理页
 顶部可从「文件」App 多选导入图片，下方以网格列表展示，点击可全屏预览
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ImageManagerController : UIViewController

/// 指定子文件夹名(可选)。nil/空 = 查看 Images 下全部图片;非空 = 只看该文件夹
@property (nonatomic, copy, nullable) NSString *subfolderName;

@end

NS_ASSUME_NONNULL_END