//
//  VideoStore.m
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/16.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import "VideoStore.h"
#import "FileTool.h"

// 视频扩展名集合(小写,供 FileTool 过滤/判定)
static NSArray<NSString *> *kVideoExtensions(void) {
    static NSArray *exts;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        exts = @[@"mp4", @"mov", @"m4v", @"m3u8", @"mpg", @"mpeg", @"avi", @"3gp", @"wmv", @"flv"];
    });
    return exts;
}

@implementation VideoStore

+ (NSString *)videosDirectory {
    return [FileTool resolveChildPathInDocuments:@"videos" create:YES];
}

+ (NSString *)ensureDefaultFolder {
    return [self folderPath:@"default"];
}

+ (NSArray<NSString *> *)folderNames {
    NSMutableArray<NSString *> *names = [[FileTool subdirectoryNamesInDirectory:[self videosDirectory]] mutableCopy];
    // 保证 default 总在列表中并排在最前
    if (![names containsObject:@"default"]) {
        [names addObject:@"default"];
    }
    return [names sortedArrayWithOptions:0 usingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        // 首项(default)保持第 0,其余按名字升序
        if ([a isEqualToString:@"default"]) return NSOrderedAscending;
        if ([b isEqualToString:@"default"]) return NSOrderedDescending;
        return [a compare:b];
    }];
}

+ (NSString *)folderPath:(NSString *)name {
    // 子文件夹落在 videos 目录下,而非 Documents 根
    NSString *full = [FileTool resolveChildPath:name inDirectory:[self videosDirectory] create:YES];
    return full ?: [self videosDirectory];
}

+ (BOOL)createFolder:(NSString *)name {
    NSString *full = [FileTool resolveChildPath:name inDirectory:[self videosDirectory] create:NO];
    if (!full) return NO;
    if ([FileTool existsAtPath:full]) {
        // 同名路径已存在但不是目录(被文件占位)时创建不了
        if (![FileTool directoryExists:full]) {
            NSLog(@"创建视频文件夹失败: %@ 已被同名文件占用", name);
            return NO;
        }
        return YES;   // 已存在视为成功
    }
    NSError *error = nil;
    BOOL ok = [[NSFileManager defaultManager] createDirectoryAtPath:full withIntermediateDirectories:YES attributes:nil error:&error];
    if (!ok) {
        NSLog(@"创建视频文件夹失败: %@", error);
    }
    return ok;
}

+ (NSArray<NSString *> *)videoPathsInFolder:(NSString *)name {
    return [FileTool pathsInDirectory:[self folderPath:name] matchingExtensions:kVideoExtensions()];
}

+ (BOOL)isVideoName:(NSString *)name {
    return [FileTool name:name hasExtensionInSet:kVideoExtensions()];
}

+ (nullable NSString *)saveVideoFromURL:(NSURL *)url intoDirectory:(NSString *)dir error:(NSError **)error {
    return [FileTool copyFromURL:url intoDirectory:dir fallbackName:@"video.mp4" error:error];
}

+ (BOOL)deleteVideoAtPath:(NSString *)path {
    NSError *error = nil;
    BOOL ok = [FileTool deleteAtPath:path error:&error];
    if (!ok) {
        NSLog(@"删除视频失败: %@", error);
    }
    return ok;
}

+ (BOOL)deleteFolder:(NSString *)name {
    // resolveChildPath 内置防路径逃逸:名字带路径分隔符时返回 nil
    NSString *full = [FileTool resolveChildPath:name inDirectory:[self videosDirectory] create:NO];
    if (!full) return NO;
    NSError *error = nil;
    BOOL ok = [FileTool deleteAtPath:full error:&error];
    if (!ok) {
        NSLog(@"删除视频文件夹失败: %@", error);
    }
    return ok;
}

@end
