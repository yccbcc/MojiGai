//
//  WebBrowserView.m
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/19.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import "WebBrowserView.h"
#import <WebKit/WebKit.h>
#import "TSWebView.h"
#import "HTMLTextTool.h"
#import "ConvertVideoFormat.h"
#import "VideoStore.h"
#import "TSToast.h"

@interface WebBrowserView () <WKUIDelegate, WKNavigationDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) TSWebView *wkWeb;
// m3u8 下载候选列表(点「下载」时展示),URL 自动去重。由两个采集点共同填充:
//
// ① 网页网络请求监听 —— onNetworkRequest 过滤注入 JS 的上报后加入
//    上报来源: XHR / fetch / 媒体元素 src(注入脚本统一经 messageHandlers 上报)
//    命中条件(任一):
//      - URL 含 .m3u8 或 .m3
//      - 响应体以 #EXTM3U 或 #EXT-X- 开头(即使 URL 不像 m3u8,只要内容是 HLS 播放列表)
//    注: 媒体元素消息的响应体为 nil,只能按 URL 判断;因注入脚本只上报 m3u8 地址,必然命中。
//
// ② 网页 HTML 解析 —— downloadClick 里从 document.documentElement.innerHTML 提取 video/source 的 src
@property (nonatomic, strong) NSMutableArray<NSString *> *m3u8UrlArray;
@property (nonatomic, copy) NSString *pageHTMLString;
@property (nonatomic, copy) NSString *resultString;
@end

@implementation WebBrowserView
{
    NSMutableArray *_controlBtns;
    UIView *_controlBar;
    UIScreenEdgePanGestureRecognizer *_edgeGesture;
    BOOL _didLoadInitial;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [UIColor whiteColor];

    // 顶部操作行:所有按钮放进一个容器 view,统一背景色
    _controlBtns = [NSMutableArray array];
    UIView *controlBar = [[UIView alloc] initWithFrame:CGRectZero];
    controlBar.backgroundColor = [UIColor colorWithRed:1.00f green:0.99f blue:0.92f alpha:1.00f];
    [self addSubview:controlBar];
    _controlBar = controlBar;

    NSArray *titles  = @[@"上一页", @"URL", @"主页", @"关闭", @"copy", @"下载", @"下一页"];
    NSArray *tags    = @[@200, @251, @252, @250, @202, @203, @201];
    NSArray *actions = @[
        NSStringFromSelector(@selector(directedClick:)),
        NSStringFromSelector(@selector(urlClick)),
        NSStringFromSelector(@selector(homeClick)),
        NSStringFromSelector(@selector(closeClick)),
        NSStringFromSelector(@selector(copyClick:)),
        NSStringFromSelector(@selector(downloadClick:)),
        NSStringFromSelector(@selector(directedClick:)),
    ];
    for (NSInteger i = 0; i < titles.count; i++) {
        UIButton *b = [[UIButton alloc] initWithFrame:CGRectZero];
        b.tag = [tags[i] integerValue];
        [b setTitle:titles[i] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor colorWithRed:0.20f green:0.47f blue:0.98f alpha:1.00f] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
        [b setBackgroundImage:[UIImage imageNamed:@"redImage.png"] forState:UIControlStateHighlighted];
        b.titleLabel.font = [UIFont systemFontOfSize:13];
        b.titleLabel.adjustsFontSizeToFitWidth = YES;
        b.titleLabel.minimumScaleFactor = 0.8;
        b.backgroundColor = [UIColor clearColor];
        b.layer.cornerRadius = 8.0;
        b.clipsToBounds = YES;
        SEL sel = NSSelectorFromString(actions[i]);
        [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
        [controlBar addSubview:b];
        [_controlBtns addObject:b];
    }

    // 网页视图:位于顶部操作行之下
    __weak typeof(self) weakSelf = self;
    TSWebView *wkWeb = [[TSWebView alloc] initWithFrame:CGRectZero configuration:[[WKWebViewConfiguration alloc] init]];
    wkWeb.UIDelegate = self;
    wkWeb.navigationDelegate = self;
    wkWeb.onNetworkRequest = ^(TSNetworkRequestInfo *request) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!request || request.url.length == 0) return;

        // 来源①:网页网络请求监听(注入 JS 上报 XHR / fetch / 媒体元素 src),在此过滤出 m3u8 候选。
        // 放宽捕获条件(相比原来只认 ".m3u8" 字符串):
        //  ① URL 含 .m3u8 / .m3 —— 覆盖带 token / 无扩展名地址;媒体元素 src(type==media) 因注入脚本
        //     postMedia 只上报 m3u8 地址,其 URL 必然命中这里,无需单独判断
        //  ② 响应体以 #EXTM3U / #EXT-X- 开头 —— HLS 播放列表铁证,覆盖 URL 不带 m3u8 的接口加载
        NSString *urlString = request.url;
        NSString *lower = [urlString lowercaseString];
        NSString *trimmedResponse = [request.response stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        BOOL isM3U8ByURL = ([lower containsString:@".m3u8"] || [lower containsString:@".m3u"]);
        BOOL isM3U8ByResponse = ([trimmedResponse hasPrefix:@"#EXTM3U"] || [trimmedResponse hasPrefix:@"#EXT-X-"]);

        if (isM3U8ByURL || isM3U8ByResponse) {
            if (!strongSelf.m3u8UrlArray) {
                strongSelf.m3u8UrlArray = [NSMutableArray array];
            }
            if (![strongSelf.m3u8UrlArray containsObject:urlString]) {
                [strongSelf.m3u8UrlArray addObject:urlString];
                NSLog(@"捕获 m3u8: %@", urlString);
            }
        }
    };
    [self addSubview:wkWeb];
    _wkWeb = wkWeb;

    // 下拉刷新(替代「刷新」按钮)
    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self action:@selector(reloadClick) forControlEvents:UIControlEventValueChanged];
    wkWeb.scrollView.refreshControl = refresh;

    // 右滑手势:有网页历史时返回网页上一页,否则触发 onClose(由宿主决定 pop/隐藏)
    UIScreenEdgePanGestureRecognizer *edge = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(edgeSwipe:)];
    edge.edges = UIRectEdgeLeft;
    [self addGestureRecognizer:edge];
    _edgeGesture = edge;
}

