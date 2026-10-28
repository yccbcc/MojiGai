//
//  TextReplaceManager.h
//  Mojigai
//
//  Created by zhaohongbin on 2026/10/13.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

/*
 文本替换工具：把原文中的左栏文本批量替换成右栏文本
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TextReplaceManager : NSObject

/// 把 text 中的左栏文本按规则批量替换为右栏文本，返回替换后的完整文本
/// @param text      待替换的原始文本
/// @param leftText  左栏文本（被替换内容，字符之间可夹杂任意空白）
/// @param rightText 右栏文本（替换内容）
+ (NSString *)replaceText:(NSString *)text leftText:(NSString *)leftText rightText:(NSString *)rightText;

@end

NS_ASSUME_NONNULL_END
