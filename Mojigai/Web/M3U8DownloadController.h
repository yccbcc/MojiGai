//
//  M3U8DownloadController.h
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/21.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// m3u8 下载选择页:列表展示候选地址,每行 = 标题(URL) + 缩略图占位 + 下载按钮。
/// 点「下载」后弹文件夹选择,确认后回调开始下载并关闭本页。
/// 由调用方包一层 UINavigationController present 出来。
@interface M3U8DownloadController : UIViewController

/// 候选 m3u8 地址列表
@property (nonatomic, strong) NSArray<NSString *> *m3u8Urls;

/// url -> 来源标识 NSNumber(1=XHR/fetch, 2=媒体元素, 3=HTML解析);用于 cell 展示来源
@property (nonatomic, strong, nullable) NSDictionary<NSString *, NSNumber *> *sourceDict;

/// 确认下载后回调(参数: m3u8 地址, 目标文件夹名),调用方负责真正开始转换
@property (nonatomic, copy, nullable) void (^onStartDownload)(NSString *m3u8URL, NSString *folderName);

@end

NS_ASSUME_NONNULL_END
