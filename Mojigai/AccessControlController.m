//
//  AccessControlController.m
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/15.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import "AccessControlController.h"
#import "MainController.h"
#import "TSToast.h"
#import "UIWindow+CurrentWindow.h"

@interface AccessControlController () <UITextFieldDelegate>
@end

@implementation AccessControlController
{
    UIButton *_clockBtn;
    NSTimer *_clockTimer;
    UITextField *_clockTf;
    UIView *_clockDimView;
    CALayer *_hourHand;
    CALayer *_minuteHand;
    CALayer *_secondHand;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    [self createClock];
}

- (void)dealloc {
    [_clockTimer invalidate];
    _clockTimer = nil;
}

#pragma mark - 时钟

- (void)createClock {
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    CGFloat D = 260;
    if (screenW - 32 < D) D = screenW - 32;   // 小屏自适应

    // 圆形表盘按钮:点击事件不变(clockClick)
    UIButton *clockBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    clockBtn.frame = CGRectMake((screenW - D) / 2.0, (self.view.bounds.size.height - D) / 2.0, D, D);
    clockBtn.backgroundColor = [UIColor colorWithRed:0.97f green:0.98f blue:1.00f alpha:1.00f];
    clockBtn.layer.cornerRadius = D / 2.0;
    clockBtn.layer.borderColor = [UIColor lightGrayColor].CGColor;
    clockBtn.layer.borderWidth = 1.5;
    clockBtn.clipsToBounds = YES;
    [clockBtn addTarget:self action:@selector(clockClick) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:clockBtn];
    _clockBtn = clockBtn;

    [self drawClockFaceOnButton:clockBtn size:D];

    [self clockTick];
    __weak typeof(self) weakSelf = self;
    _clockTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf clockTick];
    }];
    [[NSRunLoop mainRunLoop] addTimer:_clockTimer forMode:NSRunLoopCommonModes];
}

// 画表盘:刻度 + 时针/分针/秒针(支点均在圆心)
- (void)drawClockFaceOnButton:(UIButton *)btn size:(CGFloat)D {
    CGFloat c = D / 2.0;
    CALayer *root = btn.layer;

    // 中心圆点
    CALayer *centerDot = [CALayer layer];
    centerDot.bounds = CGRectMake(0, 0, 10, 10);
    centerDot.cornerRadius = 5;
    centerDot.backgroundColor = [UIColor darkGrayColor].CGColor;
    centerDot.position = CGPointMake(c, c);
    [root addSublayer:centerDot];

    // 12 个刻度(整点加粗加长)
    for (NSInteger i = 0; i < 12; i++) {
        BOOL major = (i % 3 == 0);
        CGFloat len = major ? 10 : 6;
        CGFloat w = major ? 2.5 : 1.5;
        CALayer *tick = [CALayer layer];
        tick.bounds = CGRectMake(0, 0, w, len);
        tick.backgroundColor = [UIColor grayColor].CGColor;
        CGFloat ang = i * (M_PI * 2.0 / 12.0);
        CGFloat r = D / 2.0 - len / 2.0 - 5;   // 贴边
        tick.position = CGPointMake(c + r * cos(ang), c + r * sin(ang));
        tick.transform = CATransform3DMakeRotation(ang, 0, 0, 1);
        [root addSublayer:tick];
    }

    _hourHand = [self makeHandLength:D * 0.22 width:7 color:[UIColor darkGrayColor] center:CGPointMake(c, c)];
    [root addSublayer:_hourHand];
    _minuteHand = [self makeHandLength:D * 0.32 width:5 color:[UIColor darkGrayColor] center:CGPointMake(c, c)];
    [root addSublayer:_minuteHand];
    _secondHand = [self makeHandLength:D * 0.40 width:2 color:[UIColor systemRedColor] center:CGPointMake(c, c)];
    [root addSublayer:_secondHand];
}

// 生成一根指针:底部中心为支点,默认指向 12 点
- (CALayer *)makeHandLength:(CGFloat)len width:(CGFloat)w color:(UIColor *)color center:(CGPoint)c {
    CALayer *hand = [CALayer layer];
    hand.backgroundColor = color.CGColor;
    hand.bounds = CGRectMake(0, 0, w, len);
    hand.anchorPoint = CGPointMake(0.5, 1.0);
    hand.position = c;
    hand.cornerRadius = w / 2.0;
    return hand;
}