#pragma mark - 布局

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat barH = 50;
    CGFloat safeTop = self.safeAreaInsets.top;
    CGFloat safeBottom = self.safeAreaInsets.bottom;

    _controlBar.frame = CGRectMake(0, safeTop, w, barH);
    CGFloat space = 5;
    CGFloat btnW = (w - 6 * space) / 7.0;   // 7 个按钮(上一页/URL/主页/关闭/copy/下载/下一页)
    CGFloat btnH = barH - 12;
    for (NSInteger i = 0; i < _controlBtns.count; i++) {
        UIButton *b = _controlBtns[i];
        b.frame = CGRectMake(i * (btnW + space), (barH - btnH) / 2.0, btnW, btnH);
    }

    _wkWeb.frame = CGRectMake(0, safeTop + barH, w, h - safeTop - barH - safeBottom);
}

#pragma mark - 全局单例(挂到 window)

+ (instancetype)sharedBrowser {
    static WebBrowserView *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[WebBrowserView alloc] initWithFrame:CGRectZero];
        __weak typeof(s) weakS = s;
        s.onClose = ^{
            __strong typeof(weakS) strongS = weakS;
            [strongS hide];
        };
    });
    return s;
}

+ (void)showOnWindow {
    WebBrowserView *b = [WebBrowserView sharedBrowser];
    UIWindow *win = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { win = w; break; }
    }
    if (!win) {
        win = [UIApplication sharedApplication].windows.firstObject;
    }
    if (!win) return;

    b.frame = win.bounds;
    b.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    if (b.superview != win) {
        [win addSubview:b];
    }
    [b loadSavedURLIfNeeded];
}

- (void)hide {
    if (self.superview) {
        [self removeFromSuperview];
    }
}

+ (void)showOnWindowWithURL:(NSString *)urlString {
    WebBrowserView *b = [WebBrowserView sharedBrowser];
    [WebBrowserView showOnWindow];
    if (urlString.length > 0) {
        [b loadURL:urlString];
    }
}

