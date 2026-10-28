//
//  TxtStore.h
//  MojiGai
//
//  Created by zhaohongbin on 2023/8/25.
//  Copyright © 2023 zhaohongbin. All rights reserved.
//

/*
 阅读文本存取工具
 按内容尺寸分页;正文及分页缓存(.pages)落盘 Documents/txts,UserDefaults 只存轻量元数据,删除条目时一并清理相关文件。
 文件/目录基础操作委托 Store 层 FileTool,本类只做阅读数据的领域逻辑
 */
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TxtStore : NSObject
+(NSArray *)pagingWithContentString:(NSString *)contentString contentSize:(CGSize)contentSize textAttribute:(NSDictionary *)textAttribute;

#pragma mark - 文本内容落盘(Documents/txts),UserDefaults 只留轻量元数据
/// 把正文写入文件,并在 entry 中记录文件名;返回是否成功
+ (BOOL)saveValue:(NSString *)value toEntry:(NSMutableDictionary *)entry;
/// 读取正文(优先读文件;老格式无文件时回退 entry[@"value"])
+ (NSString *)readValueForEntry:(NSDictionary *)entry;

#pragma mark - 分页结果缓存(与正文同目录,存 .pages 文件)
+ (BOOL)savePages:(NSArray *)pages forEntry:(NSMutableDictionary *)entry;
+ (NSArray *)readPagesForEntry:(NSDictionary *)entry;

#pragma mark - 删除条目相关文件(正文 + 分页缓存)
+ (void)removeEntryFiles:(NSDictionary *)entry;
@end

NS_ASSUME_NONNULL_END
