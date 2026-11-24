//
//  HTMLTextTool.m
//  Mojigai
//
//  Created by zhaohongbin on 2026/10/13.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import "HTMLTextTool.h"

// Base64 解码为 UTF-8 明文字符串,失败返回 nil
static NSString *MojiDecodeBase64(NSString *base64) {
    NSData *data = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
    if (!data) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@implementation HTMLTextTool

+ (NSString *)filterHTML:(NSString *)html{
    NSString *content = html ?: @"";
    //整块去掉脚本/样式/头部/注释(连标签带内容),这些不是页面正文
    NSRegularExpression *regularExpretion=[NSRegularExpression regularExpressionWithPattern:@"<script[\\s\\S]*?</script>|<style[\\s\\S]*?</style>|<noscript[\\s\\S]*?</noscript>|<head[\\s\\S]*?</head>|<!--[\\s\\S]*?-->" options:NSRegularExpressionCaseInsensitive error:nil];
    content=[regularExpretion stringByReplacingMatchesInString:content options:0 range:NSMakeRange(0, content.length) withTemplate:@""];
    
    //块级标签的结束位置换成换行,避免相邻内容粘连成一行
    regularExpretion=[NSRegularExpression regularExpressionWithPattern:@"<br[^>]*>|</(p|div|li|h[1-6]|tr|td|th|section|article|header|footer|ul|ol|table|blockquote)>" options:NSRegularExpressionCaseInsensitive error:nil];
    content=[regularExpretion stringByReplacingMatchesInString:content options:0 range:NSMakeRange(0, content.length) withTemplate:@"\n"];
    
    //剩下的标签全部去掉
    regularExpretion=[NSRegularExpression regularExpressionWithPattern:@"<[^>]*>" options:0 error:nil];
    content=[regularExpretion stringByReplacingMatchesInString:content options:0 range:NSMakeRange(0, content.length) withTemplate:@""];
    
    //还原常见HTML实体(&amp;最后还原,避免二次解码)
    content=[content stringByReplacingOccurrencesOfString:@"&nbsp;" withString:@" "];
    content=[content stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    content=[content stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    content=[content stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    content=[content stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"];
    content=[content stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    
    //逐行去首尾空白,丢弃空行
    NSMutableArray *marr=[NSMutableArray array];
    for (NSString *line in [content componentsSeparatedByString:@"\n"]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) {
            [marr addObject:trimmed];
        }
    }
    return  [marr componentsJoinedByString:@"\n"];
}

+ (NSString *)removePromoBlock:(NSString *)text{
    NSString *content = text ?: @"";
    if (content.length == 0) {
        return content;
    }
    // 推广块的首尾标记以 Base64 常量内置,解码后再参与匹配,明文不落在代码与注释里
    NSString *headMark = MojiDecodeBase64(@"5bm/6ICM5ZGK5LmL77ya5peg6ZmQ5Yi25rap5rap");
    NSString *tailMark = MojiDecodeBase64(@"Pj4+5p+l55yL5pu05aSa5biW5Li756S+5Yy65Yqo5oCB");
    if (headMark.length == 0 || tailMark.length == 0) {
        return content;
    }
    // 中间内容惰性匹配跨行,遇到第一个尾标记即停止;尾标记后的省略号允许三个英文点或中文省略号,也没有时同样命中
    NSString *pattern = [NSString stringWithFormat:@"%@[\\s\\S]*?%@(?:\\.{3}|…{1,2})?", headMark, tailMark];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    if (!regex) {
        return content;
    }
    return [regex stringByReplacingMatchesInString:content options:0 range:NSMakeRange(0, content.length) withTemplate:@""];
}

+ (NSArray<NSString *> *)extractM3U8URLsFromHTML:(NSString *)html{
    NSMutableArray<NSString *> *urls = [NSMutableArray array];
    NSError *regexError = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"src\\s*=\\s*[\"']([^\"']*\\.m3u8[^\"']*)[\"']"
                                                                            options:NSRegularExpressionCaseInsensitive
                                                                              error:&regexError];
    if (!regexError) {
        NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:html
                                                                  options:0
                                                                    range:NSMakeRange(0, html.length)];
        for (NSTextCheckingResult *match in matches) {
            if (match.numberOfRanges >= 2) {
                NSString *src = [html substringWithRange:[match rangeAtIndex:1]];
                // HTML 实体还原：&amp; -> & 等
                src = [src stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
                src = [src stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
                src = [src stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"];
                src = [src stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
                src = [src stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
                if (src.length > 0 && ![urls containsObject:src]) {
                    [urls addObject:src];
                }
            }
        }
    }
    return urls;
}

@end
