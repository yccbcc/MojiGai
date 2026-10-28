//
//  PageController.m
//  MojiGai
//
//  Created by zhaohongbin on 2023/8/25.
//  Copyright © 2023 zhaohongbin. All rights reserved.
//

#import "PageController.h"

@interface PageController ()<UITextViewDelegate>
@end

@implementation PageController

- (void)viewDidLoad {
    [super viewDidLoad];
    // 兜底默认值(通常由父控制器创建时已设置)
    if (self.fontSize <= 0) self.fontSize = 20;
    if (!self.readerBgColor) self.readerBgColor = [UIColor colorWithRed:1.00f green:0.97f blue:0.85f alpha:1.00f];
    if (!self.readerTextColor) self.readerTextColor = [UIColor darkGrayColor];
    self.view.backgroundColor = self.readerBgColor;
    [self.view addSubview:[self createReadTextView]];
}

// 布局完成后按安全区摆放文本框:顶部让出刘海区+阅读器顶栏,底部避开 Home 指示条
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (_readTXTView) {
        CGFloat top = self.view.safeAreaInsets.top + 44;
        CGFloat bottom = self.view.safeAreaInsets.bottom;
        _readTXTView.frame = CGRectMake(0, top,
                                        self.view.bounds.size.width,
                                        self.view.bounds.size.height - top - bottom);
    }
}

- (UITextView *)createReadTextView{
    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectZero];
    textView.backgroundColor = self.readerBgColor;
    textView.textColor = self.readerTextColor;
    textView.delegate = self;
    _readTXTView = textView;
    [self setContentString];
    return textView;
}

- (void)setContent:(NSString *)content{
    _content = content;
    if(_readTXTView){
        [self setContentString];
    }
}

- (void)setContentString{
    NSString *text = self.content ?: @"";
    CGFloat size = self.fontSize > 0 ? self.fontSize : 20;
    NSMutableAttributedString *mAttString = [[NSMutableAttributedString alloc] initWithString:text];
    [mAttString setAttributes:@{
        NSFontAttributeName: [UIFont fontWithName:@"PingFang TC" size:size],
        NSForegroundColorAttributeName: (self.readerTextColor ?: [UIColor darkGrayColor])
    } range:NSMakeRange(0, text.length)];
    _readTXTView.attributedText = mAttString;
    _readTXTView.backgroundColor = self.readerBgColor;
    _readTXTView.textColor = self.readerTextColor;
}

// 样式变更(字号/主题)后由父控制器调用刷新
- (void)applyStyle{
    if (self.fontSize <= 0) self.fontSize = 20;
    if (!self.readerBgColor) self.readerBgColor = [UIColor colorWithRed:1.00f green:0.97f blue:0.85f alpha:1.00f];
    if (!self.readerTextColor) self.readerTextColor = [UIColor darkGrayColor];
    self.view.backgroundColor = self.readerBgColor;
    if (_readTXTView){
        _readTXTView.backgroundColor = self.readerBgColor;
        _readTXTView.textColor = self.readerTextColor;
        [self setContentString];
    }
}

- (BOOL)textViewShouldBeginEditing:(UITextView *)textView{
    return NO;
}

// 把文本视图的滚动事件转发给阅读器(用于滚动模式下滑块跟随进度)
- (void)scrollViewDidScroll:(UIScrollView *)scrollView{
    if (self.scrollDelegate && [self.scrollDelegate respondsToSelector:@selector(scrollViewDidScroll:)]) {
        [self.scrollDelegate scrollViewDidScroll:scrollView];
    }
}

@end
