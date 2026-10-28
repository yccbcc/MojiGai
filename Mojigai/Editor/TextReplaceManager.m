//
//  TextReplaceManager.m
//  Mojigai
//
//  Created by zhaohongbin on 2026/10/13.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import "TextReplaceManager.h"

@implementation TextReplaceManager

+ (NSString *)replaceText:(NSString *)text leftText:(NSString *)leftText rightText:(NSString *)rightText {

    // 按组合字符拆分左右文本
    NSMutableArray<NSString *> *leftChars = [NSMutableArray array];
    NSMutableArray<NSString *> *rightChars = [NSMutableArray array];
    [leftText enumerateSubstringsInRange:NSMakeRange(0, leftText.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString * _Nullable substring, NSRange substringRange, NSRange enclosingRange, BOOL * _Nonnull stop) {
        [leftChars addObject:substring];
    }];
    [rightText enumerateSubstringsInRange:NSMakeRange(0, rightText.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString * _Nullable substring, NSRange substringRange, NSRange enclosingRange, BOOL * _Nonnull stop) {
        [rightChars addObject:substring];
    }];
    
    // ===== 替换规则(统一记法: "匹配串"→"结果";.. 表示任意空白,允许夹杂在字与字之间) =====
    //
    // 跑几轮(去头级联,左右长度关系只影响轮数,不改变行为):
    //   第0轮匹配左栏整条,此后每轮去掉开头1个字;后缀降到 max(右栏字数,2) 停,即去头数 = 左栏字数 - max(右栏,2)
    //   3字→2轮: "abc"、"bc"    4字→3轮: "abcd"、"bcd"、"cd"    配"xyz"或"yz"轮次清单相同
    //   2字/1字左栏、左短右长: 只1轮整条
    //
    // 每轮匹配到后怎么换:整段直接换成右栏对应文本,不再保留格式(字间空白丢弃):
    //   "abc"→"xyz"   "a..bc"→"xyz"   "ab..c"→"xyz"   "abcd"→"yz"
    //
    // 各轮都要求匹配串字符齐全,缺字不换(避免首字/前缀撞进无关词误替换,如"小新"不会拆出单"小")
    
    // alignByChar:两边字数相同,逐字对位(每轮换右栏对应后缀);leftLonger:左栏更长,右栏对齐左栏末尾
    BOOL alignByChar = leftChars.count == rightChars.count && leftChars.count > 1;
    BOOL leftLonger = leftChars.count > rightChars.count;
    NSString *result = text;
    // 替换轮数:第0轮匹配整条,后面每轮去掉开头一个字(后缀至少留2个字,避免单字满篇误替换);
    // 等长时换到只剩2个字,左长右短时换到后缀与右栏等长,如"abc"→"yz"依次替换"abc"、"bc"
    NSUInteger lastStart = 0;
    if (alignByChar) {
        lastStart = leftChars.count - 2;
    } else if (leftLonger) {
        NSUInteger minLen = MAX(rightChars.count, 2);
        lastStart = leftChars.count > minLen ? leftChars.count - minLen : 0;
    }
    for (NSUInteger k = 0; k <= lastStart; k++) {
        // 本轮匹配左栏从第k个字开始的后缀;先长后短,避免长串被短后缀提前拆坏
        NSMutableString *pattern = [NSMutableString string];
        for (NSUInteger i = k; i < leftChars.count; i++) {
            if (i > k) {
                // 字与字之间允许夹杂任意空白(仅容错匹配,替换时直接丢弃,不保留格式)
                [pattern appendString:@"\\s*"];
            }
            // 转义正则特殊字符,保证左栏内容按普通文字匹配
            NSString *escapedChar = [NSRegularExpression escapedPatternForString:leftChars[i]];
            [pattern appendString:escapedChar];
        }
        
        // 替换模板:逐字对应时取右栏同位置字符,否则整段用完整右栏文本
        // tStart:左栏更长时每轮都替换成完整右栏(从右栏第1个字取起),其余情况从第k个字取起
        NSUInteger tStart = leftLonger ? 0 : k;
        NSMutableString *template = [NSMutableString string];
        for (NSUInteger i = tStart; i < rightChars.count; i++) {
            // 替换文本中的 \ 和 $ 需要转义,避免被当成模板占位符
            NSString *oneChar = [rightChars[i] stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
            oneChar = [oneChar stringByReplacingOccurrencesOfString:@"$" withString:@"\\$"];
            [template appendString:oneChar];
        }
        
        // 执行本轮替换,结果作为下一轮的输入继续替换
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        if (regex) {
            result = [regex stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length) withTemplate:template];
        }
    }
    return result;
}

@end
