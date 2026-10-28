//
//  TxtStore.m
//  MojiGai
//
//  Created by zhaohongbin on 2023/8/25.
//  Copyright © 2023 zhaohongbin. All rights reserved.
//

#import "TxtStore.h"
#import "FileTool.h"
#import <UIKit/UIKit.h>
@implementation TxtStore

+(NSArray *)pagingWithContentString:(NSString *)contentString contentSize:(CGSize)contentSize textAttribute:(NSDictionary *)textAttribute
{
    
    NSMutableArray *pageArray = [NSMutableArray array];
    NSMutableAttributedString *orginAttributeString = [[NSMutableAttributedString alloc]initWithString:contentString attributes:textAttribute];
    NSTextStorage *textStorage = [[NSTextStorage alloc]initWithAttributedString:orginAttributeString];
    NSLayoutManager *layoutManager = [[NSLayoutManager alloc]init];
    [textStorage addLayoutManager:layoutManager];
    int I=0;
    while (YES) {
        I++;
        NSTextContainer *textContainer = [[NSTextContainer alloc]initWithSize:contentSize];
        [layoutManager addTextContainer:textContainer];
        NSRange rang = [layoutManager glyphRangeForTextContainer:textContainer];
        if(rang.length <= 0)
        {
            break;
        }
        NSString *str = [contentString substringWithRange:rang];
        //NSMutableAttributedString *attstr = [[NSMutableAttributedString alloc]initWithString:str attributes:textAttribute];
        [pageArray addObject:str];
    }
    return pageArray;
}

#pragma mark - 文本内容落盘(Documents/txts)

+ (NSString *)txtsDirPath{
    return [FileTool resolveChildPathInDocuments:@"txts" create:YES];
}

// 文件名只留安全字符,避免路径注入/特殊字符
+ (NSString *)safeBaseName:(NSString *)key{
    NSCharacterSet *illegal = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|%"];
    key = [[key componentsSeparatedByCharactersInSet:illegal] componentsJoinedByString:@"_"];
    if (key.length == 0) key = @"entry";
    if (key.length > 40) key = [key substringToIndex:40];
    return key;
}

+ (BOOL)saveValue:(NSString *)value toEntry:(NSMutableDictionary *)entry{
    NSString *fname = entry[@"file"];
    if (!fname) {
        NSString *base = [self safeBaseName:entry[@"key"]];
        fname = [NSString stringWithFormat:@"%@_%@.txt", base, [NSUUID UUID].UUIDString];
        entry[@"file"] = fname;
    }
    NSString *path = [[self txtsDirPath] stringByAppendingPathComponent:fname];
    return [value writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

+ (NSString *)readValueForEntry:(NSDictionary *)entry{
    NSString *fname = entry[@"file"];
    if (fname) {
        NSString *path = [[self txtsDirPath] stringByAppendingPathComponent:fname];
        if ([FileTool existsAtPath:path]) {
            return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        }
    }
    // 老格式回退:未落盘时正文仍在 entry 里
    return entry[@"value"];
}

#pragma mark - 分页结果缓存

+ (NSString *)pagesPathForEntry:(NSDictionary *)entry{
    NSString *fname = entry[@"file"];
    if (!fname) return nil;
    NSString *base = [fname stringByDeletingPathExtension];   // 去掉 .txt
    return [[self txtsDirPath] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.pages", base]];
}

+ (BOOL)savePages:(NSArray *)pages forEntry:(NSMutableDictionary *)entry{
    NSString *path = [self pagesPathForEntry:entry];
    if (!path) return NO;
    return [pages writeToFile:path atomically:YES];
}

+ (NSArray *)readPagesForEntry:(NSDictionary *)entry{
    NSString *path = [self pagesPathForEntry:entry];
    if (!path) return nil;
    NSArray *arr = [NSArray arrayWithContentsOfFile:path];
    return ([arr isKindOfClass:[NSArray class]]) ? arr : nil;
}

+ (void)removePagesForEntry:(NSDictionary *)entry{
    NSString *path = [self pagesPathForEntry:entry];
    if (path) {
        [FileTool deleteAtPath:path error:nil];
    }
}

#pragma mark - 删除条目相关文件

+ (void)removeEntryFiles:(NSDictionary *)entry{
    NSString *fname = entry[@"file"];
    if (fname) {
        [FileTool deleteAtPath:[[self txtsDirPath] stringByAppendingPathComponent:fname] error:nil];
    }
    [self removePagesForEntry:entry];
}

@end


/**
 @implementation ViewController
 {
     UITextView *_textView;
     NSArray *_dataArr;
 }
 - (void)viewDidLoad {
     [super viewDidLoad];
     // Do any additional setup after loading the view.
     
     
     NSString *txt = @"后续，广东盐业会持续密切关注国家及广东省环保部门公布的海水水质信息，对广东海水定期进行放射性元素送检，并严密监控盐产品是否受污染的情况，保障广东盐业食盐产品的质量安全及供应安全。\n广东盐业集团相关负责人介绍称，目前，省、市两级食盐政府储备量和企业社会责任储备共10.8万吨，能保障食盐充足供应。同时，广东盐业已对广东省主要海盐生产工区的海域海水及生态海盐进行了α、β放射性项目的第三方送样检测，结果显示目前的广东海盐是安全的。\n据广东盐业集团负责人介绍，广东盐业作为广东省内唯一的省属食盐生产运销和储备企业，长期以来肩负确保本省食盐质量安全、供应安全的社会责任。目前，省、市两级食盐政府储备量和企业社会责任储备共10.8万吨，百分百覆盖全省各市县行政区域，能迅速及时响应，保障食盐充足供应。市民不必恐慌，更不必效仿“囤盐”。\n暴雨来势汹汹，台风也在海上活跃！目前，西北太平洋上台风“苏拉”“达维”“双台共舞”。\n据中央气象台消息，今年第10号台风“达维”于25日05时在西北太平洋洋面上生成。预计，“达维”将以每小时25-30公里的速度向东北方向移动，强度变化不大。而今年第9号台风“苏拉”，于24日下午生成。“苏拉”附近海温接近30℃，有季风水汽的支持，利于其结构维持和继续整合，后续“苏拉”可能加强为下一个超强台风。\n今年第9号台风“苏拉”和第10号台风“达维”都已生成，据最新预报显示台风“达维”未来对我国无影响，公众需着重关注台风“苏拉”的未来动向。今日8时，台风“苏拉”位于菲律宾马尼拉北偏东方向约650公里，强度为强热带风暴（10级，25米/秒），中心最低气压为985百帕。预计，“苏拉”将先在菲律宾吕宋岛东北部洋面徘徊，29日开始向北偏西方向移动，逐渐向台湾东部沿海靠近，最强可达强台风级或超强台风级（45~52m/s，14~16级）。";
     
     _textView = [[UITextView alloc] initWithFrame:CGRectMake(0, 100, UIScreen.mainScreen.bounds.size.width, 500)];
     _textView.backgroundColor = UIColor.lightGrayColor;
     [self.view addSubview:_textView];
     
     _dataArr = [self pagingWithContentString:txt contentSize:CGSizeMake(UIScreen.mainScreen.bounds.size.width, 500) textAttribute:@{NSFontAttributeName: [UIFont fontWithName:@"PingFang TC" size:20]}];
     
     _textView.attributedText = _dataArr[0];
     
 }

 - (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
     _textView.attributedText = _dataArr[1];
 }


 @end
 */
