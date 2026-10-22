//
//  M3U8DownloadController.m
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/21.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import "M3U8DownloadController.h"
#import "VideoStore.h"

@interface M3U8DownloadController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation M3U8DownloadController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;

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

#pragma mark - 下载按钮

- (void)downloadTapped:(UIButton *)btn {
    NSInteger row = btn.tag;
    if (row < 0 || row >= self.m3u8Urls.count) return;
    NSString *url = self.m3u8Urls[row];

    // 弹文件夹选择,确认后回调并关闭本页
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
