//
//  ReadViewController.m
//  MojiGai
//
//  Created by zhaohongbin on 2023/8/25.
//  Copyright © 2023 zhaohongbin. All rights reserved.
//

#import "ReadViewController.h"
#import "TxtStore.h"
#import "PageController.h"

@interface ReadViewController () <UIGestureRecognizerDelegate>

@property(retain, nonatomic) UISlider* readerSlider;
@property (nonatomic, strong) NSMutableArray *udData;
@property (nonatomic, strong) NSMutableDictionary *oriDict;
@property (nonatomic, strong) NSArray *pages;
@property (nonatomic, strong) UIView *readerNavBar;
@property (nonatomic, strong) UIView *readerToolbar;
@property (nonatomic, assign) BOOL chromeVisible;

@end

@implementation ReadViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.dataSource = self;
    self.delegate = self;
    [self configNavigationBar];
    [self configToolbar];
    [self setupTapGesture];
    [self handleViewControllers];
    [self applyCurrentStyle];   // 应用主题/字号到阅读器上下文
}

- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    if (self.readerSlider) {
        self.readerSlider.value = [self oriSliderValue];
    }
    // 翻页模式:恢复上次所在页
    if ([self curReadType] == 1 && self.readerSlider) {
        [self pressSlider:self.readerSlider];
    }
}

- (void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    // 滚动模式:恢复上次阅读位置(offsety)
    if ([self curReadType] == 0) {
        PageController *page = [self viewControllers].firstObject;
        UITextView *tv = page.readTXTView;
        CGFloat off = [self curOffSet];
        if (tv && off > 0) {
            CGFloat span = tv.contentSize.height - tv.frame.size.height;
            CGFloat target = (span > 0) ? MIN(off, span) : 0;
            [tv setContentOffset:CGPointMake(0, target) animated:false];
        }
    }
}

// 布局完成后按安全区摆放顶栏/滑块/底部工具栏(顶部刘海区 + 底部 Home 指示条)
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat top = self.view.safeAreaInsets.top;
    CGFloat bottom = self.view.safeAreaInsets.bottom;

    // 顶栏
    self.readerNavBar.frame = CGRectMake(0, 0, w, top + 44);
    UIButton *backBtn = [self.view viewWithTag:2010];
    backBtn.frame = CGRectMake(0, top, 60, 44);
    self.readerSlider.frame = CGRectMake(60, top, w - 120, 44);
    UIButton *switchBtn = [self.view viewWithTag:2011];
    switchBtn.frame = CGRectMake(w - 60, top, 60, 44);

    // 底部工具栏(含安全区): A- / A+ / 主题
    CGFloat barH = 50;
    self.readerToolbar.frame = CGRectMake(0, h - bottom - barH, w, barH + bottom);
    CGFloat btnW = w / 3.0;
    for (NSInteger i = 0; i < 3; i++) {
        UIButton *b = (UIButton *)[self.readerToolbar viewWithTag:(2020 + i)];
        b.frame = CGRectMake(i * btnW, 0, btnW, barH);
    }
}

#pragma mark - 时序修复:预置首页内容再 setViewControllers

- (void)handleViewControllers{
    PageController *page1 = [[PageController alloc] init];
    PageController *page2 = [[PageController alloc] init];
    PageController *page3 = [[PageController alloc] init];
    // 滚动事件转发给阅读器:滚动模式下滑块跟随进度
    page1.scrollDelegate = self;
    page2.scrollDelegate = self;
    page3.scrollDelegate = self;
    [self applyStyleToPage:page1];
    page1.index = 0;
    [self refreshContent:0 controller:page1];
    self.pages = @[page1,page2,page3];
    [self setViewControllers:@[page1] direction:UIPageViewControllerNavigationDirectionForward animated:true completion:nil];
}

