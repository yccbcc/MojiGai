//
//  WebBrowserView.h
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/19.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 可复用的网页浏览视图:内含顶部操作行 + WKWebView + 下拉刷新 + 右滑返回网页 + m3u8 下载。
/// 全 app 共用单例,挂到 key window 显示;Editor / Main / Source 打开的是同一个实例,保留网页状态。
@interface WebBrowserView : UIView

/// 关闭回调(右滑无上一页时触发;单例模式下默认调用 hide)。
@property (nonatomic, copy, nullable) void (^onClose)(void);

/// 全局单例网页视图(Editor / Main 共用同一实例,打开关闭保留网页状态)。
+ (instancetype)sharedBrowser;

/// 把网页视图挂到 key window 全屏显示;再次调用直接复用原实例,不重新加载 URL。
+ (void)showOnWindow;

/// 挂到 window 显示并加载指定网址(用于从外部传入具体链接,如 Source 里的 http 条目)。
+ (void)showOnWindowWithURL:(NSString *)urlString;

/// 从 window 移除(隐藏),实例保留。
- (void)hide;

/// 首次显示时若尚未加载任何页面,加载上次记住的 URL。宿主在 viewDidLoad 调用一次即可。
- (void)loadSavedURLIfNeeded;

/// 当前是否有网页上一页
@property (nonatomic, readonly) BOOL canGoBack;

@end

NS_ASSUME_NONNULL_END
