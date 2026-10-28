//
//  ImageStore.h
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/15.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

/*
 图片本地存取工具
 把从「文件」App 导入的图片复制到 Documents/Images 目录，并提供列表与缩略图读取
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ImageStore : NSObject

/// Documents/Images 目录(不存在会自动创建)
+ (NSString *)imagesDirectory;

/// 目录下所有图片的本地绝对路径(按文件名升序)
+ (NSArray<NSString *> *)allImagePaths;

/// Documents/Images 下所有子文件夹名(升序,不含隐藏项)
+ (NSArray<NSString *> *)imageSubfolderNames;

/// 子文件夹完整路径(不存在会自动创建)
+ (NSString *)subfolderPath:(NSString *)name;

/// 创建子文件夹,返回是否成功(已存在视为成功)
+ (BOOL)createSubfolder:(NSString *)name;

/// 指定子文件夹下的所有图片路径(升序)
+ (NSArray<NSString *> *)imagePathsInSubfolder:(NSString *)name;

/// 按扩展名判断文件名是否为图片(jpg/jpeg/png/gif/heic/heif/webp/bmp/tiff/tif)
+ (BOOL)isImageName:(NSString *)name;

/// 把外部选中的图片复制到 Images 目录，返回复制后的本地路径；失败返回 nil
+ (nullable NSString *)saveImageFromURL:(NSURL *)url error:(NSError **)error;

/// 把外部选中的图片复制到指定目录,返回复制后的本地路径;失败返回 nil
+ (nullable NSString *)saveImageFromURL:(NSURL *)url intoDirectory:(NSString *)dir error:(NSError **)error;

/// 删除指定图片文件,返回是否成功(不存在视为成功)
+ (BOOL)deleteImageAtPath:(NSString *)path;

/// 删除指定相册文件夹(含其中所有图片),返回是否成功
+ (BOOL)deleteSubfolder:(NSString *)name;

/// 读取缩略图(用于列表，避免直接加载原图爆内存)，maxPixel 为最长边像素
+ (nullable UIImage *)thumbnailForPath:(NSString *)path maxPixel:(CGFloat)maxPixel;

@end

NS_ASSUME_NONNULL_END