#pragma mark - UIPageViewControllerDataSource

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerBeforeViewController:(UIViewController *)viewController{
    if (!self.oriDict) return nil;
    if ([self curReadType] == 0) return nil;   // 滚动模式:禁止横向翻页(索引可能残留,强制拦截)
    PageController *curVC = (PageController *)viewController;
    if(curVC.index <= 0){
        return nil;
    }
    NSUInteger curIndex = [self.pages indexOfObject:viewController];
    PageController *beforeVC = curIndex > 0 ? _pages[curIndex - 1] : _pages.lastObject;
    beforeVC.index = curVC.index - 1;
    [self refreshContent:beforeVC.index controller:beforeVC];
    return beforeVC;
}

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerAfterViewController:(UIViewController *)viewController{
    if (!self.oriDict) return nil;
    if ([self curReadType] == 0) return nil;   // 滚动模式:禁止横向翻页
    PageController *curVC = (PageController *)viewController;
    NSArray *dataArr = [self curReadType] == 0 ? @[[self curOriginString]] : [self curPageArray];
    if (dataArr.count == 0) return nil;
    if(curVC.index >= dataArr.count - 1){
        return nil;
    }
    NSUInteger curIndex = [self.pages indexOfObject:viewController];
    PageController *afterVC = curIndex < _pages.count - 1 ? _pages[curIndex + 1] : _pages.firstObject;
    afterVC.index = curVC.index + 1;
    [self refreshContent:afterVC.index controller:afterVC];
    return afterVC;
}

- (void)refreshContent:(int)pageIndex controller:(PageController *)controller{
    if (!self.oriDict) {
        controller.content = @"";
        return;
    }
    NSArray *dataArr = [self curReadType] == 0 ? @[[self curOriginString]] : [self curPageArray];
    if (pageIndex < 0 || pageIndex >= dataArr.count) return;
    controller.content = dataArr[pageIndex];
}

- (void)pageViewController:(UIPageViewController *)pageViewController didFinishAnimating:(BOOL)finished previousViewControllers:(NSArray<UIViewController *> *)previousViewControllers transitionCompleted:(BOOL)completed{
    if(completed && [self curReadType] == 1){
        PageController *curVC = (PageController *)pageViewController.viewControllers.firstObject;
        NSArray *dataArr = [self curPageArray];
        if (dataArr.count > 1) {
            self.readerSlider.value = MAX(curVC.index * 1.0 / (dataArr.count - 1), 0);
        }
    }
}

#pragma mark - scrollview代理

- (void)scrollViewDidScroll:(UIScrollView *)scrollView{
    if(_readerSlider.isHighlighted){
        return;
    }
    if([self curReadType] == 0){
        CGFloat span = scrollView.contentSize.height - scrollView.frame.size.height;
        if (span <= 0) return;
        float value = (scrollView.contentOffset.y * 1.0) / span;
        value = MAX(0, MIN(1, value));
        // 节流:值变化超过阈值才更新,滤掉高频微调导致的滑块抖动
        if (fabs(value - _readerSlider.value) > 0.001) {
            _readerSlider.value = value;
        }
    }
}

#pragma mark - slider代理

- (void) pressSlider:(UISlider*) slider {
    if([self curReadType] == 0){
        PageController *page = [self viewControllers][0];
        CGFloat span = page.readTXTView.contentSize.height - page.readTXTView.frame.size.height;
        if (span > 0) {
            [page.readTXTView setContentOffset:CGPointMake(0, span * slider.value) animated:false];
        }
    }else if([self curReadType] == 1){
        PageController *page = [self viewControllers][0];
        NSArray *dataArr = [self curPageArray];
        if (dataArr.count < 2) return;
        int nIndex = MAX((int)((dataArr.count - 1) * slider.value), 0);
        if(page.index == nIndex){
            return;
        }
        page.index = nIndex;
        [self setViewControllers:@[page] direction:UIPageViewControllerNavigationDirectionForward animated:false completion:nil];
        [self refreshContent:nIndex controller:page];
    }
}

#pragma mark - Data

- (NSMutableArray *)udData{
    if(!_udData){
        NSArray *saved = [[NSUserDefaults standardUserDefaults] valueForKey:@"names"];
        _udData = ([saved isKindOfClass:[NSArray class]]) ? [saved mutableCopy] : [NSMutableArray array];
    }
    return _udData;
}

- (NSMutableDictionary *)oriDict{
    if(!_oriDict){
        // 越界判空:Source 列表变化/条目被删时 row 可能失效,返回 nil 避免崩溃
        if (self.row < 0 || self.row >= self.udData.count) {
            return nil;
        }
        _oriDict = [self.udData[self.row] mutableCopy];
    }
    return _oriDict;
}

