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
#import "VideoDownloadTool.h"
#import "VideoStore.h"
#import "M3U8DownloadController.h"
#import "TSToast.h"
#import "UIWindow+CurrentWindow.h"

@interface WebBrowserView () <WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate, UIGestureRecognizerDelegate>
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
// url -> 来源标识 NSNumber: 1=XHR/fetch, 2=媒体元素, 3=HTML解析(与 m3u8UrlArray 一一对应)
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *m3u8SourceDict;
@property (nonatomic, copy) NSString *pageHTMLString;
@property (nonatomic, copy) NSString *resultString;
// 视频下载工具:封装 m3u8 转码 / mp4 直下与进度回调(懒加载)
@property (nonatomic, strong) VideoDownloadTool *downloadTool;
// 网页原生下载:download -> 落盘地址映射(懒加载,weak key)
@property (nonatomic, strong) NSMapTable<WKDownload *, NSURL *> *downloadDestinations;
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
                strongSelf.m3u8SourceDict = [NSMutableDictionary dictionary];
            }
            if (![strongSelf.m3u8UrlArray containsObject:urlString]) {
                [strongSelf.m3u8UrlArray addObject:urlString];
                // 来源:1=XHR/fetch, 2=媒体元素(上报 type 为 media 时)
                NSInteger source = [request.type isEqualToString:@"media"] ? 2 : 1;
                strongSelf.m3u8SourceDict[urlString] = @(source);
                NSLog(@"捕获 m3u8(来源%ld): %@", (long)source, urlString);
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

// 全局网页视图实例。用可重置的静态变量而非 dispatch_once:
// 便于「长按 Web 入口」时销毁实例并清空网页缓存,下次打开重建——解决缓存膨胀只能重启 App 的问题。
static WebBrowserView *sSharedBrowser = nil;

+ (instancetype)sharedBrowser {
    if (!sSharedBrowser) {
        sSharedBrowser = [[WebBrowserView alloc] initWithFrame:CGRectZero];
        __weak typeof(sSharedBrowser) weakS = sSharedBrowser;
        sSharedBrowser.onClose = ^{
            __strong typeof(weakS) strongS = weakS;
            [strongS hide];
        };
    }
    return sSharedBrowser;
}

// 彻底销毁全局网页视图:停止加载 → 断开代理/回调 → 移出 window → 释放实例 → 清空网页数据。
// 之后再次打开 Web 时 sharedBrowser 会新建,并按 lastWebURL 重新加载,相当于重置整个网页模块。
+ (void)destroySharedBrowser {
    WebBrowserView *b = sSharedBrowser;
    if (!b) return;

    // 打断进行中的加载与回调,避免异步回调触达即将释放的实例
    [b.wkWeb stopLoading];
    b.wkWeb.navigationDelegate = nil;
    b.wkWeb.UIDelegate = nil;
    b.wkWeb.onNetworkRequest = nil;

    [b hide];                 // 移出 window,断开 superview 的强引用
    sSharedBrowser = nil;     // 释放单例,下次重建

    // 清空 WKWebView 网站数据(磁盘/内存缓存、Cookie、本地存储等),真正回收缓存
    WKWebsiteDataStore *store = [WKWebsiteDataStore defaultDataStore];
    [store removeDataOfTypes:[WKWebsiteDataStore allWebsiteDataTypes]
               modifiedSince:[NSDate dateWithTimeIntervalSince1970:0]
           completionHandler:^{}];
}

+ (void)showOnWindow {
    WebBrowserView *b = [WebBrowserView sharedBrowser];
    UIWindow *win = [UIWindow currentKeyWindow];
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
    } else {
        // 首次打开且未记住任何网址时,默认加载主页
        [self homeClick];
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
    // 主动加载新网址(地址栏输入 / 主页 / 外部传入):属于真正的页面切换,清空旧页候选
    [self clearM3U8Candidates];
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
    [alert addAction:[UIAlertAction actionWithTitle:@"下载" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        UITextView *input = (UITextView *)[alert.view viewWithTag:901];
        [strongSelf downloadFromAddressBarURL:input.text];
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
    [self clearM3U8Candidates];
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
            self.m3u8SourceDict = [NSMutableDictionary dictionary];
        }
        // 来源②:从当前网页 HTML 里提取 video/source 标签的 m3u8 src(补充网络监听没抓到的静态地址)
        for (NSString *src in [HTMLTextTool extractM3U8URLsFromHTML:self.pageHTMLString]) {
            if (![self.m3u8UrlArray containsObject:src]) {
                [self.m3u8UrlArray addObject:src];
                self.m3u8SourceDict[src] = @(3);   // 来源:3=HTML解析
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

    // 下载选择页:列表展示所有候选,每行含来源与下载按钮(替代原来的 actionSheet)
    M3U8DownloadController *vc = [[M3U8DownloadController alloc] init];
    vc.m3u8Urls = [self.m3u8UrlArray copy];
    vc.sourceDict = [self.m3u8SourceDict copy];
    __weak typeof(self) weakSelf = self;
    vc.onStartDownload = ^(NSString *m3u8URL, NSString *folderName) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf downloadVideoURL:m3u8URL type:VideoURLTypeM3U8 targetFolder:folderName];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [parent presentViewController:nav animated:YES completion:nil];
}

#pragma mark - 下载调度(委托 VideoDownloadTool)

// 顶部「下载」列表与地址栏「下载」都经此:视图只把工具回调的进度 / 结果映射到下载按钮与 Toast,
// 真正的网络下载 / m3u8 转码 / 落库都封装在 VideoDownloadTool 内。
- (void)downloadVideoURL:(NSString *)urlString type:(VideoURLType)type targetFolder:(NSString *)folderName {
    if (urlString.length == 0) return;

    UIButton *dlBtn = [self downloadButton];
    [dlBtn setTitle:@"0%" forState:UIControlStateNormal];

    __weak typeof(self) weakSelf = self;
    VideoDownloadProgressBlock progress = ^(float value) {
        NSInteger pct = (NSInteger)(value * 100);
        [[weakSelf downloadButton] setTitle:[NSString stringWithFormat:@"%ld%%", (long)pct] forState:UIControlStateNormal];
    };
    VideoDownloadCompletionBlock completion = ^(BOOL success, NSString *savedPath, NSString *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        // 若该地址来自 m3u8 候选列表,完成后移除,避免重复展示
        [strongSelf.m3u8UrlArray removeObject:urlString];
        UIButton *btn = [strongSelf downloadButton];
        if (success) {
            [btn setTitle:@"100%" forState:UIControlStateNormal];
            [TSToast show:@"下载完成"];
        } else {
            [btn setTitle:@"下载" forState:UIControlStateNormal];
            [TSToast show:[NSString stringWithFormat:@"下载失败: %@", error ?: @"未知错误"]];
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[weakSelf downloadButton] setTitle:@"下载" forState:UIControlStateNormal];
        });
    };

    if (type == VideoURLTypeMP4) {
        [self.downloadTool downloadMP4:urlString targetFolder:folderName progress:progress completion:completion];
    } else {
        [self.downloadTool downloadM3U8:urlString targetFolder:folderName progress:progress completion:completion];
    }
}

// 懒加载下载工具:视图持有,负责实际下载与线程调度
- (VideoDownloadTool *)downloadTool {
    if (!_downloadTool) {
        _downloadTool = [[VideoDownloadTool alloc] init];
    }
    return _downloadTool;
}

#pragma mark - 地址栏下载(视频 URL 直接下载)

// 地址栏「下载」:先补 scheme、用工具判断是不是视频,再让用户选保存文件夹。
- (void)downloadFromAddressBarURL:(NSString *)urlString {
    urlString = [urlString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (urlString.length == 0) {
        [TSToast show:@"请输入网址"];
        return;
    }
    if (![urlString hasPrefix:@"http://"] && ![urlString hasPrefix:@"https://"]) {
        urlString = [NSString stringWithFormat:@"https://%@", urlString];
    }

    UIViewController *parent = [self parentViewController];
    if (!parent) return;

    VideoURLType type = [VideoDownloadTool videoTypeForURLString:urlString];
    if (type == VideoURLTypeNone) {
        UIAlertController *tip = [UIAlertController alertControllerWithTitle:@"无法下载"
                                                                    message:@"该地址不是视频(.mp4 / .m3u8)"
                                                             preferredStyle:UIAlertControllerStyleAlert];
        [tip addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        // 等「输入网址」弹窗消失后再弹提示,避免 present 冲突
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [parent presentViewController:tip animated:YES completion:nil];
        });
        return;
    }

    [self presentFolderChoiceForVideoURL:urlString type:type];
}

// 选择保存到 Documents/videos 下的哪个文件夹,确认后交给下载工具执行。
- (void)presentFolderChoiceForVideoURL:(NSString *)urlString type:(VideoURLType)type {
    UIViewController *parent = [self parentViewController];
    if (!parent) return;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择保存位置"
                                                                  message:@"保存到 Documents/videos 下的文件夹"
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *folder in [VideoStore folderNames]) {
        NSString *title = [folder isEqualToString:@"default"] ? @"default(默认)" : folder;
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            [self downloadVideoURL:urlString type:type targetFolder:folder];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self;
        sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds), 1, 1);
    }
    // 延迟到「输入网址」弹窗消失后再弹,避免 present 冲突
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [parent presentViewController:sheet animated:YES completion:nil];
    });
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
    // 新窗口请求(target="_blank" / window.open):WKWebView 默认不自建窗口,必须在此处理。
    // 搜索引擎结果页的链接天然指向别的站点,不属于广告引流,一律放行拉回当前 webview;
    // 其它页面防广告一小步:仅当新地址与当前页同域名时才拉回,跨域弹窗(多为广告/引流)直接丢弃。
    if (!navigationAction.targetFrame.isMainFrame) {
        NSString *currentMainDomain = [self mainDomainForURL:webView.URL];
        NSString *newMainDomain = [self mainDomainForURL:navigationAction.request.URL];
        BOOL sameDomain = newMainDomain.length > 0 && [newMainDomain isEqualToString:currentMainDomain];
        if ([self isSearchEngineURL:webView.URL] || sameDomain) {
            // 弹窗被拉回当前页等同于真正的页面切换,清掉旧页积累的 m3u8 候选
            [self clearM3U8Candidates];
            [webView loadRequest:navigationAction.request];
        } else {
            NSLog(@"拦截跨域弹窗: %@ (当前主域: %@)", navigationAction.request.URL.absoluteString ?: @"(空)", currentMainDomain ?: @"(空)");
        }
    }
    return nil;
}

