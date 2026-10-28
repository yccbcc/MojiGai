//
//  EditorController.m
//  MojiGai
//
//  Created by zhaohongbin on 2019/6/20.
//  Copyright © 2019 zhaohongbin. All rights reserved.
//

#import "EditorController.h"
#import "ReadTxtManager.h"
#import "HandleSystemFile.h"
#import "TextReplaceManager.h"
#import "TSToast.h"
#import "TxtStore.h"
#import "FileTool.h"
#import "WebBrowserView.h"

// Base64 解码为 UTF-8 明文字符串,失败返回 nil
static NSString *MojiDecodeBase64(NSString *base64) {
    NSData *data = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
    if (!data) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@interface EditorController ()
<
UITextFieldDelegate,
UITextViewDelegate,
UIScrollViewDelegate
>

@end

@implementation EditorController
{
    NSMutableArray *_mArr;

    UITextField *_nameTf;
    UITextField *_leftTf;
    UITextField *_rightTf;

    UITextView *_textView;

    float _searchOffset;
    NSInteger _strCount;

    HandleSystemFile *_handleManger;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.

    self.view.backgroundColor = [UIColor whiteColor];
    // 被 push 进导航控制器:页面不延伸到导航栏下方,布局以导航栏之下为起点
    self.edgesForExtendedLayout = UIRectEdgeNone;

    _handleManger = [[HandleSystemFile alloc] init];
    _handleManger.controller = self;
    _searchOffset = 0.0;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fileNotification:) name:@"FileNotification" object:nil];
    [self createUI];

    // 历史遗留清理:旧版导出会往 Documents/file_app 落副本,但沙盒不对外暴露、
    // app 内也无入口消费该目录,导出后就成了孤儿。现在改为临时目录暂存+导出即删,
    // 这里一次性删掉旧残留(仅首次进入 Editor 时执行)
    static BOOL legacyCleaned;
    if (!legacyCleaned) {
        legacyCleaned = YES;
        NSString *docs = [FileTool documentsDirectory];
        [FileTool deleteAtPath:[docs stringByAppendingPathComponent:@"file_app"] error:nil];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// viewDidLoad 时 view.bounds 仍是全屏高度;布局完成后(导航栏之下)再校准文本框,避免溢出屏幕底部
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (_textView) {
        CGFloat textMargin = 12;
        CGFloat textTop = 100;
        CGFloat w = self.view.bounds.size.width;
        // 底部按安全区(刘海屏 Home 指示条)留白,标准机型 safeAreaInsets.bottom=0
        CGFloat safeBottom = self.view.safeAreaInsets.bottom;
        _textView.frame = CGRectMake(textMargin, textTop, w - textMargin * 2, self.view.bounds.size.height - textTop - safeBottom - 12);
    }
}

#pragma mark - 处理外部打开文件(从系统"文件"App 分享进来,由本 app 打开该文件)

/*
 说明：本方法用于处理"从外部把文档带进 app"的两条路径：
   1) 系统「文件」App → 分享/用本 app 打开 → 复制进 Documents/Inbox → 触发本通知；
   2) app 内「导入」按钮(HandleSystemFile.readFile 用 UIDocumentPickerViewController)
      选中文件后也 post 同一个 FileNotification，走到这里读取并展示。

 当前状态：路径 2 正常使用；路径 1 已被停用——
 原因：Info.plist 中的 CFBundleDocumentTypes 已移除。原先声明了该键后，
       一旦从「文件」App 分享/打开 txt 进来，iOS 会把 app 的 Documents 目录
       暴露到「文件 → 我的iPhone → MojiGai」下(实测：刚安装不显示，导入一份
       txt 后即出现该文件夹，且里面多出导入的文档)。为隐藏 Documents 目录，移除之。
 影响：本方法不再被路径 1 触发，但路径 2 仍会用，故代码保留不动。

 重新启用路径 1 的方法：在 Mojigai/Info.plist 重新加回 CFBundleDocumentTypes 段：
 <key>CFBundleDocumentTypes</key>
 <array>
     <dict>
         <key>CFBundleTypeIconFiles</key>
         <array>
             <string>96.png</string>
             <string>96@2x.png</string>
         </array>
         <key>CFBundleTypeName</key>
         <string>com.myapp.common-data</string>
         <key>LSItemContentTypes</key>
         <array>
             <string>com.microsoft.powerpoint.ppt</string>
             <string>public.item</string>
             <string>com.microsoft.word.doc</string>
             <string>com.adobe.pdf</string>
             <string>com.microsoft.excel.xls</string>
             <string>public.image</string>
             <string>public.content</string>
             <string>public.composite-content</string>
             <string>public.archive</string>
             <string>public.audio</string>
             <string>public.movie</string>
             <string>public.text</string>
             <string>public.data</string>
         </array>
     </dict>
 </array>
 */