- (NSString *)curOriginString{
    return [TxtStore readValueForEntry:self.oriDict] ?: @"";
}

- (int)curReadType{
    return [self.oriDict[@"readType"] intValue];
}

- (CGFloat)curOffSet{
    return [self.oriDict[@"offsety"] floatValue];
}

- (CGFloat)oriSliderValue{
    return [self.oriDict[@"sliderValue"] floatValue];
}

- (NSArray *)curPageArray{
    NSArray *pages = [TxtStore readPagesForEntry:self.oriDict];
    return pages ?: @[];
}

// 写回当前条目(通用)
- (void)persistCurrentDict{
    if (!self.oriDict || self.row < 0 || self.row >= self.udData.count) return;
    [self.udData removeObjectAtIndex:self.row];
    [self.udData insertObject:self.oriDict atIndex:self.row];
    [[NSUserDefaults standardUserDefaults] setObject:self.udData forKey:@"names"];
}

- (void)refreshReadType:(int)type{
    if (!self.oriDict) return;
    PageController *visible = [self viewControllers].firstObject;

    if (type == 1) {
        // 分页模式:确保有分页数据;布局未就绪或分不出页则保持当前模式,避免进入空白分页
        if (![self ensurePagingData]) {
            return;
        }
    }

    self.oriDict[@"readType"] = [NSString stringWithFormat:@"%d",type];
    [self persistCurrentDict];

    // 切换模式后:进度条归零(两种模式都回到起点/第一页)
    if (self.readerSlider) {
        self.readerSlider.value = 0;
    }

    // 重置当前可见页到新模式的起点(索引 0),并刷新内容
    if (visible) {
        visible.index = 0;
        [self refreshContent:0 controller:visible];
    }
}

// 保证分页数据存在;返回 YES 表示当前可用
- (BOOL)ensurePagingData{
    if ([self curPageArray].count > 0) return YES;
    PageController *page = [self viewControllers].firstObject;
    // 用文本框实际排版区域(已扣 textContainerInset),保证每页内容正好放得下、不超屏
    CGSize cs = page.readTXTView.textContainer.size;
    if (cs.width <= 0 || cs.height <= 0) return NO;
    NSArray *pages = [TxtStore pagingWithContentString:[self curOriginString]
                                             contentSize:cs
                                          textAttribute:@{NSFontAttributeName: [UIFont fontWithName:@"PingFang TC" size:[self currentFontSize]]}];
    if (pages.count == 0) return NO;
    [TxtStore savePages:pages forEntry:self.oriDict];
    return YES;
}

// 字号/主题变化后强制按当前尺寸+字号重新分页;失败(布局未就绪/空文本)保留旧缓存,避免空白
- (void)forceRepaginate{
    PageController *page = [self viewControllers].firstObject;
    // 用文本框实际排版区域(已扣 textContainerInset),保证每页内容正好放得下、不超屏
    CGSize cs = page.readTXTView.textContainer.size;
    if (cs.width <= 0 || cs.height <= 0) return;
    NSArray *pages = [TxtStore pagingWithContentString:[self curOriginString]
                                             contentSize:cs
                                          textAttribute:@{NSFontAttributeName: [UIFont fontWithName:@"PingFang TC" size:[self currentFontSize]]}];
    if (pages.count == 0) return;
    [TxtStore savePages:pages forEntry:self.oriDict];
}

#pragma mark - 字号 / 主题 / 进度

// 字号(读写 NSUserDefaults)
- (CGFloat)currentFontSize{
    CGFloat s = [[NSUserDefaults standardUserDefaults] floatForKey:@"readerFontSize"];
    return (s > 0) ? s : 20;
}
- (void)saveFontSize:(CGFloat)s{
    [[NSUserDefaults standardUserDefaults] setFloat:s forKey:@"readerFontSize"];
}

