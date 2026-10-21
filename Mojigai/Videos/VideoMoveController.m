//
//  VideoMoveController.m
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/21.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import "VideoMoveController.h"
#import "VideoStore.h"
#import "TSToast.h"

@interface VideoMoveController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) NSArray<NSString *> *folders;   // 候选文件夹(已排除当前文件夹)
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIBarButtonItem *moveItem;
@property (nonatomic, copy, nullable) NSString *selectedFolder;
@end

@implementation VideoMoveController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;

    // 候选 = 全部文件夹 减去 当前文件夹
    NSMutableArray *folders = [[VideoStore folderNames] mutableCopy];
    if (self.currentFolderName.length > 0) {
        [folders removeObject:self.currentFolderName];
    }
    self.folders = [folders copy];

    // 导航栏:标题默认"移动视频",选中后变为所选文件夹名;左取消、右移动
    self.title = @"移动视频";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"取消"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(cancelClick)];
    self.moveItem = [[UIBarButtonItem alloc] initWithTitle:@"移动"
                                                     style:UIBarButtonItemStyleDone
                                                    target:self
                                                    action:@selector(moveClick)];
    self.moveItem.enabled = NO;
    self.navigationItem.rightBarButtonItem = self.moveItem;

    UITableView *tv = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.dataSource = self;
    tv.delegate = self;
    [tv registerClass:[UITableViewCell class] forCellReuseIdentifier:@"FolderCell"];
    [self.view addSubview:tv];
    self.tableView = tv;
}

- (void)cancelClick {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// 执行移动:移动到所选文件夹;成功回调并关闭,失败留在本页
- (void)moveClick {
    if (self.selectedFolder.length == 0 || self.videoPath.length == 0) {
        return;
    }
    NSString *targetDir = [VideoStore folderPath:self.selectedFolder];
    NSString *newPath = [targetDir stringByAppendingPathComponent:[self.videoPath lastPathComponent]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:newPath]) {
        [TSToast show:@"目标文件夹已有同名文件"];
        return;
    }
    NSError *err = nil;
    if ([[NSFileManager defaultManager] moveItemAtPath:self.videoPath toPath:newPath error:&err]) {
        [TSToast show:@"已移动"];
        if (self.onMoved) {
            self.onMoved(self.selectedFolder);
        }
        [self dismissViewControllerAnimated:YES completion:nil];
    } else {
        [TSToast show:[NSString stringWithFormat:@"移动失败: %@", err.localizedDescription]];
    }
}

#pragma mark - UITableViewDataSource / Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.folders.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"FolderCell" forIndexPath:indexPath];
    NSString *name = self.folders[indexPath.row];
    cell.textLabel.text = [name isEqualToString:@"default"] ? @"default(默认)" : name;
    BOOL isSel = [name isEqualToString:self.selectedFolder];
    cell.accessoryType = isSel ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.tintColor = [UIColor colorWithRed:0.20f green:0.47f blue:0.98f alpha:1.00f];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    self.selectedFolder = self.folders[indexPath.row];
    self.moveItem.enabled = YES;
    self.title = self.selectedFolder;   // 导航栏名称 = 所选文件夹名
    [self.tableView reloadData];
}

@end