- (void)fileNotification:(NSNotification *)notifcation {
    NSDictionary *info = notifcation.userInfo;
    // fileName是文件名称、filePath是文件存储在本地的路径
    NSString *fileName = [info objectForKey:@"fileName"];
    NSString *filePath = [info objectForKey:@"filePath"];
    NSLog(@"fileName=%@  \nfilePath=%@", fileName, filePath);
    NSString *string = [ReadTxtManager readTxtWithPath:filePath txtName:fileName];
    if (!string) { //读取失败返回 nil：提示后不更新界面
        [TSToast show:@"文件读取失败"];
        return;
    }
    NSArray *names = [fileName componentsSeparatedByString:@"."];
    fileName = (names && names.count > 0) ? names.firstObject : fileName;
    _nameTf.text = fileName;
    _textView.text = string;

    // 清理导入产生的临时文件(系统可能放在 Documents/Inbox 或 Documents 根目录),避免留孤儿。
    // 只清理 Documents 下的非业务文件夹(Inbox/根目录临时文件),绝不碰 txts/images/videos 等业务数据
    if ([FileTool isImportedStagingCleanableAtPath:filePath]) {
        [FileTool deleteAtPath:filePath error:nil];
    }
}

#pragma mark - 保存到"文件"app

// 导出到系统「文件」App:正文先写进临时目录暂存,export picker 把副本落到用户自选位置后,
// 由 HandleSystemFile 在导出完成/取消时删掉暂存文件,不在沙盒留长期副本(内容仍在编辑器可再次导出)
- (void)saveToFileClick{
    if (_nameTf.text.length <= 0 || _textView.text.length <= 0) {
        return;
    }
    NSString *fileName = _nameTf.text;
    if (![fileName hasSuffix:@".txt"]) {
        fileName = [NSString stringWithFormat:@"%@.txt", fileName];
    }
    // 暂存到系统临时目录(非法字符/路径分隔符交由 FileTool 清洗)
    NSString *stageDir = NSTemporaryDirectory();
    NSString *stagePath = [FileTool resolveChildPath:fileName inDirectory:stageDir create:NO];
    if (!stagePath) {
        [TSToast show:@"文件名不合法"];
        return;
    }

    if (![_textView.text writeToFile:stagePath atomically:true encoding:NSUTF8StringEncoding error:nil]) {
        [TSToast show:@"导出失败"];
        return;
    }

    [HandleSystemFile shareInstance].controller = self;
    [[HandleSystemFile shareInstance] saveToFile:stagePath];
}

#pragma mark - textView代理

- (BOOL)textViewShouldBeginEditing:(UITextView *)textView{
    if (textView != _textView) {
        return NO;
    }
    return YES;
}

#pragma mark - textField代理

- (void)textFieldDidEndEditing:(UITextField *)textField{

    if (textField == _rightTf){
        NSString *_leftText = _leftTf.text;
        // 常量为 Base64 编码,使用前先解码成明文,否则替换会拿编码串去匹配
        NSString *rightText1 = MojiDecodeBase64(@"5byg5pS555Sf");
        NSString *rightText2 = MojiDecodeBase64(@"5LqR5bOw");
        NSString *_rightText = [_rightTf.text isEqualToString:@"1"] ? rightText1 : _rightTf.text;
        _rightText = [_rightText isEqualToString:@"2"] ? rightText2 : _rightText;
        if (_leftText.length > 0) {
            // 替换规则见 TextReplaceManager
            _textView.text = [TextReplaceManager replaceText:_textView.text leftText:_leftText rightText:_rightText];
        }
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField{
    [textField endEditing:YES];
    return YES;
}

#pragma mark - 键盘

- (UIToolbar *)keyboardToolbar {
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 44)];
    UIBarButtonItem *flexItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];

    UIView *closeView = nil;
    if (@available(iOS 13.0, *)) {
        // 系统自带的半透明圆底 X 按钮
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeClose];
        [closeBtn addTarget:self action:@selector(dismissKeyboard) forControlEvents:UIControlEventTouchUpInside];
        closeView = closeBtn;
    } else {
        closeView = [self customCloseButton];
    }
    UIBarButtonItem *closeItem = [[UIBarButtonItem alloc] initWithCustomView:closeView];
    toolbar.items = @[flexItem, closeItem];
    return toolbar;
}