- (NSInteger)currentThemeIndex{
    NSInteger i = [[NSUserDefaults standardUserDefaults] integerForKey:@"readerTheme"];
    return (i < 0 || i >= 4) ? 0 : i;
}
- (NSArray *)themeNames{ return @[@"米白", @"纯白", @"护眼", @"夜间"]; }
- (UIColor *)themeBgForIndex:(NSInteger)i{
    switch (i) {
        case 1: return [UIColor whiteColor];
        case 2: return [UIColor colorWithRed:0.93f green:0.98f blue:0.93f alpha:1.00f];
        case 3: return [UIColor colorWithRed:0.12f green:0.13f blue:0.15f alpha:1.00f];
        case 0:
        default: return [UIColor colorWithRed:1.00f green:0.97f blue:0.85f alpha:1.00f];
    }
}
- (UIColor *)themeTextForIndex:(NSInteger)i{
    switch (i) {
        case 3: return [UIColor colorWithRed:0.85f green:0.85f blue:0.85f alpha:1.00f];
        case 2: return [UIColor colorWithRed:0.10f green:0.30f blue:0.10f alpha:1.00f];
        case 0:
        case 1:
        default: return [UIColor colorWithRed:0.22f green:0.22f blue:0.22f alpha:1.00f];
    }
}

// 把当前主题/字号写入页面属性(页面视图未加载时仅设属性,加载后由 viewDidLoad 应用)
- (void)applyStyleToPage:(PageController *)page{
    page.fontSize = [self currentFontSize];
    page.readerBgColor = [self themeBgForIndex:[self currentThemeIndex]];
    page.readerTextColor = [self themeTextForIndex:[self currentThemeIndex]];
}

// 主题/字号变更:应用到阅读器自身与可见页;分页模式重算分页
- (void)applyCurrentStyle{
    NSInteger ti = [self currentThemeIndex];
    UIColor *bg = [self themeBgForIndex:ti];
    UIColor *txt = [self themeTextForIndex:ti];
    CGFloat fs = [self currentFontSize];

    self.view.backgroundColor = bg;
    self.readerNavBar.backgroundColor = bg;
    self.readerToolbar.backgroundColor = bg;
    [self updateThemeButton];

    // 应用到全部(含被复用的)页面,避免翻页后只有当前页变色
    for (PageController *page in self.pages) {
        page.fontSize = fs;
        page.readerBgColor = bg;
        page.readerTextColor = txt;
        [page applyStyle];
    }

    // 分页模式:字号变化会改变分页边界,按当前字号重新分页(失败则保留旧缓存,避免空白)
    if ([self curReadType] == 1) {
        [self forceRepaginate];
        PageController *visible = [self viewControllers].firstObject;
        if (visible) {
            visible.index = 0;
            [self refreshContent:0 controller:visible];
        }
    }
}

- (void)updateThemeButton{
    UIButton *b = (UIButton *)[self.readerToolbar viewWithTag:2022];
    if (b) {
        [b setTitle:[self themeNames][[self currentThemeIndex]] forState:UIControlStateNormal];
        [b setTitleColor:[self themeTextForIndex:[self currentThemeIndex]] forState:UIControlStateNormal];
    }
}

- (void)fontMinusClick{
    CGFloat s = [self currentFontSize] - 2;
    if (s < 14) s = 14;
    [self saveFontSize:s];
    [self applyCurrentStyle];
}
- (void)fontPlusClick{
    CGFloat s = [self currentFontSize] + 2;
    if (s > 28) s = 28;
    [self saveFontSize:s];
    [self applyCurrentStyle];
}
- (void)themeClick{
    NSInteger i = [self currentThemeIndex];
    i = (i + 1) % 4;
    [[NSUserDefaults standardUserDefaults] setInteger:i forKey:@"readerTheme"];
    [self applyCurrentStyle];
}

#pragma mark - 进度保存

// 退出时保存:滚动模式记 offsety,统一记 sliderValue
- (void)saveCurrentProgress{
    if (!self.oriDict) return;
    if ([self curReadType] == 0) {
        PageController *page = [self viewControllers].firstObject;
        if (page.readTXTView) {
            self.oriDict[@"offsety"] = [NSString stringWithFormat:@"%f", page.readTXTView.contentOffset.y];
        }
    }
    self.oriDict[@"sliderValue"] = [NSString stringWithFormat:@"%f", self.readerSlider.value];
    [self persistCurrentDict];
}

