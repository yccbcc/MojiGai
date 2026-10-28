//
//  FileTool.m
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/28.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import "FileTool.h"

static NSString * const kFileToolIllegalNameChars = @"/\\:*?\"<>|%";

// Documents 下受保护的业务子目录,导入临时文件清理时绝不触碰
static NSArray<NSString *> *kFileToolProtectedFolders(void) {
    static NSArray *folders;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        folders = @[@"/txts/", @"/images/", @"/videos/"];
    });
    return folders;
}

// 仅供本类内部复用的私有原语(不对外公开)
@interface FileTool ()
+ (NSArray<NSString *> *)contentsOfDirectory:(NSString *)dir;
+ (NSString *)safeName:(NSString *)name;
+ (NSString *)uniquePathInDirectory:(NSString *)dir name:(NSString *)name;
@end

@implementation FileTool

+ (NSString *)documentsDirectory {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
}

+ (NSString *)resolveChildPathInDocuments:(NSString *)name create:(BOOL)create {
    return [self resolveChildPath:name inDirectory:[self documentsDirectory] create:create];
}

+ (NSString *)resolveChildPath:(NSString *)name inDirectory:(NSString *)parent create:(BOOL)create {
    // 防路径逃逸:不允许名字里带路径分隔符(含清理时被替换前的原始字符)
    if ([name containsString:@"/"] || [name containsString:@"\\"]) return nil;
    NSString *clean = [self safeName:name];
    if (clean.length == 0) return nil;
    NSString *full = [parent stringByAppendingPathComponent:clean];
    if (create) {
        [self ensureDirectory:full];
    }
    return full;
}

+ (NSArray<NSString *> *)contentsOfDirectory:(NSString *)dir {
    NSArray<NSString *> *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *name in contents) {
        if ([name hasPrefix:@"."]) continue;   // 隐藏项(.DS_Store 等)
        [names addObject:name];
    }
    return [names sortedArrayUsingSelector:@selector(compare:)];
}

+ (NSArray<NSString *> *)subdirectoryNamesInDirectory:(NSString *)dir {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *name in [self contentsOfDirectory:dir]) {
        BOOL isDir = NO;
        if ([fileManager fileExistsAtPath:[dir stringByAppendingPathComponent:name] isDirectory:&isDir] && isDir) {
            [names addObject:name];
        }
    }
    return names;
}

+ (NSArray<NSString *> *)pathsInDirectory:(NSString *)dir matchingExtensions:(NSArray<NSString *> *)exts {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSString *name in [self contentsOfDirectory:dir]) {
        if ([self name:name hasExtensionInSet:exts]) {
            [paths addObject:[dir stringByAppendingPathComponent:name]];
        }
    }
    return paths;
}

+ (BOOL)name:(NSString *)name hasExtensionInSet:(NSArray<NSString *> *)exts {
    NSString *ext = name.pathExtension.lowercaseString;
    return ext.length > 0 && [exts containsObject:ext];
}

+ (BOOL)directoryExists:(NSString *)path {
    BOOL isDir = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && isDir;
}

+ (BOOL)existsAtPath:(NSString *)path {
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

+ (NSString *)ensureDirectory:(NSString *)path {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:path]) {
        [fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return path;
}

+ (NSString *)safeName:(NSString *)name {
    name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSCharacterSet *illegal = [NSCharacterSet characterSetWithCharactersInString:kFileToolIllegalNameChars];
    return [[name componentsSeparatedByCharactersInSet:illegal] componentsJoinedByString:@"_"];
}

+ (NSString *)uniquePathInDirectory:(NSString *)dir name:(NSString *)name {
    NSString *dest = [dir stringByAppendingPathComponent:name];
    if (![self existsAtPath:dest]) {
        return dest;
    }
    NSString *base = name.stringByDeletingPathExtension;
    NSString *ext = name.pathExtension;
    NSInteger index = 1;
    while (YES) {
        NSString *candidate = ext.length > 0 ? [NSString stringWithFormat:@"%@_%ld.%@", base, (long)index, ext]
                                             : [NSString stringWithFormat:@"%@_%ld", base, (long)index];
        dest = [dir stringByAppendingPathComponent:candidate];
        if (![self existsAtPath:dest]) {
            return dest;
        }
        index++;
    }
}

+ (BOOL)moveFromPath:(NSString *)from toPath:(NSString *)to error:(NSError **)error {
    return [[NSFileManager defaultManager] moveItemAtPath:from toPath:to error:error];
}

+ (BOOL)deleteAtPath:(NSString *)path error:(NSError **)error {
    if (![self existsAtPath:path]) return YES;   // 不存在视为删除成功
    return [[NSFileManager defaultManager] removeItemAtPath:path error:error];
}

+ (NSString *)copyFromURL:(NSURL *)url intoDirectory:(NSString *)dir fallbackName:(NSString *)fallbackName error:(NSError **)error {
    NSString *name = url.lastPathComponent.length > 0 ? url.lastPathComponent : fallbackName;
    NSString *dest = [self uniquePathInDirectory:dir name:name];
    // 普通路径下 start 是 no-op，返回值不可当可读性门禁，仅记录并配对 stop
    BOOL didStart = [url startAccessingSecurityScopedResource];
    BOOL success = [[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:dest] error:error];
    if (didStart) {
        [url stopAccessingSecurityScopedResource];
    }
    return success ? dest : nil;
}

+ (BOOL)isImportedStagingCleanableAtPath:(NSString *)path {
    if (![path containsString:@"/Documents/"]) return NO;
    for (NSString *folder in kFileToolProtectedFolders()) {
        if ([path containsString:folder]) return NO;
    }
    return YES;
}

@end
