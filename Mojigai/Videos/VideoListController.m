//
//  VideoListController.m
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/16.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import "VideoListController.h"
#import "VideoPreviewController.h"
#import "VideoMoveController.h"
#import "VideoStore.h"
#import "FileTool.h"
#import "TSToast.h"
#import <AVFoundation/AVFoundation.h>

@interface VideoListController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) NSMutableArray<NSString *> *videoPaths;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *thumbCache;

@end

@implementation VideoListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    self.edgesForExtendedLayout = UIRectEdgeNone;
    self.thumbCache = [[NSCache alloc] init];
    self.videoPaths = [[VideoStore videoPathsInFolder:self.folderName] mutableCopy];
    [self configCollectionView];
    [self reloadDataIfNeeded];   // 回到页面时刷新(可能有新下载的视频)
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadDataIfNeeded];
}

// 数据变了才刷新,避免每次进入都重排
- (void)reloadDataIfNeeded {
    NSArray<NSString *> *latest = [VideoStore videoPathsInFolder:self.folderName];
    if (![latest isEqualToArray:self.videoPaths]) {
        self.videoPaths = [latest mutableCopy];
        [self.collectionView reloadData];
    }
}

#pragma mark - UI

- (void)configCollectionView {
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    CGFloat margin = 8;
    NSInteger columns = 2;
    CGFloat itemW = floor((screenW - margin * (columns + 1)) / columns);
    CGFloat itemH = itemW * 0.72;

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = CGSizeMake(itemW, itemH);
    layout.minimumLineSpacing = margin;
    layout.minimumInteritemSpacing = margin;
    layout.sectionInset = UIEdgeInsetsMake(margin, margin, margin, margin);

    UICollectionView *cv = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    cv.translatesAutoresizingMaskIntoConstraints = NO;
    cv.backgroundColor = UIColor.whiteColor;
    cv.dataSource = self;
    cv.delegate = self;
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressCell:)];
    [cv addGestureRecognizer:longPress];
    [cv registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"VideoCell"];
    [self.view addSubview:cv];
    self.collectionView = cv;

    // 用 Auto Layout 贴安全区,自动扣除导航栏与底部安全区,避免列表超出屏幕/回弹
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [cv.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [cv.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
        [cv.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [cv.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
    ]];
}

#pragma mark - 事件

- (void)longPressCell:(UILongPressGestureRecognizer *)lp {
    if (lp.state != UIGestureRecognizerStateBegan) return;
    CGPoint p = [lp locationInView:self.collectionView];
    NSIndexPath *ip = [self.collectionView indexPathForItemAtPoint:p];
    if (!ip) return;
    NSString *path = self.videoPaths[ip.item];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[path lastPathComponent]
                                                                    message:nil
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *rename = [UIAlertAction actionWithTitle:@"重命名" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self renameVideoAtPath:path];
    }];
    UIAlertAction *export = [UIAlertAction actionWithTitle:@"导出到文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self exportVideoAtPath:path];
    }];
    UIAlertAction *move = [UIAlertAction actionWithTitle:@"移动" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self moveVideoAtPath:path];
    }];
    UIAlertAction *del = [UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self confirmDeleteVideoAtPath:path];
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    [sheet addAction:rename];
    [sheet addAction:export];
    [sheet addAction:move];
    [sheet addAction:del];
    [sheet addAction:cancel];
    // iPad 适配:actionSheet 必须指定 popover 锚点
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.collectionView;
        sheet.popoverPresentationController.sourceRect = CGRectMake(p.x, p.y, 1, 1);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

// 导出到系统「文件」App(用户自选位置)
- (void)exportVideoAtPath:(NSString *)path {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithURL:[NSURL fileURLWithPath:path] inMode:UIDocumentPickerModeExportToService];
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