// 判断当前页是否搜索引擎:取主域后只比最前面的品牌段,这样 google.com / google.co.jp / google.com.hk
// 都归为 google,不必把各国域名逐个写进名单。
- (BOOL)isSearchEngineURL:(NSURL *)url {
    NSString *brand = [[self mainDomainForURL:url] componentsSeparatedByString:@"."].firstObject;
    if (brand.length == 0) return NO;
    static NSSet<NSString *> *engineBrands;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        engineBrands = [NSSet setWithArray:@[@"google", @"bing", @"baidu", @"sogou"]];
    });
    return [engineBrands containsObject:brand];
}

// 取主域名(忽略子域):a.bilibili.com 与 www.bilibili.com 都归为 bilibili.com。
// 转小写后默认取最后两段;若命中已知多段公共后缀(如 .com.cn / .co.uk),则多取一段定位真正主域。
- (NSString *)mainDomainForURL:(NSURL *)url {
    NSString *host = url.host.lowercaseString;
    if (host.length == 0) return host;
    NSArray<NSString *> *labels = [host componentsSeparatedByString:@"."];
    if (labels.count <= 2) return host;   // 本就两段或更少,直接就是主域

    // 末尾两段属于常见多段公共后缀时,主域应为「倒数第三段 + 后两段」(共三段)
    NSString *lastTwo = [labels[labels.count - 2] isEqualToString:@""] ? nil :
                        [NSString stringWithFormat:@"%@.%@", labels[labels.count - 2], labels[labels.count - 1]];
    NSSet *multiPartSuffixes = [NSSet setWithArray:@[
        @"com.cn", @"net.cn", @"org.cn", @"gov.cn", @"edu.cn", @"ac.cn",
        @"com.hk", @"com.tw", @"com.mo", @"co.uk", @"org.uk", @"ac.uk",
        @"com.jp", @"co.jp", @"or.jp", @"com.sg", @"com.au", @"co.za", @"co.kr"
    ]];
    NSInteger span = (lastTwo && [multiPartSuffixes containsObject:lastTwo]) ? 3 : 2;
    NSInteger startIndex = labels.count - span;
    NSArray *mainParts = [labels subarrayWithRange:NSMakeRange(startIndex, span)];
    return [mainParts componentsJoinedByString:@"."];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    // 只在「用户真正点击链接」这种确定要切换到新网址的场景清空上一次 m3u8 候选。
    // 忽略重定向 / 前端 JS 跳转 / backForward 等 WKNavigationTypeOther 导航——
    // 它们可能在新页面 m3u8 已被捕获后再次触发,会把当前页刚抓到的地址误清掉。
    // (代码里主动 loadURL 的清空放在 loadURL: 中处理;下拉刷新放在 reloadClick 中处理。)
    if (navigationAction.targetFrame.isMainFrame &&
        navigationAction.navigationType == WKNavigationTypeLinkActivated) {
        [self clearM3U8Candidates];
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

#pragma mark - 网页原生下载(WKDownload)

// download -> 落盘地址。新版 SDK 的完成回调 downloadDidFinish: 不再回传 URL,
// 需在 decideDestination 时记下目标地址,供完成时展示文件名与路径。weak key:下载结束自动清理。
- (NSMapTable<WKDownload *, NSURL *> *)downloadDestinations {
    if (!_downloadDestinations) {
        _downloadDestinations = [NSMapTable weakToStrongObjectsMapTable];
    }
    return _downloadDestinations;
}

// Documents/videos/downloads 目录,不存在时自动创建。放在 videos 下,下载的视频会直接作为「downloads」
// 文件夹出现在视频列表里。videos 根目录由 VideoStore 统一维护(不存在会自动建)。WKDownload 需 iOS 14.5+。
- (NSString *)downloadsDirectory {
    NSString *dir = [[VideoStore videosDirectory] stringByAppendingPathComponent:@"downloads"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return dir;
}

// 目标文件已存在时在名尾追加 (1)(2)… 顺延,避免覆盖旧文件
- (NSURL *)uniqueDestinationURLForFilename:(NSString *)filename {
    NSString *dir = [self downloadsDirectory];
    NSString *base = filename.stringByDeletingPathExtension;
    NSString *ext = filename.pathExtension;
    NSString *candidate = filename;
    NSInteger index = 1;
    while ([[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingPathComponent:candidate]]) {
        candidate = [NSString stringWithFormat:@"%@ (%ld).%@", base, (long)index, ext];
        index++;
    }
    return [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:candidate]];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    // iOS 14.5+ 网页原生下载入口:<a download> / Content-Disposition: attachment / 无法内联渲染的类型,
    // WebKit 都会把响应作为下载提议到这里。不实现本回调时默认取消下载(点了没反应)。
    if (@available(iOS 14.5, *)) {
        NSString *disposition = nil;
        if ([navigationResponse.response isKindOfClass:[NSHTTPURLResponse class]]) {
            disposition = [(NSHTTPURLResponse *)navigationResponse.response allHeaderFields][@"Content-Disposition"];
        }
        // 注意:无 Content-Disposition 时 disposition 为 nil,而给 nil 发消息返回的 NSRange 是全零({0,0}),
        // location 为 0 而非 NSNotFound,会让判断恒为真——所有普通网页都被当成附件下载。
        // 故必须先保证字符串非空再取 range。
        BOOL isAttachment = disposition.length > 0 &&
                            [disposition rangeOfString:@"attachment" options:NSCaseInsensitiveSearch].location != NSNotFound;
        if (!navigationResponse.canShowMIMEType || isAttachment) {
            // 转交 WKDownload 通道:随后经 didBecomeDownload 回调拿到 download,再由 downloadDelegate 决定落盘位置
            decisionHandler(WKNavigationResponsePolicyDownload);
            return;
        }
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

// 导航响应被转为下载:挂上 delegate,否则收不到 decideDestination / 完成 / 失败回调。
- (void)webView:(WKWebView *)webView navigationResponse:(WKNavigationResponse *)navigationResponse didBecomeDownload:(WKDownload *)download API_AVAILABLE(ios(14.5)) {
    download.delegate = self;
}

#pragma mark WKDownloadDelegate

// 决定保存位置:Documents/videos/downloads/<建议文件名>。必须在此同步给出 destination。
- (void)download:(WKDownload *)download decideDestinationUsingResponse:(NSURLResponse *)response
                                                 suggestedFilename:(NSString *)suggestedFilename
                                                 completionHandler:(void (^)(NSURL * _Nullable destination))completionHandler {
    if (suggestedFilename.length == 0) {
        suggestedFilename = @"未命名文件";
    }
    // 文件名可能带路径分隔符(恶意或异常响应),只取最后一段
    suggestedFilename = suggestedFilename.lastPathComponent;
    NSURL *destination = [self uniqueDestinationURLForFilename:suggestedFilename];
    // 记下目标地址,供 downloadDidFinish: 展示(该回调不再回传 URL)
    [self.downloadDestinations setObject:destination forKey:download];
    completionHandler(destination);
}

// 下载完成:Toast 提示文件名与相对路径(相对沙盒 Documents)。
- (void)downloadDidFinish:(WKDownload *)download {
    NSURL *destination = [self.downloadDestinations objectForKey:download];
    [self.downloadDestinations removeObjectForKey:download];
    NSString *name = destination.lastPathComponent ?: @"文件";
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *path = destination.path ?: @"";
    NSString *display = [path hasPrefix:docs] ? [path substringFromIndex:docs.length + 1] : path;
    [TSToast show:[NSString stringWithFormat:@"已下载: %@\n保存到: %@", name, display]];
}

- (void)download:(WKDownload *)download didFailWithError:(NSError *)error resumeData:(nullable NSData *)resumeData {
    [self.downloadDestinations removeObjectForKey:download];
    NSString *name = download.originalRequest.URL.lastPathComponent ?: @"";
    NSLog(@"网页下载失败: %@ (%@)", name, error.localizedDescription);
    [TSToast show:[NSString stringWithFormat:@"下载失败: %@", error.localizedDescription ?: @"未知错误"]];
}

// 清空当前积累的 m3u8 候选与来源标识(数组为 nil 时发消息也安全)
- (void)clearM3U8Candidates {
    [self.m3u8UrlArray removeAllObjects];
    [self.m3u8SourceDict removeAllObjects];
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
