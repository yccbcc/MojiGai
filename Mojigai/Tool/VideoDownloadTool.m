//
//  VideoDownloadTool.m
//  Mojigai
//
//  Created by zhaohongbin on 2026-10-22.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import "VideoDownloadTool.h"
#import "ConvertVideoFormat.h"
#import "VideoStore.h"

// mp4 下载进度 KVO 的专属 context(用静态变量地址,唯一且可与父类区分)
static void * const kMP4ProgressKVOContext = (void *)&kMP4ProgressKVOContext;

@interface VideoDownloadTool ()
// mp4 直下:持有下载任务与进度回调,便于 KVO 上报进度、结束时统一清理
@property (nonatomic, strong, nullable) NSURLSessionDownloadTask *mp4DownloadTask;
@property (nonatomic, copy, nullable) VideoDownloadProgressBlock mp4ProgressBlock;
@end

@implementation VideoDownloadTool

+ (VideoURLType)videoTypeForURLString:(NSString *)urlString {
    NSString *lower = [urlString lowercaseString];
    if ([lower containsString:@".m3u8"] || [lower containsString:@".m3u"]) {
        return VideoURLTypeM3U8;
    }
    if ([lower containsString:@".mp4"]) {
        return VideoURLTypeMP4;
    }
    return VideoURLTypeNone;
}

#pragma mark - m3u8(转 mp4)

- (void)downloadM3U8:(NSString *)m3u8URL
        targetFolder:(NSString *)folderName
            progress:(VideoDownloadProgressBlock)progressBlock
          completion:(VideoDownloadCompletionBlock)completionBlock {
    if (m3u8URL.length == 0) {
        [self deliverCompletion:completionBlock success:NO path:nil message:@"地址为空"];
        return;
    }
    [self removeOldCachedMP4Files];

    NSURL *outputURL = [[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] firstObject];
    NSString *fileName = [NSString stringWithFormat:@"%.0f.mp4", [[NSDate date] timeIntervalSince1970]];
    outputURL = [outputURL URLByAppendingPathComponent:fileName];

    // FFmpeg 统计回调只给出已处理时长(毫秒),缺总时长算不出真实百分比,
    // 这里沿用「估算进度」策略:随回调步进到 90%,转换成功后由完成回调补到 100%。
    __block float fakeProgress = 0;
    __weak typeof(self) weakSelf = self;
    [ConvertVideoFormat convertM3U8ToMP4WithInputURL:[NSURL URLWithString:m3u8URL]
                                          outputURL:outputURL
                                           progress:^(float progress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (fakeProgress < 0.9f) {
                fakeProgress += 0.03f;
                if (fakeProgress > 0.9f) fakeProgress = 0.9f;
                if (progressBlock) progressBlock(fakeProgress);
            }
        });
    } completion:^(BOOL success, NSURL *url, NSString *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!success) {
            NSLog(@"m3u8 转换失败: %@", error);
            [strongSelf deliverCompletion:completionBlock success:NO path:nil message:(error ?: @"转换失败")];
            return;
        }
        NSLog(@"m3u8 转换完成: %@", url.path);
        NSError *copyError = nil;
        NSString *targetDir = [VideoStore folderPath:folderName];
        NSString *stored = [VideoStore saveVideoFromURL:url intoDirectory:targetDir error:&copyError];
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        if (stored) {
            [strongSelf deliverCompletion:completionBlock success:YES path:stored message:nil];
        } else {
            [strongSelf deliverCompletion:completionBlock success:NO path:nil message:(copyError.localizedDescription ?: @"保存失败")];
        }
    }];
}

#pragma mark - mp4(直接下载)

