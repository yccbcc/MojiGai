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
    // 库内部对 projectiveView 为 nil 时仍会截图(得到 {0,0} 上下文),iOS 27 下会直接断言崩溃,
    // 所以必须保证每个 data 都挂上一个非空的来源视图:优先用列表缩略图,否则用全屏占位视图
    UIView *sourceView = self.sourceView ?: [self makeFallbackSourceView];
    for (NSString *path in self.imagePaths) {
        YBIBImageData *data = [YBIBImageData new];
        data.imageURL = [NSURL fileURLWithPath:path];
        data.projectiveView = sourceView;
        [datas addObject:data];
    }

    YBImageBrowser *browser = [YBImageBrowser new];
    browser.delegate = self;
    // 库靠 isStatusBarHidden/statusBarOrientation 隐藏状态栏,iOS 27 上这两个 API 已变成 no-op(只刷废弃日志),直接关掉
    browser.shouldHideStatusBar = NO;
    browser.dataSourceArray = datas;
    browser.currentPage = self.index;
    [browser showToView:self.view];
    self.browser = browser;
}

// 无缩略图可当转场来源时的兜底:一个透明占位视图,仅用于避开库的 nil 截图崩溃
- (UIView *)makeFallbackSourceView {
    UIView *placeholder = [[UIView alloc] initWithFrame:self.view.bounds];
    placeholder.backgroundColor = UIColor.clearColor;
    [self.view addSubview:placeholder];
    return placeholder;
}

#pragma mark - YBImageBrowserDelegate

// 下拉关闭(或工具条关闭)的隐藏转场结束后,收起承载控制器
- (void)yb_imageBrowser:(YBImageBrowser *)imageBrowser endTransitioningWithIsShow:(BOOL)isShow {
    if (!isShow) {
        [self dismissViewControllerAnimated:NO completion:nil];
    }
}

@end
