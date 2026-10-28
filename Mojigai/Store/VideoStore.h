//
//  VideoStore.h
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/16.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

/*
 视频本地存取工具
 把 m3u8 转换后的视频保存到 Documents/videos/<文件夹> 目录,并提供文件夹/视频列表与删除
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface VideoStore : NSObject

/// Documents/videos 目录(不存在会自动创建)
+ (NSString *)videosDirectory;

/// 确保存在 default 文件夹,返回其路径
+ (NSString *)ensureDefaultFolder;

/// 子文件夹名列表(保证 default 排在最前)
+ (NSArray<NSString *> *)folderNames;

/// 子文件夹完整路径(不存在会自动创建)
+ (NSString *)folderPath:(NSString *)name;

/// 创建子文件夹,返回是否成功(已存在视为成功)
+ (BOOL)createFolder:(NSString *)name;

/// 指定子文件夹下的所有视频路径(升序)
+ (NSArray<NSString *> *)videoPathsInFolder:(NSString *)name;

/// 是否视频文件
+ (BOOL)isVideoName:(NSString *)name;

/// 把外部选中的视频复制到指定目录,返回复制后的本地路径;失败返回 nil
+ (nullable NSString *)saveVideoFromURL:(NSURL *)url intoDirectory:(NSString *)dir error:(NSError **)error;

/// 删除指定视频文件,返回是否成功(不存在视为成功)
+ (BOOL)deleteVideoAtPath:(NSString *)path;

/// 删除指定视频文件夹(含其中所有视频),返回是否成功
+ (BOOL)deleteFolder:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
