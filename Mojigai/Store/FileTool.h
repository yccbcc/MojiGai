//
//  FileTool.h
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/28.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

/*
 文件/文件夹通用操作工具(Store 层基础设施)
 统一各 Store 与控制器里分散的目录确保创建、子项列举、文件名清理、同名顺延、复制/移动/删除,
 以及 Documents 业务子目录路径解析(内置防路径逃逸)和导入临时文件的安全清理判定
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FileTool : NSObject

/// Documents 根目录
+ (NSString *)documentsDirectory;

/// 解析 Documents 下业务子目录/子文件的路径;create=YES 时目录不存在会自动创建。
/// 名字含路径分隔符(防逃逸)或清理后为空时返回 nil
+ (nullable NSString *)resolveChildPathInDocuments:(NSString *)name create:(BOOL)create;

/// 解析任意父目录下子项的路径,防逃逸/清理规则同上;create=YES 时目录不存在会自动创建
+ (nullable NSString *)resolveChildPath:(NSString *)name inDirectory:(NSString *)parent create:(BOOL)create;

/// 目录下的子文件夹名(升序,不含隐藏项)
+ (NSArray<NSString *> *)subdirectoryNamesInDirectory:(NSString *)dir;

/// 从文件名列表中挑出扩展名命中给定集合的完整路径(升序)
+ (NSArray<NSString *> *)pathsInDirectory:(NSString *)dir matchingExtensions:(NSArray<NSString *> *)exts;

/// 文件名是否命中给定扩展名集合(不区分大小写)
+ (BOOL)name:(NSString *)name hasExtensionInSet:(NSArray<NSString *> *)exts;

/// 目录是否存在
+ (BOOL)directoryExists:(NSString *)path;

/// 文件/目录是否存在
+ (BOOL)existsAtPath:(NSString *)path;

/// 确保目录存在(不存在逐级创建),返回该路径
+ (NSString *)ensureDirectory:(NSString *)path;

/// 移动/重命名(目标已存在时失败并通过 error 返回)
+ (BOOL)moveFromPath:(NSString *)from toPath:(NSString *)to error:(NSError **)error;

/// 删除,不存在视为成功
+ (BOOL)deleteAtPath:(NSString *)path error:(NSError **)error;

/// 把外部 URL 复制进目录,同名自动顺延;security-scoped 访问自动配对 start/stop。
/// fallbackName 在源 URL 无文件名时使用;返回落地路径,失败返回 nil
+ (nullable NSString *)copyFromURL:(NSURL *)url intoDirectory:(NSString *)dir fallbackName:(NSString *)fallbackName error:(NSError **)error;

/// 判断导入产生的临时文件是否可安全清理(位于 Documents 下、且不在业务子目录内)
+ (BOOL)isImportedStagingCleanableAtPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
