//
//  TSToast.m
//  Mojigai
//
//  Created by zhaohongbin on 2026/10/13.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import "TSToast.h"
#import "UIWindow+CurrentWindow.h"

@implementation TSToast

+ (void)show:(NSString *)message{
    if (message.length == 0) return;
    UIWindow *window = [UIWindow currentKeyWindow];
    if (!window) return;
    UILabel *toast = [[UILabel alloc] init];
    toast.text = message;
    toast.textColor = [UIColor whiteColor];
    toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.layer.cornerRadius = 8;
    toast.clipsToBounds = YES;
    toast.font = [UIFont systemFontOfSize:14];
    toast.numberOfLines = 0;
    CGFloat maxW = [UIScreen mainScreen].bounds.size.width - 40;
    CGSize size = [message boundingRectWithSize:CGSizeMake(maxW, 100)
                                         options:NSStringDrawingUsesLineFragmentOrigin
                                      attributes:@{NSFontAttributeName: toast.font}
                                         context:nil].size;
    CGFloat w = size.width + 32;
    CGFloat h = size.height + 16;
    toast.frame = CGRectMake(([UIScreen mainScreen].bounds.size.width - w)/2,
                             CGRectGetHeight(window.bounds) - 180,
                             w, h);
    [window addSubview:toast];
    [UIView animateWithDuration:0.3 delay:1.5 options:UIViewAnimationOptionCurveEaseIn animations:^{
        toast.alpha = 0;
    } completion:^(BOOL finished) {
        [toast removeFromSuperview];
    }];
}

@end
