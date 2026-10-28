//
//  ConvertVideoFormat.h
//  Mojigai
//
//  Created by zhaohongbin on 2026/10/12.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

/*
 把 m3u8 视频（在线链接或本地路径）转换成 mp4 文件
 基于 FFmpegKit 异步转换，可查看进度、可取消
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^ConvertProgressBlock)(float progress);
typedef void (^ConvertCompletionBlock)(BOOL success, NSURL * _Nullable outputURL, NSString * _Nullable errorMessage);

@interface ConvertVideoFormat : NSObject

/// 将 m3u8 链接转换为 mp4 文件（异步）
/// @param m3u8URL   m3u8 的远程 URL 或本地路径
/// @param outputURL 输出 mp4 的本地文件 URL（建议放在 Documents 或 Caches 目录）
/// @param progressBlock 进度回调，progress 为 0.0 ~ 1.0
/// @param completionBlock 完成回调，success 为 YES 时 outputURL 有效
+ (void)convertM3U8ToMP4WithInputURL:(NSURL *)m3u8URL
                           outputURL:(NSURL *)outputURL
                            progress:(nullable ConvertProgressBlock)progressBlock
                          completion:(ConvertCompletionBlock)completionBlock;

/// 取消当前正在执行的转换任务
+ (void)cancelCurrentConversion;

@end

NS_ASSUME_NONNULL_END
