//
//  MainController.m
//  MojiGai
//
//  Created by zhaohognbin on 2026/10/15.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import "MainController.h"
#import "EditorController.h"
#import "ImageManagerController.h"
#import "PhotoAlbumController.h"
#import "VideoCollectionController.h"
#import "SourceController.h"
#import "WebBrowserView.h"
#import "TSToast.h"

@interface MainController ()
@end

@implementation MainController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"主页";
    self.view.backgroundColor = [UIColor colorWithRed:0.94f green:0.95f blue:0.97f alpha:1.00f];
    self.tableView.backgroundColor = [UIColor colorWithRed:0.94f green:0.95f blue:0.97f alpha:1.00f];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 100;

    // 长按 Web 入口(section 4):销毁全局网页视图并清空网页缓存。
    // WebBrowserView 是常驻单例,缓存过大时不重启 App 无法释放,长按可就地重置。
    UILongPressGestureRecognizer *webLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleWebLongPress:)];
    webLongPress.minimumPressDuration = 0.6;
    [self.tableView addGestureRecognizer:webLongPress];
}

// 长按命中 Web 行时,先弹二次确认(防误触),确认后再销毁网页视图并清空缓存。
- (void)handleWebLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) {
        return;
    }
    CGPoint point = [gr locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (!indexPath || indexPath.section != 4) {   // 仅 Web 入口响应
        return;
    }
    [self confirmDestroyWebBrowser];
}

- (void)confirmDestroyWebBrowser {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"确认清理缓存？"
                                                                  message:@"将销毁当前网页并清空所有缓存，下次打开重新加载。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确认清理" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        // 返回被取消的下载数:销毁会断开 WKDownload 的 weak delegate,不显式取消的话这些下载会静默失联,
        // 沙盒里留下半截文件。这里合并成一条提示(TSToast 同位置叠 label,分两条弹会重叠)。
        NSUInteger cancelled = [WebBrowserView destroySharedBrowser];
        NSString *msg = cancelled > 0 ? [NSString stringWithFormat:@"已销毁网页并清空缓存\n取消了 %ld 个进行中的下载", (long)cancelled]
                                      : @"已销毁网页并清空缓存";
        [TSToast show:msg];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuse = @"MainCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.backgroundColor = [UIColor clearColor];
        cell.contentView.backgroundColor = [UIColor clearColor];

        CGFloat cellW = tableView.frame.size.width;
        CGFloat margin = 16;
        CGFloat cardH = 84;

        // 卡片容器
        UIView *card = [[UIView alloc] initWithFrame:CGRectMake(margin, 8, cellW - margin * 2, cardH)];
        card.backgroundColor = [UIColor whiteColor];
        card.layer.cornerRadius = 14;
        card.layer.shadowColor = [UIColor blackColor].CGColor;
        card.layer.shadowOpacity = 0.08;
        card.layer.shadowOffset = CGSizeMake(0, 2);
        card.layer.shadowRadius = 8;
        card.tag = 1001;
        [cell.contentView addSubview:card];

        // 图标
        UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(16, (cardH - 52) / 2.0, 52, 52)];
        icon.layer.cornerRadius = 13;
        icon.clipsToBounds = YES;
        icon.contentMode = UIViewContentModeCenter;
        icon.tintColor = [UIColor whiteColor];
        icon.tag = 1002;
        [card addSubview:icon];

        // 标题
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(84, 18, card.frame.size.width - 84 - 40, 22)];
        title.font = [UIFont boldSystemFontOfSize:17];
        title.textColor = [UIColor darkGrayColor];
        title.tag = 1003;
        [card addSubview:title];

        // 副标题
        UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(84, 44, card.frame.size.width - 84 - 40, 18)];
        subtitle.font = [UIFont systemFontOfSize:13];
        subtitle.textColor = [UIColor lightGrayColor];
        subtitle.tag = 1004;
        [card addSubview:subtitle];

        // 箭头
        UIImageView *chevron = [[UIImageView alloc] initWithFrame:CGRectMake(card.frame.size.width - 28, (cardH - 18) / 2.0, 12, 18)];
        chevron.image = [UIImage systemImageNamed:@"chevron.right"];
        chevron.tintColor = [UIColor colorWithRed:0.80f green:0.82f blue:0.85f alpha:1.00f];
        chevron.contentMode = UIViewContentModeScaleAspectFit;
        chevron.tag = 1005;
        [card addSubview:chevron];
    }

    UIView *card = [cell.contentView viewWithTag:1001];
    UIImageView *icon = [cell.contentView viewWithTag:1002];
    UILabel *title = [cell.contentView viewWithTag:1003];
    UILabel *subtitle = [cell.contentView viewWithTag:1004];

    NSArray *titles    = @[@"Editor", @"Videos", @"Photos", @"Source", @"Web"];
    NSArray *subtitles = @[@"文本编辑器", @"视频管理", @"图片管理", @"列表与阅读", @"网页浏览"];
    NSArray *icons     = @[@"doc.text", @"video.fill", @"photo.on.rectangle", @"list.bullet", @"globe"];
    NSArray *colors    = @[
        [UIColor colorWithRed:0.20f green:0.47f blue:0.98f alpha:1.00f], // 蓝
        [UIColor colorWithRed:0.55f green:0.35f blue:0.80f alpha:1.00f], // 紫
        [UIColor colorWithRed:0.22f green:0.71f blue:0.42f alpha:1.00f], // 绿
        [UIColor colorWithRed:0.96f green:0.58f blue:0.13f alpha:1.00f], // 橙
        [UIColor colorWithRed:0.90f green:0.32f blue:0.29f alpha:1.00f], // 红
    ];

    title.text = titles[indexPath.section];
    subtitle.text = subtitles[indexPath.section];
    icon.image = [UIImage systemImageNamed:icons[indexPath.section]];
    icon.backgroundColor = colors[indexPath.section];

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    switch (indexPath.section) {
        case 0: { // 文本编辑器
            EditorController *vc = [[EditorController alloc] init];
            vc.title = @"Editor";
            [self.navigationController pushViewController:vc animated:YES];
            break;
        }
        case 1: { // 视频
            VideoCollectionController *vc = [[VideoCollectionController alloc] init];
            vc.title = @"Videos";
            [self.navigationController pushViewController:vc animated:YES];
            break;
        }
        case 2: { // 相册分组入口
            PhotoAlbumController *vc = [[PhotoAlbumController alloc] init];
            vc.title = @"Photos";
            [self.navigationController pushViewController:vc animated:YES];
            break;
        }
        case 3: { // Source 列表
            SourceController *vc = [[SourceController alloc] init];
            vc.title = @"Source";
            [self.navigationController pushViewController:vc animated:YES];
            break;
        }
        case 4: { // Web:直接挂到 window 显示全局网页视图(不 push 控制器)
            [WebBrowserView showOnWindow];
            break;
        }
        default:
            break;
    }
}

@end
