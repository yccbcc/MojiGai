//
//  ImageManagerController.m
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/15.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import "ImageManagerController.h"
#import "ImagePreviewController.h"
#import "ImageStore.h"
#import "FileTool.h"
#import "TSToast.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface ImageManagerController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UIDocumentPickerDelegate>

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) NSMutableArray<NSString *> *imagePaths;

@end

@implementation ImageManagerController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    // 被 push 进导航控制器:页面从导航栏之下开始,不复用自绘导航栏
    self.edgesForExtendedLayout = UIRectEdgeNone;
    self.imagePaths = [self loadImagePaths];
    [self configNavigationBar];
    [self configCollectionView];
}

// 按子文件夹过滤读取图片路径
- (NSMutableArray<NSString *> *)loadImagePaths {
    if (self.subfolderName.length > 0) {
        return [[ImageStore imagePathsInSubfolder:self.subfolderName] mutableCopy];
    }
    return [[ImageStore allImagePaths] mutableCopy];
}

#pragma mark - UI

- (void)configNavigationBar {
    // 复用真实导航栏:返回由导航控制器自带,"导入"放右侧
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"导入"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(importClick)];
}

- (void)configCollectionView {
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    CGFloat margin = 2;
    NSInteger columns = 3;
    CGFloat itemW = floor((screenW - margin * (columns + 1)) / columns);

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = CGSizeMake(itemW, itemW);
    layout.minimumLineSpacing = margin;
    layout.minimumInteritemSpacing = margin;
    layout.sectionInset = UIEdgeInsetsMake(margin, margin, margin, margin);

    // 页面已在导航栏之下,网格从顶部开始铺满
    UICollectionView *cv = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 0, screenW, self.view.bounds.size.height) collectionViewLayout:layout];
    cv.backgroundColor = UIColor.whiteColor;
    cv.dataSource = self;
    cv.delegate = self;
    // 长按删除照片
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressCell:)];
    [cv addGestureRecognizer:longPress];
    [cv registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"ImageCell"];
    [self.view addSubview:cv];
    self.collectionView = cv;
}

#pragma mark - 事件

- (void)longPressCell:(UILongPressGestureRecognizer *)lp {
    if (lp.state != UIGestureRecognizerStateBegan) return;
    CGPoint p = [lp locationInView:self.collectionView];
    NSIndexPath *ip = [self.collectionView indexPathForItemAtPoint:p];
    if (!ip) return;
    NSString *path = self.imagePaths[ip.item];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除照片" message:@"确定删除这张照片吗？" preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction *del = [UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        if ([ImageStore deleteImageAtPath:path]) {
            self.imagePaths = [self loadImagePaths];
            [self.collectionView reloadData];
        } else {
            [TSToast show:@"删除失败"];
        }
    }];
    [alert addAction:cancel];
    [alert addAction:del];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)backClick {
    if (self.navigationController) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)importClick {
    // 打开系统「文件」App，支持多选图片；asCopy:YES 让其先拷进 App 沙盒
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.imagePaths.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ImageCell" forIndexPath:indexPath];
    UIImageView *imageView = [cell.contentView viewWithTag:999];
    if (!imageView) {
        imageView = [[UIImageView alloc] initWithFrame:cell.contentView.bounds];
        imageView.tag = 999;
        imageView.contentMode = UIViewContentModeScaleAspectFill;
        imageView.clipsToBounds = YES;
        [cell.contentView addSubview:imageView];
    }
    imageView.frame = cell.contentView.bounds;
    // 列表用缩略图，避免直接加载原图
    imageView.image = [ImageStore thumbnailForPath:self.imagePaths[indexPath.item] maxPixel:300];
    return cell;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    ImagePreviewController *preview = [[ImagePreviewController alloc] init];
    preview.imagePaths = self.imagePaths;
    preview.index = indexPath.item;
    preview.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:preview animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) {
        return;
    }
    NSInteger failed = 0;
    for (NSURL *url in urls) {
        NSError *error = nil;
        NSString *stored = nil;
        // 有子文件夹时导入到该文件夹,否则导入到 Images 根目录
        if (self.subfolderName.length > 0) {
            stored = [ImageStore saveImageFromURL:url intoDirectory:[ImageStore subfolderPath:self.subfolderName] error:&error];
        } else {
            stored = [ImageStore saveImageFromURL:url error:&error];
        }
        if (!stored) {
            failed++;
            NSLog(@"导入图片失败: %@", error);
        } else {
            // 清理导入产生的临时文件(系统可能放在 Documents/Inbox 或 Documents 根目录),避免留孤儿;
            // 只清理 Documents 下的非业务文件夹,绝不碰 txts/images/videos/file_app 等业务数据
            if ([FileTool isImportedStagingCleanableAtPath:url.path]) {
                [FileTool deleteAtPath:url.path error:nil];
            }
        }
    }
    self.imagePaths = [self loadImagePaths];
    [self.collectionView reloadData];

    if (failed == urls.count) {
        [TSToast show:@"图片导入失败"];
    } else if (failed > 0) {
        [TSToast show:[NSString stringWithFormat:@"部分图片导入失败(%ld)", (long)failed]];
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    NSLog(@"取消导入图片");
}

@end