//
//  TSWebView.m
//  MojiGai
//
//  Created by zhaohongbin on 2019/9/2.
//  Copyright © 2019 zhaohongbin. All rights reserved.
//

#import "TSWebView.h"

static NSString * const TSNetworkObserverHandlerName = @"tsNetworkObserver";

static NSString *TSStringValue(id value) {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

#pragma mark - 弱引用消息代理(userContentController 会强引用 handler,经代理转发避免循环引用)

@interface TSWeakScriptMessageHandler : NSObject <WKScriptMessageHandler>

@property (nonatomic, weak) id<WKScriptMessageHandler> delegate;

@end

@implementation TSWeakScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    [self.delegate userContentController:userContentController didReceiveScriptMessage:message];
}

@end

#pragma mark - 请求记录

@implementation TSNetworkRequestInfo

@end

#pragma mark - TSWebView

@interface TSWebView () <WKScriptMessageHandler>

@property (nonatomic, strong) TSWeakScriptMessageHandler *messageHandlerProxy;

@end

@implementation TSWebView

- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration{
    // 注入脚本与消息代理需在 WKWebView 创建前完成,否则对首次加载的页面不生效
    TSWeakScriptMessageHandler *proxy = [[TSWeakScriptMessageHandler alloc] init];
    WKUserContentController *userContentController = configuration.userContentController;
    [userContentController addScriptMessageHandler:proxy name:TSNetworkObserverHandlerName];
    [userContentController addUserScript:[[WKUserScript alloc] initWithSource:[TSWebView networkObserverScript]
                                                               injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                            forMainFrameOnly:NO]];

    if (self = [super initWithFrame:frame configuration:configuration]) {
        proxy.delegate = self;
        _messageHandlerProxy = proxy;
        [self createMenu];
    }
    return self;
}

- (void)dealloc {
    // 移除消息代理,避免 userContentController 长期持有已释放视图对应的代理
    [self.configuration.userContentController removeScriptMessageHandlerForName:TSNetworkObserverHandlerName];
}

//构建UIMenuController
//新添加的菜单
- (void)createMenu {
    UIMenuController *menu = [UIMenuController sharedMenuController];
    UIMenuItem *item0 = [[UIMenuItem alloc] initWithTitle:@"复制2" action:@selector(haha:)];
    [menu setMenuItems:@[item0]];
}
//决定展示哪个菜单
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action ==@selector(copy:) || action == @selector(selectAll:) || action == @selector(paste:) || action == @selector(haha:)) {
        return YES;
    }
    return NO;
}

//自定义菜单按钮的执行方法
- (void)haha:(id)sender{
    
    //有问题,会获得上一次的选中信息
//    [self copy:sender];
//    NSLog(@"%@",[UIPasteboard generalPasteboard].string);
    
    [self evaluateJavaScript:@"window.getSelection().toString()" completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        NSLog(@"%@",result);
    }];
}

- (void)showWeb{
    self.hidden = NO;
    if ([self canBecomeFirstResponder]) {
        [self becomeFirstResponder];
    }
}
- (void)hideWeb{
    self.hidden = YES;
    if ([self canResignFirstResponder]) {
        [self resignFirstResponder];
    }
}

/**
 
 //    @protocol UIResponderStandardEditActions <NSObject>
 //    @optional
 //    - (void)cut:(nullable id)sender NS_AVAILABLE_IOS(3_0); //剪切
 //    - (void)copy:(nullable id)sender NS_AVAILABLE_IOS(3_0); //复制
 //    - (void)paste:(nullable id)sender NS_AVAILABLE_IOS(3_0); //粘贴
 //    - (void)select:(nullable id)sender NS_AVAILABLE_IOS(3_0); //选择
 //    - (void)selectAll:(nullable id)sender NS_AVAILABLE_IOS(3_0); //全选
 //    - (void)delete:(nullable id)sender NS_AVAILABLE_IOS(3_2);    //删除
 //    - (void)makeTextWritingDirectionLeftToRight:(nullable id)sender NS_AVAILABLE_IOS(5_0); //改变书写模式为从左向右按钮触发
 //    - (void)makeTextWritingDirectionRightToLeft:(nullable id)sender NS_AVAILABLE_IOS(5_0); //改变书写模式为从右向左按钮触发
 
 ————————————————
 版权声明：本文为CSDN博主「唐云T_yun」的原创文章，遵循 CC 4.0 BY-SA 版权协议，转载请附上原文出处链接及本声明。
 原文链接：https://blog.csdn.net/xmy0010/article/details/52945689
 
 */

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:TSNetworkObserverHandlerName] || ![message.body isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSDictionary *body = (NSDictionary *)message.body;

    TSNetworkRequestInfo *request = [[TSNetworkRequestInfo alloc] init];
    request.type = TSStringValue(body[@"type"]);
    request.method = TSStringValue(body[@"method"]);
    request.url = TSStringValue(body[@"url"]);
    request.params = [body[@"params"] isKindOfClass:[NSString class]] ? body[@"params"] : nil;
    request.status = [body[@"status"] integerValue];
    request.response = [body[@"response"] isKindOfClass:[NSString class]] ? body[@"response"] : nil;

    if (self.onNetworkRequest) {
        self.onNetworkRequest(request);
    }
}