// iOS 12 及以下: 自绘半透明圆底 X 按钮
- (UIView *)customCloseButton {
    UIButton *btn = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 28, 28)];
    btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.12];
    btn.layer.cornerRadius = 14;
    [btn setTitle:@"✕" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor colorWithRed:0.48 green:0.48 blue:0.48 alpha:1] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [btn addTarget:self action:@selector(dismissKeyboard) forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

#pragma mark - 事件

// 导入:读取本地文件到文本框(原"搜索"按钮)
- (void)searchClick{
    [self.view endEditing:YES];
    [HandleSystemFile shareInstance].controller = self;
    [[HandleSystemFile shareInstance] readFile];
    return;
}

- (void)fetchClick{
    if (_nameTf.text.length == 0) {
        return;
    }
    [self.view endEditing:YES];
    for (NSDictionary *dict in _mArr) {
        if ([dict[@"key"] isEqualToString:_nameTf.text]) {
            _textView.text = [TxtStore readValueForEntry:dict];
        }
    }
}

- (void)saveClick{
    [self.view endEditing:YES];
    if (_nameTf.text.length > 0) {
        if (![_mArr containsObject:_nameTf.text] && _textView.text.length > 0) {
            // 正文落盘到 Documents/txts,UserDefaults 只存轻量元数据(不再塞 value)
            NSMutableDictionary *entry = [@{@"key":_nameTf.text, @"offsety":@"0", @"readType":@"0"} mutableCopy];
            [TxtStore saveValue:_textView.text toEntry:entry];
            [_mArr addObject:entry];
            [[NSUserDefaults standardUserDefaults] setObject:_mArr forKey:@"names"];
        }
        _nameTf.text = @"";
    }
}

#pragma mark - 内嵌网页(统一使用 window 上的全局网页视图)

// 打开网页:直接显示挂到 key window 的全局 WebBrowserView(单实例,关闭再开保留原网页)
- (void)webClick {
    [self.view endEditing:YES];
    [WebBrowserView showOnWindow];
}

#pragma mark - tool

- (CGSize)sizeWithStr:(NSString *)str font:(UIFont *)font maxWidth:(CGFloat)width maxHeight:(CGFloat)height {
    NSMutableDictionary *attr = [NSMutableDictionary dictionary];
    CGSize maxSize = CGSizeMake(width, height);
    attr[NSFontAttributeName] = font;
    CGSize theSize = [str boundingRectWithSize:maxSize options:NSStringDrawingTruncatesLastVisibleLine | NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading attributes:attr context:nil].size;
    return CGSizeMake(ceil(theSize.width), ceil(theSize.height));
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    [self.view endEditing:YES];
}

#pragma mark - UI

// 统一样式的功能按钮(保存/获取/toFile/导入共用)
- (UIButton *)standardButtonWithTitle:(NSString *)title action:(SEL)action frame:(CGRect)frame{
    UIButton *btn = [[UIButton alloc] initWithFrame:frame];
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [btn setBackgroundImage:[UIImage imageNamed:@"redImage.png"] forState:UIControlStateHighlighted];
    btn.backgroundColor = [UIColor blueColor];
    btn.layer.cornerRadius = 8;
    btn.titleLabel.font = [UIFont systemFontOfSize:15];
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)createUI{
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    CGFloat margin = 16;   // 左右边距(对称)
    CGFloat gap = 8;       // 组件间距

    // 四个功能按钮(保存/获取/导入/导出)统一等宽
    CGFloat btnW = 64;
    // 第一行: 名称输入框(自适应宽) + 保存、获取、Web
    CGFloat nameW = screenW - margin * 2 - btnW * 3 - gap * 3;

    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(margin, 0, nameW, 40)];
    tf.placeholder = @"请输入";
    tf.returnKeyType = UIReturnKeyDone;
    tf.borderStyle = UITextBorderStyleRoundedRect;
    tf.font = [UIFont systemFontOfSize:14];
    tf.inputAccessoryView = [self keyboardToolbar];
    tf.delegate = self;
    [self.view addSubview:tf];
    _nameTf = tf;

    // 第一行按钮: 保存、获取、Web(Web 打开内嵌的网页视图)
    NSArray *firstRowTitles  = @[@"保存", @"获取", @"Web"];
    NSArray *firstRowActions = @[NSStringFromSelector(@selector(saveClick)),
                                 NSStringFromSelector(@selector(fetchClick)),
                                 NSStringFromSelector(@selector(webClick))];
    for (NSInteger i = 0; i < firstRowTitles.count; i++) {
        SEL action = NSSelectorFromString(firstRowActions[i]);
        CGRect frame = CGRectMake(margin + nameW + gap + i * (btnW + gap), 0, btnW, 40);
        UIButton *btn = [self standardButtonWithTitle:firstRowTitles[i] action:action frame:frame];
        [self.view addSubview:btn];
    }

    // 第二行: 检索、替换(自适应宽) + 导入、导出(与第一行同宽的 btnW)
    CGFloat tfW = (screenW - margin * 2 - btnW * 2 - gap * 3) / 2.0;
    UITextField *tf1 = [[UITextField alloc] initWithFrame:CGRectMake(margin, 50, tfW, 40)];
    tf1.placeholder = @"检索";
    tf1.returnKeyType = UIReturnKeyDone;
    tf1.borderStyle = UITextBorderStyleRoundedRect;
    tf1.font = [UIFont systemFontOfSize:14];
    tf1.inputAccessoryView = [self keyboardToolbar];
    tf1.delegate = self;
    [self.view addSubview:tf1];
    _leftTf = tf1;

    UITextField *tf2 = [[UITextField alloc] initWithFrame:CGRectMake(margin + tfW + gap, 50, tfW, 40)];
    tf2.placeholder = @"替换";
    tf2.returnKeyType = UIReturnKeyDone;
    tf2.borderStyle = UITextBorderStyleRoundedRect;
    tf2.font = [UIFont systemFontOfSize:14];
    tf2.inputAccessoryView = [self keyboardToolbar];
    tf2.delegate = self;
    [self.view addSubview:tf2];
    _rightTf = tf2;

    // 第二行右端: 导入(读取文件)、导出(保存到"文件"app,原 toFile) 与第一行按钮同宽
    UIButton *importBtn = [self standardButtonWithTitle:@"导入" action:@selector(searchClick) frame:CGRectMake(margin + tfW * 2 + gap * 2, 50, btnW, 40)];
    [self.view addSubview:importBtn];
    UIButton *exportBtn = [self standardButtonWithTitle:@"导出" action:@selector(saveToFileClick) frame:CGRectMake(margin + tfW * 2 + gap * 2 + btnW + gap, 50, btnW, 40)];
    [self.view addSubview:exportBtn];

    NSArray *arr = [[NSUserDefaults standardUserDefaults] valueForKey:@"names"];
    if (arr) {
        _mArr = [NSMutableArray arrayWithArray:arr];
    }else{
        _mArr = [@[] mutableCopy];
    }

    // 大文本编辑区:圆角 + 浅色背景 + 内边距
    CGFloat textMargin = 12;   // 左右留白,让圆角可见
    CGFloat textTop = 100;
    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(textMargin, textTop, screenW - textMargin * 2, self.view.bounds.size.height - textTop - 34)];
    textView.delegate = self;
    textView.inputAccessoryView = [self keyboardToolbar];
    textView.font = [UIFont systemFontOfSize:13];
    textView.textColor = [UIColor darkGrayColor];
    textView.backgroundColor = [UIColor colorWithRed:0.98f green:0.98f blue:0.97f alpha:1.00f]; // 浅米白
    textView.layer.cornerRadius = 10;
    textView.layer.borderWidth = 1;
    textView.layer.borderColor = [UIColor colorWithRed:0.88f green:0.88f blue:0.88f alpha:1.00f].CGColor;
    textView.clipsToBounds = YES;
    // 内边距:四周留白,底部多留(键盘弹出时可滚动查看最后几行)
    textView.textContainer.lineFragmentPadding = 0;
    textView.textContainerInset = UIEdgeInsetsMake(12, 12, 120, 12);
    [self.view addSubview:textView];
    _textView = textView;
}

@end
