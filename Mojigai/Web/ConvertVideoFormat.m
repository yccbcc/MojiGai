#import "ConvertVideoFormat.h"
@import ffmpegkit;

@interface ConvertVideoFormat ()
@property (nonatomic, strong, nullable) FFmpegSession *currentSession;
@end

@implementation ConvertVideoFormat

+ (void)convertM3U8ToMP4WithInputURL:(NSURL *)m3u8URL
                           outputURL:(NSURL *)outputURL
                            progress:(ConvertProgressBlock)progressBlock
                          completion:(ConvertCompletionBlock)completionBlock {
    
    // 清理可能存在的旧输出文件
    [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
    
    NSString *inputPath  = m3u8URL.absoluteString;
    NSString *outputPath = outputURL.path;
    
    // 使用参数数组方式，避免路径中的空格/特殊字符导致命令解析错误
    NSArray *arguments = @[
        @"-i", inputPath,              // 输入 m3u8
        @"-c", @"copy",                // 直接复制流，不重新编码，速度最快
        @"-bsf:a", @"aac_adtstoasc",   // HLS 的 AAC 流需转为普通 AAC 才能封装进 mp4
        @"-y",                         // 覆盖已有文件
        outputPath                     // 输出 mp4 路径
    ];
    
    // 记录会话，便于取消
    FFmpegSession *session = [FFmpegKit executeWithArgumentsAsync:arguments
        withCompleteCallback:^(FFmpegSession *session) {
            ReturnCode *returnCode = [session getReturnCode];
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([ReturnCode isSuccess:returnCode]) {
                    completionBlock(YES, outputURL, nil);
                } else if ([ReturnCode isCancel:returnCode]) {
                    completionBlock(NO, nil, @"转换已取消");
                } else {
                    NSString *failMsg = [session getFailStackTrace] ?: @"未知错误";
                    completionBlock(NO, nil, failMsg);
                }
            });
        }
        withLogCallback:^(Log *log) {
            // 可按需打印日志，调试时开启
            // NSLog(@"[FFmpeg] %@", [log getMessage]);
        }
        withStatisticsCallback:^(Statistics *statistics) {
            // statistics 中包含 time、bitrate、speed 等，这里用 time 估算进度
            if (progressBlock) {
                // 注意：需要知道总时长才能算准确进度，此处仅传 time（毫秒）
                // 若已知总时长，可在此计算 time/totalDuration
                float currentMs = [statistics getTime];
                // 如果外部知道总时长，可自行换算；这里先回调原始值供参考
                progressBlock(currentMs);
            }
        }];
    
    // 保存会话引用（需为单例或使用静态变量，这里简单处理）
    // 实际项目中建议将 currentSession 管理为单例属性
    // [ConvertVideoFormat sharedInstance].currentSession = session;
}

+ (void)cancelCurrentConversion {
    // 如需取消，需持有 session 引用
    // [[ConvertVideoFormat sharedInstance].currentSession cancel];
}

@end