- (void)downloadMP4:(NSString *)mp4URL
       targetFolder:(NSString *)folderName
           progress:(VideoDownloadProgressBlock)progressBlock
         completion:(VideoDownloadCompletionBlock)completionBlock {
    NSURL *url = [NSURL URLWithString:mp4URL];
    if (!url) {
        [self deliverCompletion:completionBlock success:NO path:nil message:@"地址无效"];
        return;
    }
    // 同一工具串行下载:开始新任务前先清理上一个,避免残留观察者
    [self removeMp4ProgressObserver];

    self.mp4ProgressBlock = progressBlock;
    NSURLSession *session = [NSURLSession sharedSession];
    __weak typeof(self) weakSelf = self;
    self.mp4DownloadTask = [session downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf removeMp4ProgressObserver];   // 结束,先摘掉进度 KVO

        if (error || !location) {
            [strongSelf deliverCompletion:completionBlock success:NO path:nil message:(error.localizedDescription ?: @"下载失败")];
            return;
        }
        // 临时文件是随机 UUID 名,尽量按响应建议名重命名后再入库,便于识别
        NSURL *renamed = location;
        NSString *suggested = response.suggestedFilename;
        if (suggested.length > 0) {
            NSString *dirPath = [[location URLByDeletingLastPathComponent] path];
            NSString *tmpPath = [dirPath stringByAppendingPathComponent:suggested];
            if (![[NSFileManager defaultManager] fileExistsAtPath:tmpPath]) {
                [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:tmpPath] error:nil];
                renamed = [NSURL fileURLWithPath:tmpPath];
            }
        }
        NSError *copyError = nil;
        NSString *targetDir = [VideoStore folderPath:folderName];
        NSString *stored = [VideoStore saveVideoFromURL:renamed intoDirectory:targetDir error:&copyError];
        [[NSFileManager defaultManager] removeItemAtURL:renamed error:nil];
        if (stored) {
            [strongSelf deliverCompletion:completionBlock success:YES path:stored message:nil];
        } else {
            [strongSelf deliverCompletion:completionBlock success:NO path:nil message:(copyError.localizedDescription ?: @"保存失败")];
        }
    }];

    [self.mp4DownloadTask addObserver:self
                           forKeyPath:@"countOfBytesReceived"
                              options:NSKeyValueObservingOptionNew
                              context:kMP4ProgressKVOContext];
    [self.mp4DownloadTask resume];
}

#pragma mark - 进度与清理

// mp4 下载进度:由 countOfBytesReceived 的 KVO 换算真实百分比(上限 99%,落库后补 100%)
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
    if (context == kMP4ProgressKVOContext && object == self.mp4DownloadTask) {
        long long received = self.mp4DownloadTask.countOfBytesReceived;
        long long expected = self.mp4DownloadTask.countOfBytesExpectedToReceive;
        if (expected > 0) {
            float ratio = (float)received / (float)expected;
            if (ratio > 0.99f) ratio = 0.99f;
            VideoDownloadProgressBlock pb = self.mp4ProgressBlock;
            if (pb) {
                dispatch_async(dispatch_get_main_queue(), ^{ pb(ratio); });
            }
        }
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

// 把完成回调统一转到主线程,调用方(视图)可直接刷新 UI
- (void)deliverCompletion:(VideoDownloadCompletionBlock)block success:(BOOL)success path:(NSString * _Nullable)path message:(NSString * _Nullable)message {
    if (!block) return;
    if ([NSThread isMainThread]) {
        block(success, path, message);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{ block(success, path, message); });
    }
}

// 移除 mp4 下载进度观察者、取消并释放任务(幂等)
- (void)removeMp4ProgressObserver {
    if (self.mp4DownloadTask) {
        @try {
            [self.mp4DownloadTask removeObserver:self forKeyPath:@"countOfBytesReceived" context:kMP4ProgressKVOContext];
        } @catch (NSException *ignored) {}
        [self.mp4DownloadTask cancel];
        self.mp4DownloadTask = nil;
    }
    self.mp4ProgressBlock = nil;
}

- (void)cancel {
    [self removeMp4ProgressObserver];
}

// 清理 Caches 里历次转换残留的 mp4,避免占用空间与串扰
- (void)removeOldCachedMP4Files {
    NSURL *cachesURL = [[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] firstObject];
    NSArray<NSURL *> *fileURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:cachesURL
                                                               includingPropertiesForKeys:nil
                                                                                  options:0
                                                                                    error:nil];
    for (NSURL *fileURL in fileURLs) {
        if ([fileURL.pathExtension.lowercaseString isEqualToString:@"mp4"]) {
            [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
        }
    }
}

- (void)dealloc {
    [self removeMp4ProgressObserver];
}

@end