- (void)clockTick {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *comp = [cal components:(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond) fromDate:[NSDate date]];
    CGFloat h = comp.hour % 12;
    CGFloat m = comp.minute;
    CGFloat s = comp.second;

    // 时针:每小时30°+每分0.5°;分针:每分6°+每秒0.1°;秒针:每秒6°
    CGFloat hAngle = (h * 30 + m * 0.5) * M_PI / 180.0;
    CGFloat mAngle = (m * 6 + s * 0.1) * M_PI / 180.0;
    CGFloat sAngle = s * 6 * M_PI / 180.0;

    _hourHand.transform = CATransform3DMakeRotation(hAngle, 0, 0, 1);
    _minuteHand.transform = CATransform3DMakeRotation(mAngle, 0, 0, 1);
    _secondHand.transform = CATransform3DMakeRotation(sAngle, 0, 0, 1);
}

- (void)clockClick {
    [self showClockDialog];
}

#pragma mark - 弹窗

- (void)showClockDialog {
    [self.view endEditing:YES];

    UIView *dimView = [[UIView alloc] initWithFrame:self.view.bounds];
    dimView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
    dimView.tag = 9001;
    [self.view addSubview:dimView];

    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    CGFloat boxW = screenW - 64;
    if (boxW > 320) boxW = 320;
    CGFloat boxH = 150;
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, boxW, boxH)];
    box.center = CGPointMake(screenW / 2.0, self.view.bounds.size.height / 2.0);
    box.backgroundColor = [UIColor whiteColor];
    box.layer.cornerRadius = 12;
    box.clipsToBounds = YES;
    box.tag = 9002;
    [dimView addSubview:box];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 16, boxW, 24)];
    title.text = @"当前时间是？";
    title.font = [UIFont boldSystemFontOfSize:17];
    title.textAlignment = NSTextAlignmentCenter;
    [box addSubview:title];

    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(24, 56, boxW - 48, 36)];
    tf.borderStyle = UITextBorderStyleRoundedRect;
    tf.keyboardType = UIKeyboardTypeNumberPad; // 纯数字键盘(只显示 0-9)
    tf.returnKeyType = UIReturnKeyDone; // 键盘右下角回车键
    tf.font = [UIFont systemFontOfSize:16];
    tf.textAlignment = NSTextAlignmentCenter;
    tf.delegate = self;
    [box addSubview:tf];
    _clockTf = tf;

    UIButton *okBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    okBtn.frame = CGRectMake(0, boxH - 44, boxW, 44);
    [okBtn setTitle:@"确定" forState:UIControlStateNormal];
    okBtn.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [okBtn addTarget:self action:@selector(confirmClock) forControlEvents:UIControlEventTouchUpInside];
    [box addSubview:okBtn];

    // 点击弹窗外侧可关闭
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(clockDimTap:)];
    [dimView addGestureRecognizer:tap];

    _clockDimView = dimView;
    [tf becomeFirstResponder];
}

- (void)clockDimTap:(UITapGestureRecognizer *)tap {
    UIView *box = [tap.view viewWithTag:9002];
    CGPoint p = [tap locationInView:tap.view];
    if (box && !CGRectContainsPoint(box.frame, p)) {
        [self dismissClockDialog];
    }
}

- (void)dismissClockDialog {
    [self.view endEditing:YES];
    [_clockDimView removeFromSuperview];
    _clockDimView = nil;
    _clockTf = nil;
}

- (void)confirmClock {
    NSString *input = _clockTf.text ?: @"";
    [self dismissClockDialog];
    if ([input isEqualToString:@"0912"]) {
        [self enterViewController];
    } else {
        // 错误时提示当前展示时间(与时钟同格式 yyyy-MM-dd HH:mm:ss)供对照输入
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        NSString *timeStr = [fmt stringFromDate:[NSDate date]];
        [TSToast show:[NSString stringWithFormat:@"当前时间为：%@", timeStr]];
    }
}

// 通过校验后切换根控制器:导航控制器 + MainController 主页
- (void)enterViewController {
    MainController *main = [[MainController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:main];

    // 统一导航栏外观:不透明白底,避免在 Web 等深色页面下显示为黑色
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = UIColor.whiteColor;
        appearance.shadowColor = [UIColor clearColor];
        nav.navigationBar.standardAppearance = appearance;
        nav.navigationBar.scrollEdgeAppearance = appearance;
    } else {
        nav.navigationBar.barTintColor = UIColor.whiteColor;
    }

    // Scene 生命周期下 window 由 SceneDelegate 持有,优先用自身所在窗口,回退当前 key window
    UIWindow *window = self.view.window ?: [UIWindow currentKeyWindow];
    window.rootViewController = nav;
}

#pragma mark - textField代理:仅数字、回车=确定

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == _clockTf) {
        [self confirmClock];
        return YES;
    }
    [textField endEditing:YES];
    return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (textField == _clockTf) {
        NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        if ([string rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
            return NO;
        }
        NSString *newText = [textField.text stringByReplacingCharactersInRange:range withString:string];
        if (newText.length > 8) {
            return NO;
        }
        return YES;
    }
    return YES;
}

@end
