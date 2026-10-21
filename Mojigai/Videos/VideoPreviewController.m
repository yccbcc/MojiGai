//
//  VideoPreviewController.m
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/16.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import "VideoPreviewController.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

@interface VideoPreviewController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIView *playerView;   // 播放器视图(用于下拉时整体平移缩放)
@end

@implementation VideoPreviewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    if (self.videoPath.length == 0) {
        return;
    }

    // 最简方案:系统播放器
    AVPlayer *player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:self.videoPath]];
    AVPlayerViewController *playerVC = [[AVPlayerViewController alloc] init];
    playerVC.player = player;
    [self addChildViewController:playerVC];
    playerVC.view.frame = self.view.bounds;
    playerVC.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:playerVC.view];
    [playerVC didMoveToParentViewController:self];
    self.playerView = playerVC.view;

    // 下拉关闭手势(网页全屏视频同款效果):竖直向下拖动 → 平移缩放,超阈值关闭 / 未超回弹
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePullDown:)];
    pan.delegate = self;
    // 不拦截子视图触摸,保证播放器自身的控件(进度条/音量/暂停)不受影响
    pan.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:pan];

    [player play];
}

#pragma mark - 下拉手势

// 只在「明显竖直向下」时才接管,避免抢走横向进度条拖动等播放器自身手势
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    CGPoint t = [(UIPanGestureRecognizer *)gestureRecognizer translationInView:self.view];
    return t.y > 0 && fabs(t.y) > fabs(t.x) * 1.5;
}

- (void)handlePullDown:(UIPanGestureRecognizer *)gr {
    UIView *pv = self.playerView;
    if (!pv) return;

    CGFloat ty = [gr translationInView:self.view].y;
    if (ty < 0) ty = 0;
    CGFloat fullH = self.view.bounds.size.height;

    if (gr.state == UIGestureRecognizerStateBegan ||
        gr.state == UIGestureRecognizerStateChanged) {
        CGFloat progress = MIN(ty / fullH, 1.0);
        CGFloat scale = 1.0 - progress * 0.35;
        CGAffineTransform t = CGAffineTransformMakeTranslation(0, ty);
        t = CGAffineTransformScale(t, scale, scale);
        pv.transform = t;
        // 背景逐渐变透,露出底下列表
        self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:(1.0 - progress * 0.85)];
    }
    else if (gr.state == UIGestureRecognizerStateEnded ||
             gr.state == UIGestureRecognizerStateCancelled) {
        CGFloat vel = [gr velocityInView:self.view].y;
        BOOL shouldDismiss = (ty > fullH * 0.25) || (vel > 1000);

        if (shouldDismiss) {
            [UIView animateWithDuration:0.25 animations:^{
                CGAffineTransform t = CGAffineTransformMakeTranslation(0, fullH);
                t = CGAffineTransformScale(t, 0.5, 0.5);
                pv.transform = t;
                self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0];
            } completion:^(BOOL finished) {
                [self dismissViewControllerAnimated:NO completion:nil];
            }];
        } else {
            [UIView animateWithDuration:0.25
                                  delay:0
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:^{
                pv.transform = CGAffineTransformIdentity;
                self.view.backgroundColor = UIColor.blackColor;
            } completion:nil];
        }
    }
}

@end
