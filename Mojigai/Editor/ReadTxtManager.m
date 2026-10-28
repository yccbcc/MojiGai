//
//  ReadTxtManager.m
//  MojiGai
//
//  Created by 赵宏彬 on 2020/12/11.
//  Copyright © 2020 zhaohongbin. All rights reserved.
//

#import "ReadTxtManager.h"
#import <sys/utsname.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define kFilePath [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) objectAtIndex:0]

@implementation ReadTxtManager

+ (NSString *)readTxtWithPath:(NSString *)txtPath txtName:(NSString *)name{
    NSLog(@"txtPath : %@",txtPath);

    //-------------------------------------------------------------------------------------------
    //编码格式
    //    NSArray *arrEncoding = @[@(NSASCIIStringEncoding),
    //                             @(NSNEXTSTEPStringEncoding),
    //                             @(NSJapaneseEUCStringEncoding),
    //                             @(NSUTF8StringEncoding),
    //                             @(NSISOLatin1StringEncoding),
    //                             @(NSSymbolStringEncoding),
    //                             @(NSNonLossyASCIIStringEncoding),
    //                             @(NSShiftJISStringEncoding),
    //                             @(NSISOLatin2StringEncoding),
    //                             @(NSUnicodeStringEncoding),
    //                             @(NSWindowsCP1251StringEncoding),
    //                             @(NSWindowsCP1252StringEncoding),
    //                             @(NSWindowsCP1253StringEncoding),
    //                             @(NSWindowsCP1254StringEncoding),
    //                             @(NSWindowsCP1250StringEncoding),
    //                             @(NSISO2022JPStringEncoding),
    //                             @(NSMacOSRomanStringEncoding),
    //                             @(NSUTF16StringEncoding),
    //                             @(NSUTF16BigEndianStringEncoding),
    //                             @(NSUTF16LittleEndianStringEncoding),
    //                             @(NSUTF32StringEncoding),
    //                             @(NSUTF32BigEndianStringEncoding),
    //                             @(NSUTF32LittleEndianStringEncoding),
    //                             @(enc)
    //    ];

    NSStringEncoding enc = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    NSArray *arrEncodingArr = @[
        @(NSUTF8StringEncoding),
        @(enc)
    ];
    
    
    NSURL *url = [NSURL fileURLWithPath:txtPath];  //本地路径使用 fileURLWithPath 而不是 URLWithPath
    BOOL didStart = [url startAccessingSecurityScopedResource];  //普通路径下为 no-op；返回 NO 也不代表读不了，不能当门禁
    NSString *result = nil;
    for (int i = 0 ; i < [arrEncodingArr count]; i++) {
        unsigned long encodingCode = [arrEncodingArr[i] unsignedLongValue];
        NSError *error = nil;
        result = [NSString stringWithContentsOfFile:txtPath encoding:encodingCode  error:&error];
        if (result) {
            [self writeToTXTFileWithString:result fileName:name];
            break;
        }
        NSLog(@"读取失败: %@", error);
    }
    if (didStart) {
        [url stopAccessingSecurityScopedResource];  //stop 只与 start 配对，与读取成败无关
    }
    return result;  //读取失败返回 nil（空文件返回空串），调用方据此区分
}

+ (void)writeToTXTFileWithString:(NSString *)string fileName:(NSString *)fileName {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        //获取文件路径
        NSString *theFilePath = [kFilePath stringByAppendingPathComponent:fileName];
        NSLog(@"%@",theFilePath);
        //覆盖写入（另存一份）：同一文件重复打开只保留最新一份内容
        NSError *error = nil;
        [string writeToFile:theFilePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (error) {
            NSLog(@"写入失败: %@", error);
        }
    });
}

#pragma mark - 读取文件
- (void)readString{
    //        NSData *data = [aString dataUsingEncoding:encodingCode];
    //        NSString *string = [[NSString alloc] initWithData:data encoding:encodingCode];
    
    NSStringEncoding enc = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    NSArray *arrEncodingArr = @[
        @(NSUTF8StringEncoding),
        @(enc)
    ];
    
    NSString *aString;
    
    NSArray *filepaths = [self fetchAllFilePaths];
    
    for (NSString *filepath in filepaths) {
        for (int i = 0 ; i < [arrEncodingArr count]; i++) {
            unsigned long encodingCode = [arrEncodingArr[i] unsignedLongValue];
            NSError *error = nil;
            NSString *filePath = filepath; // <---这里是要查看的文件路径
            aString = [NSString stringWithContentsOfFile:filePath encoding:encodingCode  error:&error];
            if (error != nil) {
                
            }else{
                // 如果有必要，还可以把文件创建出来再测试
                [aString writeToFile:[NSString stringWithFormat:@"/Users/dlios1/Desktop/%@.xml", arrEncodingArr[i]]
                         atomically:YES
                           encoding:encodingCode
                              error:&error];
                break;
            }
        }
    }
}


#pragma mark - 获取文件夹下的所有文件
- (NSArray *)fetchAllFilePaths{
    NSString *from = kFilePath;
    NSFileManager *mgr = [NSFileManager defaultManager];
    NSError *error2;
    NSArray *subpaths=[mgr contentsOfDirectoryAtPath:from error:&error2];
    NSLog(@"subpaths = %@",subpaths);
    return subpaths;
}


    
@end
