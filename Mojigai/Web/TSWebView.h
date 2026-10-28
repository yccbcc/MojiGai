//
//  TSWebView.h
//  MojiGai
//
//  Created by zhaohongbin on 2019/9/2.
//  Copyright © 2019 zhaohongbin. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 网页网络请求记录(XHR / fetch)
@interface TSNetworkRequestInfo : NSObject

/// 请求类型:xhr / fetch
@property (nonatomic, copy) NSString *type;
/// 请求方法:GET / POST 等
@property (nonatomic, copy) NSString *method;
/// 请求地址(已解析为绝对地址)
@property (nonatomic, copy) NSString *url;
/// 请求参数(已字符串化,无参数为 nil)
@property (nonatomic, copy, nullable) NSString *params;
/// 响应状态码,无响应(网络错误 / 被中止)为 0
@property (nonatomic, assign) NSInteger status;
/// 响应内容(文本形式,超长截断;二进制响应等无文本时为 nil)
@property (nonatomic, copy, nullable) NSString *response;

@end

typedef void (^TSNetworkRequestHandler)(TSNetworkRequestInfo *request);

@interface TSWebView : WKWebView

/// 网页网络请求监听回调(主线程回调)
@property (nonatomic, copy, nullable) TSNetworkRequestHandler onNetworkRequest;

- (void)showWeb;
- (void)hideWeb;

@end

NS_ASSUME_NONNULL_END