// 移动:present 文件夹选择控制器,确认后把视频移到目标文件夹
- (void)moveVideoAtPath:(NSString *)path {
    VideoMoveController *move = [[VideoMoveController alloc] init];
    move.videoPath = path;
    move.currentFolderName = self.folderName;
    __weak typeof(self) weakSelf = self;
    move.onMoved = ^(NSString *folderName) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        // 路径变了,清理旧路径封面缓存(封面按路径 hash 命名)
        [strongSelf removeThumbForPath:path];
        strongSelf.videoPaths = [[VideoStore videoPathsInFolder:strongSelf.folderName] mutableCopy];
        [strongSelf.collectionView reloadData];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:move];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

// 重命名:弹输入框,保留原扩展名,重名/非法名拒绝
- (void)renameVideoAtPath:(NSString *)path {
    NSString *oldName = [path lastPathComponent];
    NSString *base = [oldName stringByDeletingPathExtension];
    NSString *ext = [oldName pathExtension];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重命名" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = base;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *newBase = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (newBase.length == 0) {
            [TSToast show:@"名称不能为空"];
            return;
        }
        // 去除文件系统非法字符
        NSCharacterSet *illegal = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
        newBase = [[newBase componentsSeparatedByCharactersInSet:illegal] componentsJoinedByString:@""];
        NSString *newName = (ext.length > 0)
            ? [newBase stringByAppendingPathExtension:ext]
            : newBase;
        if ([newName isEqualToString:oldName]) return;   // 名称没变
        NSString *newPath = [[VideoStore folderPath:self.folderName] stringByAppendingPathComponent:newName];
        if ([FileTool existsAtPath:newPath]) {
            [TSToast show:@"已存在同名文件"];
            return;
        }
        NSError *err = nil;
        if ([FileTool moveFromPath:path toPath:newPath error:&err]) {
            [self removeThumbForPath:path];   // 清理旧路径封面缓存(路径 hash 已变)
            self.videoPaths = [[VideoStore videoPathsInFolder:self.folderName] mutableCopy];
            [self.collectionView reloadData];
        } else {
            [TSToast show:[NSString stringWithFormat:@"重命名失败: %@", err.localizedDescription]];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDeleteVideoAtPath:(NSString *)path {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除视频" message:@"确定删除这个视频吗？" preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction *del = [UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        if ([VideoStore deleteVideoAtPath:path]) {
            [self removeThumbForPath:path];   // 同步清理封面缓存
            self.videoPaths = [[VideoStore videoPathsInFolder:self.folderName] mutableCopy];
            [self.collectionView reloadData];
        } else {
            [TSToast show:@"删除失败"];
        }
    }];
    [alert addAction:cancel];
    [alert addAction:del];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.videoPaths.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"VideoCell" forIndexPath:indexPath];
    cell.contentView.backgroundColor = [UIColor colorWithRed:0.95f green:0.95f blue:0.97f alpha:1.00f];
    cell.layer.cornerRadius = 10;
    cell.layer.masksToBounds = YES;

    // 封面区:有封面显示封面,没有则显示播放图标占位
    UIImageView *cover = [cell.contentView viewWithTag:1201];
    if (!cover) {
        cover = [[UIImageView alloc] init];
        cover.tag = 1201;
        cover.clipsToBounds = YES;
        [cell.contentView addSubview:cover];
    }
    cover.frame = CGRectMake(0, 0, cell.contentView.bounds.size.width, cell.contentView.bounds.size.height - 34);

    NSString *path = self.videoPaths[indexPath.item];
    UIImage *thumb = [self thumbImageForPath:path];
    if (thumb) {
        cover.contentMode = UIViewContentModeScaleAspectFill;
        cover.image = thumb;
    } else {
        cover.contentMode = UIViewContentModeCenter;
        if (@available(iOS 13.0, *)) {
            cover.image = [[UIImage systemImageNamed:@"play.circle.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            cover.tintColor = [UIColor colorWithRed:0.90f green:0.32f blue:0.29f alpha:1.00f];
        }
        // 异步生成封面,完成后若 cell 仍可见则更新
        [self loadThumbForPath:path atIndexPath:indexPath];
    }

    UILabel *label = [cell.contentView viewWithTag:1202];
    if (!label) {
        label = [[UILabel alloc] init];
        label.tag = 1202;
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont systemFontOfSize:12];
        label.textColor = UIColor.darkGrayColor;
        label.numberOfLines = 2;
        [cell.contentView addSubview:label];
    }
    label.frame = CGRectMake(6, cell.contentView.bounds.size.height - 30, cell.contentView.bounds.size.width - 12, 26);
    label.text = [path lastPathComponent];
    return cell;
}

