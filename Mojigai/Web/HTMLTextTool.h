//
//  HTMLTextTool.h
//  Mojigai
//
//  Created by zhaohongbin on 2026/10/13.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

/*
 网页 HTML 处理工具
 把网页 HTML 清洗成纯文本；从 HTML 中提取 m3u8 视频地址；过滤正文里的推广块
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HTMLTextTool : NSObject

/// 把网页 HTML 清洗成纯文本:整块去掉脚本/样式/注释,块级标签转换行,剩余标签去掉,还原常见 HTML 实体,逐行去首尾空白
+ (NSString *)filterHTML:(NSString *)html;

/// 用正则从 HTML 中提取 video/source 标签 src 里含 .m3u8 的地址(已还原 HTML 实体,结果去重)
+ (NSArray<NSString *> *)extractM3U8URLsFromHTML:(NSString *)html;

/// 去掉正文中的推广块:按推广块的首尾标记整段删除(标记以 Base64 常量内置,解码后参与匹配)
+ (NSString *)removePromoBlock:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