#pragma mark - 首次加载

- (void)loadSavedURLIfNeeded {
    if (_didLoadInitial) {
        return;
    }
    _didLoadInitial = YES;
    NSString *savedURL = [[NSUserDefaults standardUserDefaults] stringForKey:@"lastWebURL"];
    if (savedURL.length > 0) {
        [self loadURL:savedURL];
    }
}

#pragma mark - 右滑手势(网页返回优先)

// 边缘滑动:有网页上一页则返回网页上一页(并记录该页),否则触发 onClose
- (void)edgeSwipe:(UIScreenEdgePanGestureRecognizer *)gr {
    if (gr.state == UIGestureRecognizerStateEnded || gr.state == UIGestureRecognizerStateRecognized) {
        if ([self.wkWeb canGoBack]) {
            // goBack 目标页可能走缓存不触发 didFinishNavigation,提前记录要返回的那一页
            WKBackForwardListItem *backItem = self.wkWeb.backForwardList.backItem;
            if (backItem.URL.absoluteString.length > 0) {
                [[NSUserDefaults standardUserDefaults] setObject:backItem.URL.absoluteString forKey:@"lastWebURL"];
            }
            [self.wkWeb goBack];
        } else if (self.onClose) {
            self.onClose();
        }
    }
}

- (BOOL)canGoBack {
    return self.wkWeb.canGoBack;
}

#pragma mark - 地址栏

// 加载地址并记住,供下次进入时恢复
- (void)loadURL:(NSString *)urlString {
    urlString = [urlString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (urlString.length == 0) {
        return;
    }
    // 无 scheme 时自动补 https://
    if (![urlString hasPrefix:@"http://"] && ![urlString hasPrefix:@"https://"]) {
        urlString = [NSString stringWithFormat:@"https://%@", urlString];
    }
    [_wkWeb loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlString]]];
    [[NSUserDefaults standardUserDefaults] setObject:urlString forKey:@"lastWebURL"];
}

#pragma mark - 顶部操作行事件

// 主页:打开 Google
- (void)homeClick {
    [self loadURL:@"https://www.google.com.hk"];
}

// 关闭:单例模式交给 onClose(默认 hide 移除出 window)
- (void)closeClick {
    if (self.onClose) {
        self.onClose();
    }
}

// URL:弹窗输入网址(textview + 确定),网址有变化则加载新网址
- (void)urlClick {
    UIViewController *parent = [self parentViewController];
    if (!parent) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"输入网址"
                                                                    message:nil
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.hidden = YES;
    }];

    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectZero];
    tv.layer.borderColor = [UIColor lightGrayColor].CGColor;
    tv.layer.borderWidth = 0.5;
    tv.layer.cornerRadius = 6;
    tv.font = [UIFont systemFontOfSize:14];
    tv.text = self.wkWeb.URL.absoluteString ?: @"";
    tv.tag = 901;
    [alert.view addSubview:tv];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        UITextView *input = (UITextView *)[alert.view viewWithTag:901];
        NSString *newURL = [input.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *current = strongSelf.wkWeb.URL.absoluteString ?: @"";
        NSCharacterSet *slash = [NSCharacterSet characterSetWithCharactersInString:@"/"];
        NSString *n1 = [newURL stringByTrimmingCharactersInSet:slash];
        NSString *n2 = [current stringByTrimmingCharactersInSet:slash];
        if (newURL.length > 0 && ![n1 isEqualToString:n2]) {
            [strongSelf loadURL:newURL];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    [parent presentViewController:alert animated:YES completion:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        UITextView *input = (UITextView *)[alert.view viewWithTag:901];
        CGFloat tw = alert.view.bounds.size.width - 32;
        input.frame = CGRectMake(16, 60, tw, 64);
        [input becomeFirstResponder];
    }];
}

- (void)directedClick:(UIButton *)btn {
    if (btn.tag == 200) {
        if ([self.wkWeb canGoBack]) {
            [self.wkWeb goBack];
        }
    } else {
        if ([self.wkWeb canGoForward]) {
            [self.wkWeb goForward];
        }
    }
}