#pragma mark - 注入脚本

// 包装 XMLHttpRequest 与 fetch,把请求的 URL / method / 参数与响应状态、响应内容经 messageHandlers 回传。
// 额外钩住媒体元素(video/audio)的 src,捕获直接赋值 m3u8 的情况。
// 返回的 JS 在页面 documentStart 时注入(见 initWithFrame:configuration:)。
+ (NSString *)networkObserverScript {
    // 用字符串数组按行拼接,便于阅读与加注释;数组里每行是一条 JS 语句。
    // 占位符 __HANDLER__ 在下方替换成真实的消息 handler 名。
    NSArray<NSString *> *lines = @[
        @"(function() {",
        @"    // 防止重复注入:同一页面可能多次执行本脚本",
        @"    if (window.__tsNetworkObserverInstalled) { return; }",
        @"    window.__tsNetworkObserverInstalled = true;",
        @"",
        @"    // ================= 基础工具 =================",
        @"",
        @"    // 把 JS 侧捕获到的请求信息发给原生端(WebBrowserView 的 onNetworkRequest 接收)",
        @"    var post = function(payload) {",
        @"        try { window.webkit.messageHandlers.__HANDLER__.postMessage(payload); } catch (e) {}",
        @"    };",
        @"",
        @"    // 判断一个 URL 是否像 m3u8 播放列表地址(.m3u8 或 .m3u,忽略大小写,允许带 ?/# 参数)",
        @"    var isM3U8 = function(url) {",
        @"        url = String(url || '');",
        @"        return /\\.m3u8([?#]|$)/i.test(url) || /\\.m3u([?#]|$)/i.test(url);",
        @"    };",
        @"",
        @"    // 已上报过的媒体地址,避免重复上报",
        @"    var postedMedia = {};",
        @"    // 上报媒体元素 src(仅当它是 m3u8 地址时)",
        @"    var postMedia = function(url) {",
        @"        try {",
        @"            url = String(url || '');",
        @"            if (!isM3U8(url)) return;",
        @"            if (postedMedia[url]) return;",
        @"            postedMedia[url] = true;",
        @"            post({ type: 'media', method: 'GET', url: url, params: null, status: 200, response: null });",
        @"        } catch (e) {}",
        @"    };",
        @"",
        @"    // 把请求体(FormData / URLSearchParams / 字符串)转成纯文本",
        @"    var toText = function(body) {",
        @"        if (body === undefined || body === null) { return null; }",
        @"        if (typeof body === 'string') { return body; }",
        @"        try {",
        @"            if (typeof FormData !== 'undefined' && body instanceof FormData) {",
        @"                var parts = [];",
        @"                body.forEach(function(value, key) { parts.push(key + '=' + value); });",
        @"                return parts.join('&');",
        @"            }",
        @"            if (typeof URLSearchParams !== 'undefined' && body instanceof URLSearchParams) {",
        @"                return body.toString();",
        @"            }",
        @"        } catch (e) {}",
        @"        return null;",
        @"    };",
        @"",
        @"    // 把相对 URL 解析成绝对 URL",
        @"    var resolveURL = function(url) {",
        @"        try { return new URL(url, window.location.href).href; } catch (e) { return String(url); }",
        @"    };",
        @"",
        @"    // 响应文本截断到 1 万字符,避免超大响应撑爆内存",
        @"    var clamp = function(text) {",
        @"        if (typeof text !== 'string') { return null; }",
        @"        return text.length > 10000 ? text.substring(0, 10000) : text;",
        @"    };",
        @"",
        @"    // 从 XHR 读取响应文本(仅处理文本/json 类型)",
        @"    var readResponseText = function(xhr) {",
        @"        try {",
        @"            if (xhr.responseType === 'json') { return clamp(JSON.stringify(xhr.response)); }",
        @"            if (xhr.responseType === 'text' || xhr.responseType === '') { return clamp(xhr.responseText); }",
        @"        } catch (e) {}",
        @"        return null;",
        @"    };",
        @"",
        @"    // ================= 拦截 XMLHttpRequest =================",
        @"",
        @"    var requestProto = window.XMLHttpRequest && window.XMLHttpRequest.prototype;",
        @"    if (requestProto) {",
        @"        var originalOpen = requestProto.open;",
        @"        var originalSend = requestProto.send;",
        @"        // open 时记下 method 和 url",
        @"        requestProto.open = function(method, url) {",
        @"            this.__tsRequestMethod = method;",
        @"            this.__tsRequestURL = url;",
        @"            return originalOpen.apply(this, arguments);",
        @"        };",
        @"        // send 时挂一个 loadend 监听,请求结束把结果上报",
        @"        requestProto.send = function(body) {",
        @"            var xhr = this;",
        @"            var method = xhr.__tsRequestMethod || 'GET';",
        @"            var url = resolveURL(xhr.__tsRequestURL || '');",
        @"            var params = toText(body);",
        @"            // 先移除旧的监听,避免重复上报",
        @"            if (xhr.__tsLoadendHandler) { xhr.removeEventListener('loadend', xhr.__tsLoadendHandler); }",
        @"            xhr.__tsLoadendHandler = function() {",
        @"                post({ type: 'xhr', method: method, url: url, params: params, status: xhr.status, response: readResponseText(xhr) });",
        @"            };",
        @"            xhr.addEventListener('loadend', xhr.__tsLoadendHandler);",
        @"            return originalSend.apply(this, arguments);",
        @"        };",
        @"    }",
        @"",
        @"    // ================= 拦截 fetch =================",
        @"",
        @"    var originalFetch = window.fetch;",
        @"    if (originalFetch) {",
        @"        window.fetch = function(input, init) {",
        @"            // 兼容字符串 / URL 对象 / Request 对象三种入参",
        @"            var isRequest = typeof Request !== 'undefined' && input instanceof Request;",
        @"            var rawURL = typeof input === 'string' ? input : ((typeof URL !== 'undefined' && input instanceof URL) ? input.href : (input && input.url));",
        @"            var method = (init && init.method) || (isRequest && input.method) || 'GET';",
        @"            var url = resolveURL(rawURL || '');",
        @"            var params = toText(init && init.body);",
        @"            return originalFetch.apply(this, arguments).then(function(response) {",
        @"                var record = { type: 'fetch', method: method, url: url, params: params, status: response.status };",
        @"                var contentType = '';",
        @"                try { contentType = response.headers.get('content-type') || ''; } catch (e) {}",
        @"                // 流式响应(如 SSE)不 clone 读 body,直接上报基本字段",
        @"                if (contentType.indexOf('text/event-stream') === 0) {",
        @"                    post(record);",
        @"                    return response;",
        @"                }",
        @"                // 其余响应 clone 后读一次 body 文本(尽量拿到 m3u8 播放列表内容)",
        @"                try {",
        @"                    response.clone().text().then(function(text) {",
        @"                        record.response = clamp(text);",
        @"                        post(record);",
        @"                    }, function() {",
        @"                        post(record);",
        @"                    });",
        @"                } catch (e) {",
        @"                    post(record);",
        @"                }",
        @"                return response;",
        @"            }, function(error) {",
        @"                post({ type: 'fetch', method: method, url: url, params: params, status: 0 });",
        @"                throw error;",
        @"            });",
        @"        };",
        @"    }",
        @"",
        @"    // ================= 媒体元素钩子 =================",
        @"    // 捕获 video/audio 直接赋值 m3u8 地址的情况(XHR/fetch 拦截看不到这种)",
        @"    (function() {",
        @"        if (window.__tsMediaHooked) { return; }",
        @"        window.__tsMediaHooked = true;",
        @"",
        @"        // 扫描页面里所有 video/audio,上报它们当前的 m3u8 地址",
        @"        var scan = function() {",
        @"            try {",
        @"                var els = document.querySelectorAll('video,audio');",
        @"                for (var i = 0; i < els.length; i++) {",
        @"                    var el = els[i];",
        @"                    var u = el.currentSrc || el.src;",
        @"                    if (u) postMedia(u);",
        @"                }",
        @"            } catch (e) {}",
        @"        };",
        @"",
        @"        // 拦下 src 的 setter:JS 里执行 el.src = 'xxx.m3u8' 时立即上报",
        @"        var proto = window.HTMLMediaElement && window.HTMLMediaElement.prototype;",
        @"        if (proto) {",
        @"            try {",
        @"                var srcDesc = Object.getOwnPropertyDescriptor(proto, 'src');",
        @"                if (srcDesc && srcDesc.set) {",
        @"                    Object.defineProperty(proto, 'src', {",
        @"                        set: function(v) { srcDesc.set.call(this, v); postMedia(v); },",
        @"                        get: function() { return srcDesc.get.call(this); }",
        @"                    });",
        @"                }",
        @"            } catch (e) {}",
        @"        }",
        @"",
        @"        // 立即扫一次,并每 2 秒兜底扫(覆盖动态创建视频元素或通过属性设置的站点)",
        @"        scan();",
        @"        setInterval(scan, 2000);",
        @"    })();",
        @"})();",
    ];
    NSString *script = [lines componentsJoinedByString:@"\n"];
    return [script stringByReplacingOccurrencesOfString:@"__HANDLER__" withString:TSNetworkObserverHandlerName];
}

@end
