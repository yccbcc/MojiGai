//
//  VideoDownloadTool.h
//  Mojigai
//
//  Created by zhaohongbin on 2026-10-22.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

/*
 视频下载工具:把「地址栏下载」和「顶部下载列表」里的下载逻辑集中到一处。
 - m3u8:借助 FFmpegKit 转成 mp4 再落库(进度为估算值)
 - mp4 :直接取回成品视频再落库(进度为真实字节比)
 下载结果统一保存到 Documents/videos/<文件夹>,进度 / 完成回调均在主线程。
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 从网址判断的视频类型。None 表示不是可下载视频。
typedef NS_ENUM(NSInteger, VideoURLType) {
    VideoURLTypeNone = 0,
    VideoURLTypeM3U8 = 1,
    VideoURLTypeMP4  = 2,
};

/// 进度回调,progress 为 0.0 ~ 1.0(主线程)
typedef void (^VideoDownloadProgressBlock)(float progress);

/// 完成回调,success 为 YES 时 savedPath 为落库后的本地路径(主线程)
typedef void (^VideoDownloadCompletionBlock)(BOOL success, NSString * _Nullable savedPath, NSString * _Nullable errorMessage);

@interface VideoDownloadTool : NSObject

/// 判断网址是不是可下载视频、以及类型(宽松匹配 .m3u8 / .m3u / .mp4,可覆盖带 query 的地址)
+ (VideoURLType)videoTypeForURLString:(NSString *)urlString;

/// 下载 m3u8:转成 mp4 后保存到 Documents/videos/<folderName>
- (void)downloadM3U8:(NSString *)m3u8URL
        targetFolder:(NSString *)folderName
            progress:(nullable VideoDownloadProgressBlock)progressBlock
          completion:(nullable VideoDownloadCompletionBlock)completionBlock;

/// 下载 mp4:直接取回成品视频保存到 Documents/videos/<folderName>
- (void)downloadMP4:(NSString *)mp4URL
       targetFolder:(NSString *)folderName
           progress:(nullable VideoDownloadProgressBlock)progressBlock
         completion:(nullable VideoDownloadCompletionBlock)completionBlock;

/// 取消当前进行中的下载
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