- (void)copyClick:(UIButton *)btn {
    if (self.resultString.length > 0) {
        [UIPasteboard generalPasteboard].string = self.resultString;
        [TSToast show:@"已复制"];
    } else {
        [TSToast show:@"暂无内容"];
    }
}

// 刷新(下拉刷新触发;同时清空捕获的 m3u8 列表)
- (void)reloadClick {
    [self.m3u8UrlArray removeAllObjects];
    [self.wkWeb reload];
}

// 刷新指示器收尾
- (void)endRefresh {
    UIRefreshControl *rc = self.wkWeb.scrollView.refreshControl;
    if (rc && rc.refreshing) {
        [rc endRefreshing];
    }
}

#pragma mark - 下载(m3u8 -> mp4)

// 递归查找指定 tag 的按钮(按钮在 _controlBar 容器内)
- (UIButton *)findButtonWithTag:(NSInteger)tag inView:(UIView *)view {
    for (UIView *v in view.subviews) {
        if ([v isKindOfClass:[UIButton class]] && v.tag == tag) {
            return (UIButton *)v;
        }
        UIButton *found = [self findButtonWithTag:tag inView:v];
        if (found) return found;
    }
    return nil;
}

- (UIButton *)downloadButton {
    return [self findButtonWithTag:203 inView:self];
}

- (void)downloadClick:(UIButton *)btn {
    // 先从当前网页原始 HTML 里正则提取 video/source 标签的 src（包含 .m3u8）
    if (self.pageHTMLString.length > 0) {
        if (!self.m3u8UrlArray) {
            self.m3u8UrlArray = [NSMutableArray array];
        }
        // 来源②:从当前网页 HTML 里提取 video/source 标签的 m3u8 src(补充网络监听没抓到的静态地址)
        for (NSString *src in [HTMLTextTool extractM3U8URLsFromHTML:self.pageHTMLString]) {
            if (![self.m3u8UrlArray containsObject:src]) {
                [self.m3u8UrlArray addObject:src];
                NSLog(@"从 HTML 提取 m3u8 src: %@", src);
            }
        }
    }

    UIViewController *parent = [self parentViewController];
    if (!parent) return;

    if (self.m3u8UrlArray.count == 0) {
        UIAlertController *tip = [UIAlertController alertControllerWithTitle:@"提示"
                                                                    message:@"暂未捕获到 m3u8 地址"
                                                             preferredStyle:UIAlertControllerStyleAlert];
        [tip addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        [parent presentViewController:tip animated:YES completion:nil];
        return;
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择要下载的 m3u8"
                                                                    message:nil
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *urlString in self.m3u8UrlArray) {
        NSString *title = urlString;
        if (title.length > 40) {
            title = [NSString stringWithFormat:@"%@...", [urlString substringToIndex:37]];
        }
        UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull action) {
            [self chooseFolderAndDownloadM3U8:urlString button:btn];
        }];
        [sheet addAction:action];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = btn;
        sheet.popoverPresentationController.sourceRect = btn.bounds;
    }

    [parent presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - 缓存清理

// 清理 Caches 里历次转换残留的 mp4。
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

// 选好 m3u8 后:再让用户选择保存到 Documents/videos 下的哪个文件夹(默认 default)
- (void)chooseFolderAndDownloadM3U8:(NSString *)m3u8URLString button:(UIButton *)btn {
    UIViewController *parent = [self parentViewController];
    if (!parent) return;
    NSArray<NSString *> *folders = [VideoStore folderNames];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择保存位置"
                                                                    message:@"保存到 Documents/videos 下的文件夹"
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *folder in folders) {
        NSString *title = folder;
        if ([folder isEqualToString:@"default"]) {
            title = @"default(默认)";
        }
        UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull action) {
            [self startConvertWithM3U8URL:m3u8URLString targetFolder:folder];
        }];
        [sheet addAction:action];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = btn;
        sheet.popoverPresentationController.sourceRect = btn.bounds;
    }
    [parent presentViewController:sheet animated:YES completion:nil];
}

