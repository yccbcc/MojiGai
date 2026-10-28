//
//  HTMLTextTool.m
//  Mojigai
//
//  Created by zhaohongbin on 2026/10/13.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import "HTMLTextTool.h"

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
