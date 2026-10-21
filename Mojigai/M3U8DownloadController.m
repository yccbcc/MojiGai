//
//  M3U8DownloadController.m
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/21.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import "M3U8DownloadController.h"
#import "VideoStore.h"
#import "TSToast.h"
#import <AVFoundation/AVFoundation.h>

static void *M3U8StatusContext = &M3U8StatusContext;
static const NSInteger kMaxConcurrentCheck = 4;   // 可播放性预检并发上限
static const NSTimeInterval kCheckTimeout = 6.0;  // 预检超时(秒),超时视为不可用

@interface M3U8DownloadController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
// url -> NSNumber(usable): 有值=检测完成; 无值=未检测或检测中
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *statusDict;
// 检测中的 url -> AVPlayerItem(用于 KVO)
@property (nonatomic, strong) NSMutableDictionary<NSString *, AVPlayerItem *> *checkingItems;
@property (nonatomic, assign) NSInteger checkingCount;
@end

@implementation M3U8DownloadController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    self.statusDict = [NSMutableDictionary dictionary];
    self.checkingItems = [NSMutableDictionary dictionary];

    self.title = @"选择下载";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"取消"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(cancelClick)];

    UITableView *tv = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.dataSource = self;
    tv.delegate = self;
    tv.rowHeight = 96;
    [tv registerClass:[UITableViewCell class] forCellReuseIdentifier:@"M3U8Cell"];
    [self.view addSubview:tv];
    self.tableView = tv;
}

- (void)cancelClick {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 可播放性预检(AVPlayerItem)

// 对某 url 启动预检(仅对可见 cell 懒加载,并发受限)
- (void)checkForURL:(NSString *)url {
    if (self.statusDict[url] || self.checkingItems[url]) return;
    if (self.checkingCount >= kMaxConcurrentCheck) return;   // 达到并发上限,等空闲后 cell 刷新再触发

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:url]];
    [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:M3U8StatusContext];
    self.checkingItems[url] = item;
    self.checkingCount++;

    // 超时兜底:6 秒还没 ready 视为不可用
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kCheckTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf.checkingItems[url]) {
            [strongSelf finishCheckForURL:url usable:NO];
        }
    });
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (context != M3U8StatusContext || ![keyPath isEqualToString:@"status"]) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    AVPlayerItem *item = object;
    __block NSString *foundURL = nil;
    [self.checkingItems enumerateKeysAndObjectsUsingBlock:^(NSString *key, AVPlayerItem *value, BOOL *stop) {
        if (value == item) { foundURL = key; *stop = YES; }
    }];
    if (!foundURL) return;

    if (item.status == AVPlayerItemStatusReadyToPlay) {
        [self finishCheckForURL:foundURL usable:YES];
    } else if (item.status == AVPlayerItemStatusFailed) {
        [self finishCheckForURL:foundURL usable:NO];
    }
    // unknown:继续等待,交给超时兜底
}