- (void)startConvertWithM3U8URL:(NSString *)m3u8URLString targetFolder:(NSString *)folderName {
    if (m3u8URLString.length == 0) {
        return;
    }
    [self removeOldCachedMP4Files];

    NSURL *outputURL = [[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] firstObject];
    NSString *fileName = [NSString stringWithFormat:@"%.0f.mp4", [[NSDate date] timeIntervalSince1970]];
    outputURL = [outputURL URLByAppendingPathComponent:fileName];

    UIButton *dlBtn = [self downloadButton];
    [dlBtn setTitle:@"0%" forState:UIControlStateNormal];

    __block NSInteger fakeProgress = 0;
    [ConvertVideoFormat convertM3U8ToMP4WithInputURL:[NSURL URLWithString:m3u8URLString]
                                          outputURL:outputURL
                                            progress:^(float progress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (fakeProgress < 90) {
                fakeProgress += 3;
                if (fakeProgress > 90) fakeProgress = 90;
                [dlBtn setTitle:[NSString stringWithFormat:@"%ld%%", (long)fakeProgress] forState:UIControlStateNormal];
            }
        });
    } completion:^(BOOL success, NSURL *url, NSString *error) {
        [self.m3u8UrlArray removeObject:m3u8URLString];

        if (success) {
            NSLog(@"转换完成: %@", url.path);
            NSError *copyError = nil;
            NSString *targetDir = [VideoStore folderPath:folderName];
            NSString *stored = [VideoStore saveVideoFromURL:url intoDirectory:targetDir error:&copyError];
            [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
            if (stored) {
                [dlBtn setTitle:@"100%" forState:UIControlStateNormal];
                [TSToast show:@"下载完成"];
            } else {
                [dlBtn setTitle:@"下载" forState:UIControlStateNormal];
                [TSToast show:[NSString stringWithFormat:@"保存失败: %@", copyError ?: @"未知错误"]];
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [dlBtn setTitle:@"下载" forState:UIControlStateNormal];
            });
        } else {
            NSLog(@"转换失败: %@", error);
            [dlBtn setTitle:@"下载" forState:UIControlStateNormal];
            [TSToast show:[NSString stringWithFormat:@"下载失败: %@", error ?: @"未知错误"]];
        }
    }];
}

#pragma mark - 弹出控制器查找

// 通过响应链找到承载本视图的控制器,用于 present 弹窗。
// 直接挂在 window 上时响应链到不了 UIViewController,回退到 window 的 rootViewController。
- (UIViewController *)parentViewController {
    UIResponder *r = self.nextResponder;
    while (r) {
        if ([r isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)r;
        }
        r = r.nextResponder;
    }
    UIWindow *win = self.window;
    if (win) {
        return win.rootViewController;
    }
    return nil;
}

#pragma mark - WKUIDelegate / WKNavigationDelegate

- (nullable WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    if (!navigationAction.targetFrame.isMainFrame) {
        [webView loadRequest:navigationAction.request];
    }
    return nil;
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self endRefresh];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self endRefresh];
}

// 记录最新打开的网址(含页内跳转、前进后退),供下次进入恢复
- (void)recordLastURL:(NSString *)urlString {
    if (urlString.length > 0 && ([urlString hasPrefix:@"http://"] || [urlString hasPrefix:@"https://"])) {
        [[NSUserDefaults standardUserDefaults] setObject:urlString forKey:@"lastWebURL"];
    }
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    // 提交即记录——前进/后退到缓存页也可能不触发 didFinishNavigation,这里兜底
    [self recordLastURL:webView.URL.absoluteString];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self endRefresh];
    [self recordLastURL:webView.URL.absoluteString];
    NSString *allHtml = @"document.documentElement.innerHTML";
    [webView evaluateJavaScript:allHtml completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        if ([result isKindOfClass:[NSString class]]) {
            self.pageHTMLString = result;
            if (self.resultString.length == 0) {
                self.resultString = [HTMLTextTool filterHTML:result];
            }
        }
    }];

    [webView evaluateJavaScript:@"document.body.innerText" completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        if ([result isKindOfClass:[NSString class]] && [(NSString *)result length] > 0) {
            self.resultString = result;
        }
    }];
}

@end
