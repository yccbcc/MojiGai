//
//  ImagePreviewController.m
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/15.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import "ImagePreviewController.h"
#import <YBImageBrowser/YBImageBrowser.h>

// 微信朋友圈式浏览(双指/双击缩放、下拉关闭、左右翻页)由 YBImageBrowser 提供,
// 本页只做适配:把 imagePaths 本地路径数组转成它的数据源,并在其关闭后收起自身
@interface ImagePreviewController () <YBImageBrowserDelegate>

@property (nonatomic, strong) YBImageBrowser *browser;

@end

@implementation ImagePreviewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    if (self.imagePaths.count == 0) {
        return;
    }
    if (self.index < 0 || self.index >= self.imagePaths.count) {
        self.index = 0;
    }

    NSMutableArray<YBIBImageData *> *datas = [NSMutableArray array];
    for (NSString *path in self.imagePaths) {
        YBIBImageData *data = [YBIBImageData new];
        data.imageURL = [NSURL fileURLWithPath:path];
        [datas addObject:data];
    }

    YBImageBrowser *browser = [YBImageBrowser new];
    browser.delegate = self;
    browser.dataSourceArray = datas;
    browser.currentPage = self.index;
    [browser showToView:self.view];
    self.browser = browser;
}

#pragma mark - YBImageBrowserDelegate

// 下拉关闭(或工具条关闭)的隐藏转场结束后,收起承载控制器
- (void)yb_imageBrowser:(YBImageBrowser *)imageBrowser endTransitioningWithIsShow:(BOOL)isShow {
    if (!isShow) {
        [self dismissViewControllerAnimated:NO completion:nil];
    }
}

@end