- (void)finishCheckForURL:(NSString *)url usable:(BOOL)usable {
    AVPlayerItem *item = self.checkingItems[url];
    if (item) {
        @try {
            [item removeObserver:self forKeyPath:@"status" context:M3U8StatusContext];
        } @catch (NSException *e) {}
        [self.checkingItems removeObjectForKey:url];
        self.checkingCount--;
    }
    self.statusDict[url] = @(usable);

    NSInteger idx = [self.m3u8Urls indexOfObject:url];
    if (idx != NSNotFound) {
        NSIndexPath *ip = [NSIndexPath indexPathForRow:idx inSection:0];
        [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
    }
}

#pragma mark - 下载按钮

- (void)downloadTapped:(UIButton *)btn {
    NSInteger row = btn.tag;
    if (row < 0 || row >= self.m3u8Urls.count) return;
    NSString *url = self.m3u8Urls[row];

    NSNumber *st = self.statusDict[url];
    if (st && !st.boolValue) {
        [TSToast show:@"该地址不可用"];
        return;
    }
    if (!st) {
        // 还在检测中(或排队中):先触发检测并提示等待
        [self checkForURL:url];
        [TSToast show:@"正在检测可用性,请稍候再点"];
        return;
    }

    // 可用 → 弹文件夹选择,确认后回调并关闭本页
    [self presentFolderChoiceForURL:url fromButton:btn];
}

- (void)presentFolderChoiceForURL:(NSString *)url fromButton:(UIButton *)btn {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择保存位置"
                                                                    message:@"保存到 Documents/videos 下的文件夹"
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *folder in [VideoStore folderNames]) {
        NSString *title = [folder isEqualToString:@"default"] ? @"default(默认)" : folder;
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            // 先关掉本页,再回调让调用方真正开始下载
            [self dismissViewControllerAnimated:YES completion:nil];
            if (self.onStartDownload) {
                self.onStartDownload(url, folder);
            }
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = btn;
        sheet.popoverPresentationController.sourceRect = btn.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource / Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.m3u8Urls.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"M3U8Cell" forIndexPath:indexPath];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSString *url = self.m3u8Urls[indexPath.row];

    // 顶部:URL 标题
    UILabel *title = (UILabel *)[cell.contentView viewWithTag:1301];
    if (!title) {
        title = [[UILabel alloc] init];
        title.tag = 1301;
        title.font = [UIFont systemFontOfSize:11];
        title.textColor = UIColor.darkGrayColor;
        title.numberOfLines = 2;
        [cell.contentView addSubview:title];
    }
    title.frame = CGRectMake(12, 6, cell.contentView.bounds.size.width - 110, 34);
    title.text = url;

    // 来源标识(右上角):1=XHR/fetch, 2=媒体元素, 3=HTML解析
    UILabel *srcLabel = (UILabel *)[cell.contentView viewWithTag:1305];
    if (!srcLabel) {
        srcLabel = [[UILabel alloc] init];
        srcLabel.tag = 1305;
        srcLabel.font = [UIFont systemFontOfSize:10];
        srcLabel.textColor = [UIColor colorWithRed:0.40f green:0.55f blue:0.90f alpha:1.00f];
        srcLabel.textAlignment = NSTextAlignmentRight;
        [cell.contentView addSubview:srcLabel];
    }
    srcLabel.frame = CGRectMake(cell.contentView.bounds.size.width - 98, 6, 86, 18);
    NSNumber *src = self.sourceDict[url];
    NSInteger srcVal = src ? src.integerValue : 0;
    switch (srcVal) {
        case 1: srcLabel.text = @"来源: XHR/Fetch"; break;
        case 2: srcLabel.text = @"来源: 媒体元素"; break;
        case 3: srcLabel.text = @"来源: HTML解析"; break;
        default: srcLabel.text = @"来源: 未知"; break;
    }

    // 左下:缩略图占位(方案B:不做真实抽帧,用播放图标占位)
    UIImageView *thumb = (UIImageView *)[cell.contentView viewWithTag:1302];
    if (!thumb) {
        thumb = [[UIImageView alloc] init];
        thumb.tag = 1302;
        thumb.contentMode = UIViewContentModeCenter;
        thumb.backgroundColor = [UIColor colorWithRed:0.92f green:0.92f blue:0.95f alpha:1.00f];
        thumb.layer.cornerRadius = 6;
        thumb.clipsToBounds = YES;
        [cell.contentView addSubview:thumb];
    }
    thumb.frame = CGRectMake(12, 46, 88, 40);
    if (@available(iOS 13.0, *)) {
        thumb.image = [[UIImage systemImageNamed:@"play.rectangle.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        thumb.tintColor = UIColor.lightGrayColor;
    }

    // 状态标记(可用性预检结果)
    UILabel *status = (UILabel *)[cell.contentView viewWithTag:1303];
    if (!status) {
        status = [[UILabel alloc] init];
        status.tag = 1303;
        status.font = [UIFont systemFontOfSize:11];
        [cell.contentView addSubview:status];
    }
    status.frame = CGRectMake(112, 48, 90, 20);
    NSNumber *st = self.statusDict[url];
    if (st) {
        if (st.boolValue) {
            status.text = @"● 可用";
            status.textColor = [UIColor colorWithRed:0.20f green:0.70f blue:0.30f alpha:1.00f];
        } else {
            status.text = @"● 不可用";
            status.textColor = [UIColor colorWithRed:0.90f green:0.30f blue:0.30f alpha:1.00f];
        }
    } else {
        status.text = @"检测中…";
        status.textColor = UIColor.grayColor;
        [self checkForURL:url];   // 懒加载:cell 可见时才预检
    }

    // 右下:下载按钮
    UIButton *btn = (UIButton *)[cell.contentView viewWithTag:1304];
    if (!btn) {
        btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.tag = 1304;
        [btn setTitle:@"下载" forState:UIControlStateNormal];
        [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        btn.backgroundColor = [UIColor colorWithRed:0.20f green:0.47f blue:0.98f alpha:1.00f];
        btn.layer.cornerRadius = 6;
        btn.titleLabel.font = [UIFont systemFontOfSize:13];
        [btn addTarget:self action:@selector(downloadTapped:) forControlEvents:UIControlEventTouchUpInside];
        [cell.contentView addSubview:btn];
    }
    btn.frame = CGRectMake(cell.contentView.bounds.size.width - 76, 62, 64, 28);
    btn.tag = indexPath.row;
    return cell;
}

@end
