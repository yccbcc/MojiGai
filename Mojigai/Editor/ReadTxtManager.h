//
//  ReadTxtManager.h
//  MojiGai
//
//  Created by 赵宏彬 on 2020/12/11.
//  Copyright © 2020 zhaohongbin. All rights reserved.
//

/*
 从「文件」App 分享 txt 到本项目打开时，读取 txt 中的文本内容
 依次按 UTF-8/GB18030 编码尝试，读出的内容会另存到 Documents 目录一份
 读取失败返回 nil（空文件返回空串），由调用方区分处理
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ReadTxtManager : NSObject

+ (nullable NSString *)readTxtWithPath:(NSString *)txtPath txtName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
