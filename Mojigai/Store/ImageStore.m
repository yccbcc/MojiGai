//
//  ImageStore.m
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/15.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import "ImageStore.h"
#import "FileTool.h"
#import <ImageIO/ImageIO.h>

// 图片扩展名集合(小写,供 FileTool 过滤/判定)
static NSArray<NSString *> *kImageExtensions(void) {
    static NSArray *exts;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        exts = @[@"jpg", @"jpeg", @"png", @"gif", @"heic", @"heif", @"webp", @"bmp", @"tiff", @"tif"];
    });
    return exts;
}

@implementation ImageStore

+ (NSString *)imagesDirectory {
    return [FileTool resolveChildPathInDocuments:@"Images" create:YES];
}

+ (NSArray<NSString *> *)allImagePaths {
    return [FileTool pathsInDirectory:[self imagesDirectory] matchingExtensions:kImageExtensions()];
}

+ (NSArray<NSString *> *)imageSubfolderNames {
    return [FileTool subdirectoryNamesInDirectory:[self imagesDirectory]];
}

+ (NSString *)subfolderPath:(NSString *)name {
    // 子文件夹落在 Images 目录下,而非 Documents 根
    NSString *full = [FileTool resolveChildPath:name inDirectory:[self imagesDirectory] create:YES];
    return full ?: [self imagesDirectory];
}

+ (BOOL)createSubfolder:(NSString *)name {
    NSString *full = [FileTool resolveChildPath:name inDirectory:[self imagesDirectory] create:NO];
    if (!full) return NO;
    if ([FileTool existsAtPath:full]) {
        // 同名路径已存在但不是目录(被文件占位)时创建不了
        if (![FileTool directoryExists:full]) {
            NSLog(@"创建相册文件夹失败: %@ 已被同名文件占用", name);
            return NO;
        }
        return YES;   // 已存在视为成功
    }
    NSError *error = nil;
    BOOL ok = [[NSFileManager defaultManager] createDirectoryAtPath:full withIntermediateDirectories:YES attributes:nil error:&error];
    if (!ok) {
        NSLog(@"创建相册文件夹失败: %@", error);
    }
    return ok;
}

+ (NSArray<NSString *> *)imagePathsInSubfolder:(NSString *)name {
    return [FileTool pathsInDirectory:[self subfolderPath:name] matchingExtensions:kImageExtensions()];
}

+ (BOOL)isImageName:(NSString *)name {
    return [FileTool name:name hasExtensionInSet:kImageExtensions()];
}

+ (BOOL)deleteImageAtPath:(NSString *)path {
    NSError *error = nil;
    BOOL ok = [FileTool deleteAtPath:path error:&error];
    if (!ok) {
        NSLog(@"删除图片失败: %@", error);
    }
    return ok;
}

+ (BOOL)deleteSubfolder:(NSString *)name {
    // resolveChildPath 内置防路径逃逸:名字带路径分隔符时返回 nil
    NSString *full = [FileTool resolveChildPath:name inDirectory:[self imagesDirectory] create:NO];
    if (!full) return NO;
    NSError *error = nil;
    BOOL ok = [FileTool deleteAtPath:full error:&error];
    if (!ok) {
        NSLog(@"删除相册失败: %@", error);
    }
    return ok;
}

+ (nullable NSString *)saveImageFromURL:(NSURL *)url error:(NSError **)error {
    return [self saveImageFromURL:url intoDirectory:[self imagesDirectory] error:error];
}

+ (nullable NSString *)saveImageFromURL:(NSURL *)url intoDirectory:(NSString *)dir error:(NSError **)error {
    return [FileTool copyFromURL:url intoDirectory:dir fallbackName:@"image.dat" error:error];
}

+ (nullable UIImage *)thumbnailForPath:(NSString *)path maxPixel:(CGFloat)maxPixel {
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) {
        return nil;
    }
    NSDictionary *options = @{
        (__bridge id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge id)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (__bridge id)kCGImageSourceThumbnailMaxPixelSize: @(maxPixel),
    };
    CGImageRef cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!cgImage) {
        return nil;
    }
    UIImage *image = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    return image;
}

@end