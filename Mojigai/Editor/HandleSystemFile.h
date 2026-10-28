//
//  HandleSystemFile.h
//  MojiGai
//
//  Created by cyou_zhb on 2021/4/6.
//  Copyright © 2021 zhaohongbin. All rights reserved.
//

/*
 导出txt到系统「文件」App(暂存文件导出后即清理)
 去读取file文件中的文档
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface HandleSystemFile : NSObject<UIDocumentPickerDelegate>

+ (instancetype)shareInstance;

@property (nonatomic, weak) UIViewController *controller;

/// export 模式导出的暂存文件路径;导出完成或取消后由本类删除,避免沙盒残留
@property (nonatomic, copy, nullable) NSString *exportStagedPath;

- (void)saveToFile:(NSString *)filePath;
- (void)readFile;//(没有用到)


@end

NS_ASSUME_NONNULL_END