#pragma mark - UI

- (void)configNavigationBar{
    UIView *navBar = [[UIView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:navBar];
    self.readerNavBar = navBar;

    // 控件收进 navBar,便于整体显隐(沉浸式控制层)
    UIButton *btn2 = [[UIButton alloc] initWithFrame:CGRectZero];
    btn2.tag = 2010;
    [btn2 addTarget:self action:@selector(back) forControlEvents:UIControlEventTouchUpInside];
    [btn2 setTitleColor:UIColor.linkColor forState:UIControlStateNormal];
    [btn2 setTitle:@"Back" forState:UIControlStateNormal];
    btn2.titleLabel.font = [UIFont systemFontOfSize:14];
    [navBar addSubview:btn2];

    [navBar addSubview:self.readerSlider];

    UIButton *btn3 = [[UIButton alloc] initWithFrame:CGRectZero];
    btn3.tag = 2011;
    [btn3 addTarget:self action:@selector(switchType) forControlEvents:UIControlEventTouchUpInside];
    [btn3 setTitle:@"Switch" forState:UIControlStateNormal];
    [btn3 setTitleColor:UIColor.linkColor forState:UIControlStateNormal];
    btn3.titleLabel.font = [UIFont systemFontOfSize:14];
    [navBar addSubview:btn3];
}

- (void)configToolbar{
    UIView *toolbar = [[UIView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:toolbar];
    self.readerToolbar = toolbar;

    NSArray *titles  = @[@"A-", @"A+", @"主题"];
    NSArray *actions = @[NSStringFromSelector(@selector(fontMinusClick)),
                         NSStringFromSelector(@selector(fontPlusClick)),
                         NSStringFromSelector(@selector(themeClick))];
    for (NSInteger i = 0; i < 3; i++) {
        UIButton *b = [[UIButton alloc] initWithFrame:CGRectZero];
        b.tag = 2020 + i;
        [b setTitle:titles[i] forState:UIControlStateNormal];
        [b setTitleColor:UIColor.linkColor forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        SEL sel = NSSelectorFromString(actions[i]);
        [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
        [toolbar addSubview:b];
    }
    [self updateThemeButton];
}

#pragma mark - 点击切换控制层(沉浸式)

- (void)setupTapGesture{
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleChrome)];
    tap.cancelsTouchesInView = NO;
    tap.delegate = self;
    [self.view addGestureRecognizer:tap];
    self.chromeVisible = YES;
}

// 顶栏/工具栏上的控件(按钮、滑块)直接响应,不触发展开/收起
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch{
    UIView *v = touch.view;
    if ([v isKindOfClass:[UIControl class]]) {
        return NO;
    }
    return YES;
}

- (void)toggleChrome{
    self.chromeVisible = !self.chromeVisible;
    if (self.chromeVisible) {
        self.readerNavBar.hidden = NO;
        self.readerToolbar.hidden = NO;
    }
    [UIView animateWithDuration:0.25 animations:^{
        self.readerNavBar.alpha = self.chromeVisible ? 1.0 : 0.0;
        self.readerToolbar.alpha = self.chromeVisible ? 1.0 : 0.0;
    } completion:^(BOOL finished){
        if (!self.chromeVisible) {
            self.readerNavBar.hidden = YES;
            self.readerToolbar.hidden = YES;
        }
    }];
}

- (void)back{
    [self saveCurrentProgress];
    [self dismissViewControllerAnimated:true completion:nil];
}
- (void)switchType{
    if([self curReadType] == 0){
        [self refreshReadType:1];
    }else if ([self curReadType] == 1){
        [self refreshReadType:0];
    }
}

- (UISlider *)readerSlider {
    if (_readerSlider == nil) {
        _readerSlider = [[UISlider alloc] initWithFrame:CGRectZero];
        _readerSlider.maximumValue = 1;
        _readerSlider.minimumValue = 0;
        _readerSlider.minimumTrackTintColor = [UIColor blueColor];
        _readerSlider.maximumTrackTintColor = [UIColor greenColor];
        [_readerSlider addTarget:self action:@selector(pressSlider:) forControlEvents:UIControlEventValueChanged];
    }
    return _readerSlider;
}

@end