#pragma mark - 封面抽帧

// 封面缓存:内存 NSCache + 磁盘 Caches/VideoThumbs(可被系统清理,丢失后重新生成)
- (UIImage *)thumbImageForPath:(NSString *)path {
    UIImage *cached = [self.thumbCache objectForKey:path];
    if (cached) return cached;
    NSString *diskPath = [self thumbDiskPathForPath:path];
    if ([FileTool existsAtPath:diskPath]) {
        UIImage *img = [UIImage imageWithContentsOfFile:diskPath];
        if (img) {
            [self.thumbCache setObject:img forKey:path];
            return img;
        }
    }
    return nil;
}

- (NSString *)thumbDiskPathForPath:(NSString *)path {
    NSString *dir = [[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] firstObject].path;
    dir = [FileTool ensureDirectory:[dir stringByAppendingPathComponent:@"VideoThumbs"]];
    return [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%lu.jpg", (unsigned long)[path hash]]];
}

// 删除某视频路径对应的封面缓存(磁盘文件 + 内存缓存),避免重命名/删除后残留孤儿封面
- (void)removeThumbForPath:(NSString *)path {
    NSString *diskPath = [self thumbDiskPathForPath:path];
    if ([FileTool existsAtPath:diskPath]) {
        [FileTool deleteAtPath:diskPath error:nil];
    }
    [self.thumbCache removeObjectForKey:path];
}

- (void)loadThumbForPath:(NSString *)path atIndexPath:(NSIndexPath *)indexPath {
    if ([self thumbImageForPath:path]) return;   // 已有封面
    __weak typeof(self) weakSelf = self;

    void (^finish)(CGImageRef) = ^(CGImageRef image) {
        [weakSelf handleThumbImage:image forPath:path atIndexPath:indexPath];
    };

    AVURLAsset *asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:path]];
    AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    gen.appliesPreferredTrackTransform = YES;
    gen.maximumSize = CGSizeMake(400, 400);
    // 取 0.1s 处;部分视频第一帧偏黑,失败则另起生成器取 1s 处
    [gen generateCGImageAsynchronouslyForTime:CMTimeMakeWithSeconds(0.1, 600) completionHandler:^(CGImageRef image, CMTime actualTime, NSError *error) {
        if (image) {
            finish(image);
            return;
        }
        AVAssetImageGenerator *gen2 = [[AVAssetImageGenerator alloc] initWithAsset:asset];
        gen2.appliesPreferredTrackTransform = YES;
        gen2.maximumSize = CGSizeMake(400, 400);
        [gen2 generateCGImageAsynchronouslyForTime:CMTimeMakeWithSeconds(1.0, 600) completionHandler:^(CGImageRef image2, CMTime actualTime2, NSError *error2) {
            if (image2) {
                finish(image2);
            }
        }];
    }];
}

- (void)handleThumbImage:(CGImageRef)cg forPath:(NSString *)path atIndexPath:(NSIndexPath *)indexPath {
    if (!cg) return;
    UIImage *img = [[UIImage alloc] initWithCGImage:cg];
    NSData *jpg = UIImageJPEGRepresentation(img, 0.7);
    [jpg writeToFile:[self thumbDiskPathForPath:path] atomically:YES];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.thumbCache setObject:img forKey:path];
        UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];
        UIImageView *cv = (UIImageView *)[cell.contentView viewWithTag:1201];
        if (cv) {
            cv.contentMode = UIViewContentModeScaleAspectFill;
            cv.image = img;
        }
    });
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    VideoPreviewController *preview = [[VideoPreviewController alloc] init];
    preview.videoPath = self.videoPaths[indexPath.item];
    preview.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:preview animated:YES completion:nil];
}

@end
