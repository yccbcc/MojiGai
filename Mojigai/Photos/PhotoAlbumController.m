//
//  PhotoAlbumController.m
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/16.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import "PhotoAlbumController.h"
#import "ImageManagerController.h"
#import "ImageStore.h"
#import "TSToast.h"

@interface PhotoAlbumController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) NSMutableArray<NSString *> *albumNames;

@end

@implementation PhotoAlbumController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    self.edgesForExtendedLayout = UIRectEdgeNone;
    self.albumNames = [[ImageStore imageSubfolderNames] mutableCopy];
    [self configNavigationBar];
    [self configCollectionView];
}

#pragma mark - UI

- (void)configNavigationBar {
    // 复用真实导航栏:返回由导航控制器自带,"新建"放右侧
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"新建"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(newAlbumClick)];
}

- (void)configCollectionView {
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    CGFloat margin = 12;
    NSInteger columns = 4;   // 文件夹页一行 4 个
    CGFloat itemW = floor((screenW - margin * (columns + 1)) / columns);
    CGFloat itemH = itemW;   // 4 列时单元变窄,改用正方形保证图标与名称都能完整显示

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
    // 长按删除相册
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressCell:)];
    [cv addGestureRecognizer:longPress];
    [cv registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"AlbumCell"];
    [self.view addSubview:cv];
    self.collectionView = cv;

    // 用 Auto Layout 贴安全区,自动扣除导航栏与底部安全区。
    // 原来按 viewDidLoad 时的 view 高度写死 frame,导航栏完成后 view 变矮,相册超过一屏时最后一行会被裁掉
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
    NSString *folder = self.albumNames[ip.item];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除相册"
                                                                  message:[NSString stringWithFormat:@"确定删除相册「%@」及其中的全部图片吗？", folder]
                                                           preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction *del = [UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        if ([ImageStore deleteSubfolder:folder]) {
            self.albumNames = [[ImageStore imageSubfolderNames] mutableCopy];
            [self.collectionView reloadData];
        } else {
            [TSToast show:@"删除失败"];
        }
    }];
    [alert addAction:cancel];
    [alert addAction:del];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)newAlbumClick {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"新建相册" message:@"输入相册名称" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"相册名";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields.firstObject.text;
        if (name.length == 0) {
            [TSToast show:@"请输入相册名称"];
            return;
        }
        if ([ImageStore createSubfolder:name]) {
            self.albumNames = [[ImageStore imageSubfolderNames] mutableCopy];
            [self.collectionView reloadData];
        } else {
            [TSToast show:@"创建失败"];
        }
    }];
    [alert addAction:cancel];
    [alert addAction:ok];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openAlbumAtIndexPath:(NSIndexPath *)indexPath {
    NSString *folder = self.albumNames[indexPath.item];
    ImageManagerController *vc = [[ImageManagerController alloc] init];
    vc.subfolderName = folder;
    vc.title = folder;
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.albumNames.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"AlbumCell" forIndexPath:indexPath];
    cell.contentView.backgroundColor = [UIColor colorWithRed:0.95f green:0.97f blue:1.00f alpha:1.00f];
    cell.layer.cornerRadius = 10;
    cell.layer.masksToBounds = YES;

    UIImageView *icon = [cell.contentView viewWithTag:1001];
    if (!icon) {
        icon = [[UIImageView alloc] init];
        icon.tag = 1001;
        icon.contentMode = UIViewContentModeCenter;
        [cell.contentView addSubview:icon];
    }
    CGFloat cellW = cell.contentView.bounds.size.width;
    CGFloat cellH = cell.contentView.bounds.size.height;
    icon.frame = CGRectMake(0, cellH * 0.10, cellW, cellH * 0.52);   // 4 列窄单元:图标缩小并保持水平居中
    if (@available(iOS 13.0, *)) {
        icon.image = [[UIImage systemImageNamed:@"folder.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        icon.tintColor = [UIColor colorWithRed:0.32f green:0.52f blue:0.90f alpha:1.00f];
    } else {
        icon.image = [UIImage imageNamed:@"folder"];
    }

    UILabel *label = [cell.contentView viewWithTag:1002];
    if (!label) {
        label = [[UILabel alloc] init];
        label.tag = 1002;
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = UIColor.darkGrayColor;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.7;
        [cell.contentView addSubview:label];
    }
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    label.frame = CGRectMake(2, cellH * 0.66, cellW - 4, cellH * 0.28);
    label.text = self.albumNames[indexPath.item];
    return cell;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [self openAlbumAtIndexPath:indexPath];
}

@end
