# WKWebView 导航与网页下载全流程

> 适用文件：`Mojigai/WebBrowserView.m`、`Mojigai/UIKit/TSWebView.m`、`Mojigai/Tool/VideoStore.m`、`Mojigai/Tool/VideoDownloadTool.m`
>
> 行号基准：HEAD `748826e` 之上、含「iframe 响应误下载 + 销毁时取消下载」两处修复的当前工作区。行号会随改动漂移，**定位以方法名为准**。
>
> 与 `WKWebView导航与target-blank流程.md` 的分工：那份是 **target=_blank 弹窗策略 + m3u8 清理时机**的场景枚举速查表；这份讲**一次点击的完整执行链路**（含 frame 概念地基与 WKDownload 下载通路）。查场景去那份，理解机制看这份。

---

## 一、地基：frame 是什么

不先建立这个概念，后面「走当前页导航还是走新窗口」「渲染还是下载」的分叉看不懂。

### 1.1 frame = 一份独立 HTML 文档的显示区域

一个 `WKWebView`（它是个 UIView）**不等于**一个网页。它内部是一棵 frame 树：

```
WKWebView                          ← 一个 UIView，屏幕上一块
└── 主框架 main frame               ← 页面本体那份 HTML
     ├── iframe A                   ← 另一份完整文档（自己的 DOM / JS / 滚动区）
     │    └── iframe A-1            ← iframe 可以继续嵌套
     ├── iframe B（广告位）
     └── iframe C（隐藏，用来 POST 表单）
```

每个 frame 都是一份**完整、独立的文档**：自己的 URL、自己的 DOM、自己的 JS 运行环境、自己的 origin。

→ **一个 WKWebView 内可以有任意多个 frame；只有开新窗口才会多出一个 WKWebView。**

### 1.2 WKFrameInfo 是「名片快照」，不是 frame 本身

头文件明确它是 *transient, data-only object*——只描述，不能拿它操作页面。全部可用信息就四项：

| 属性 | 含义 | 典型用途 |
|---|---|---|
| `isMainFrame` | 我是不是这棵树的**根** | 区分「用户真的换了页」与「iframe 内部动了一下」 |
| `request` | 载入本 frame 的请求 | 取这个 frame 自己的 URL |
| `securityOrigin` | 协议 + 域 + 端口 | 同源判断 |
| `webView` | 属于哪个 WKWebView（weak） | 回到宿主视图 |

`isMainFrame` 只回答一个二元问题：**根，还是枝**。不要把它理解成「是不是主页面的 URL」。

### 1.3 targetFrame：这次导航「落在哪个 frame」

`WKNavigationAction` 里有一对 frame 属性，Apple 原文注释就是答案：

```objc
@property WKFrameInfo *sourceFrame;        // The frame requesting the navigation.  谁发起
@property (nullable) WKFrameInfo *targetFrame;  // The target frame, or nil if this is a new window navigation.  落在哪
```

`targetFrame` 有三态，取值由 HTML/JS 怎么写决定：

| HTML / JS 写法 | `targetFrame` | `isMainFrame` |
|---|---|---|
| 主页面点普通链接（无 target） | 主框架对象 | YES |
| **iframe 内**点普通链接 | 该 iframe 对象 | **NO** |
| `target="_self"` | 当前 frame 自己 | 视所处层级 |
| `target="_top"` / `_parent` | 主框架 / 父 frame | YES / 视层级 |
| `target="已存在的名字"` | 那个已存在 frame | 视情况 |
| `target="_blank"` | **nil** | — |
| `window.open(url)` | **nil** | — |
| `location.href = ...` | 当前 frame 自己 | 视所处层级 |

### 1.4 三条硬结论

1. **三态互斥派发**：一次导航只进其中一个回调。前两种（有 targetFrame）走 `decidePolicyForNavigationAction`；第三种（`nil`）走 `createWebViewWithConfiguration`——弹窗请求**不会**经过 `decidePolicyForNavigationAction`。
2. **iframe 的导航也打进同一个 WKWebView 的 delegate**：整棵 frame 树共用一个 `WKNavigationDelegate`。这就是代码里必须判 `isMainFrame` 的根本原因。
   > ⚠️ 此条依 Apple 文档口径，本项目未单独构造 iframe 场景在真机验证。
3. **`targetFrame == nil` 的含义是「目标 frame 还不存在，得新建」，不是「它不是主框架」。**

### 1.5 ObjC 的 nil 语义把「不存在」和「否」合并了（两次事故）

给 `nil` 发消息返回该类型的**零值**：对象返回 `nil`、`BOOL` 返回 `NO`、**结构体返回全零**。同一族语义在本项目咬过我们两次：

| 代码 | nil 时实际值 | 后果 |
|---|---|---|
| `!navigationAction.targetFrame.isMainFrame`（L611） | `nil.isMainFrame` → `NO`，取反 → `YES` | **恒真**。本回调里 `targetFrame` 必为 nil，这个 `if` 每次都进，属冗余防御，无害 |
| `[disposition rangeOfString:@"attachment"...].location != NSNotFound` | `[nil rangeOfString:]` → `NSRange{0,0}`，`location` 是 **0**，而 `NSNotFound` 是 `NSIntegerMax` | **恒真**。所有普通网页被当成附件下载、页面空白。已修（提交 `4bff5af`）：先判 `disposition.length > 0` |

**规则**：凡是「可能为 nil 的字符串 + `rangeOfString:` / `rangeOfCharacterFromSet:` + `.location != NSNotFound`」必须先判空；或改用 `containsString:`（在 nil 上返回 `NO`，安全）。

---

## 二、总览：一次点击要过两道分叉

第一道分叉是 **WebKit 内部按 `targetFrame` 三态派发**（不是我们写的判断）；第二道才是我们的业务判断。

```
用户在网页里点击 / 提交表单 / JS 跳转
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│ WKWebView 内部：按「目标 frame 是谁」派发（三选一，互斥）      │
└───────────────────────────────────────────────────────────────┘
      │                        │                                │
 targetFrame = 主框架      targetFrame = iframe            targetFrame = nil
 (普通链接、location.href、  (iframe 内部导航——            (target="_blank" /
  表单提交到当前页)          同样走左边这个回调)             window.open)
      │                        │                                │
      └────────────┬───────────┘                                ▼
                   ▼                          ┌────────────────────────────────┐
   ┌───────────────────────────────┐          │ createWebViewWithConfiguration  │ L607
   │ decidePolicyForNavigationAction│ L661    │  !targetFrame.isMainFrame →     │
   │  isMainFrame && LinkActivated  │          │   进入「新窗口」处理分支         │
   │   → 清 m3u8 候选                │          │  （因 nil.isMainFrame==NO，恒进）│
   │  恒 return Allow                │          └────────────────────────────────┘
   └───────────────────────────────┘                    │              │
        │                                搜索引擎页 或 同主域      其它（跨域）
        ▼                                          │                 │
   发出网络请求                        clearM3U8Candidates      NSLog("拦截跨域弹窗")
   （302 链由 WebKit 自动跟随，        [webView loadRequest:]    return nil
     未实现 willPerformHTTPRedirection   = 拉回当前页，重新走       ▼
     ⇒ 一律跟随；                       一遍下面的主框架流程）  【情况2：被拒绝，无反应】
     decidePolicyForNavigationResponse                        │
     只对「最终响应」回调一次）                   └─── 拉回后回到本图顶部继续走
        ▼                                                       │
┌──────────────────────────────────────────────────────────────┐│
│ decidePolicyForNavigationResponse                  L716 ◄─────┘│
│ @available(iOS 14.5, *)                                        │
│ isAttachment = Content-Disposition 含 "attachment"              │
│ 命中条件： isAttachment                                        │
│         || ( !canShowMIMEType && isForMainFrame )              │
└──────────────────────────────────────────────────────────────┘
      │ 否（可渲染的 HTML/图片/pdf/mp4…）      │ 是
      ▼                                        ▼
┌──────────────────────────┐      ┌────────────────────────────┐
│ PolicyAllow              │      │ PolicyDownload             │
│ didCommit → didFinish    │      │ 页面不渲染，内容转为文件     │
│ 注入 JS 抓 HTML/innerText │      └────────────────────────────┘
│ → pageHTMLString/result  │                 ▼
└──────────────────────────┐     【情况3：点击后下载】
   【情况1：正常跳转】        │
                            │
   ※ 本回调对「主框架」和「iframe」的响应都会触发，故「渲染不了」这一半
     已用 isForMainFrame 限定到主框架；只有服务器明标 attachment 才对 iframe 生效
```

三种结局就是这两道分叉的组合：

| 结局 | 等价条件 |
|---|---|
| 情况 1 正常跳转 | 未被闸门 1 丢弃 **且** 闸门 2 判为可渲染 |
| 情况 2 毫无反应 | 闸门 1 丢弃（跨域弹窗） |
| 情况 3 变成下载 | 未被闸门 1 丢弃 **且** 闸门 2 判为附件/不可渲染 |

---

## 三、情况 1：正常跳转

| 步骤 | 回调（行号） | 我们做了什么 |
|---|---|---|
| 1 | `decidePolicyForNavigationAction:` L661 | 仅当 `targetFrame.isMainFrame && navigationType == LinkActivated`（真·点击链接）才 `clearM3U8Candidates`；重定向 / JS 跳转 / 前进后退（`Other`）**故意不清**，避免误删刚抓到的 m3u8 |
| 2 | 同上 L670 | 恒 `PolicyAllow` |
| 3 | 请求发出，跟随重定向 | 无回调（未实现重定向委托） |
| 4 | `decidePolicyForNavigationResponse:` L716 | `canShowMIMEType == YES` 且无 `attachment` → `PolicyAllow` |
| 5 | `didCommitNavigation:` L816 | `recordLastURL`（回退到缓存页可能不触发 didFinish，这里兜底） |
| 6 | `didFinishNavigation:` L821 | `endRefresh` 收尾下拉圈、`recordLastURL`、注入取 `document.documentElement.innerHTML` → `pageHTMLString` + `resultString`，再取 `body.innerText` 覆盖 `resultString` |

**Google 搜索结果点击属于这一类，但多走一步 L607**：结果是 `target="_blank"`，因为当前页主域的品牌段命中搜索引擎白名单（`google` / `bing` / `baidu` / `sogou`），被 `loadRequest:` **拉回当前 webview**；随后从第 1 步重走一遍。此时 `navigationType` 已变为 `Other`，所以拉回前（L617）必须显式清一次候选，不能靠第 1 步那条判断。

两个域名辅助方法：

- `mainDomainForURL:` L641：host 转小写，默认取末尾两段；若末尾两段命中多段公共后缀表（`com.cn` / `co.uk` / `com.jp` …）则多取一段。使 `a.bilibili.com` 与 `www.bilibili.com` 都归为 `bilibili.com`。
- `isSearchEngineURL:` L628：取主域最前面的**品牌段**比对白名单，故 `google.com` / `google.co.jp` / `google.com.hk` 都算 `google`，不必逐国域名枚举。

---

## 四、情况 2：被拒绝，没反应

**唯一入口**：`createWebViewWithConfiguration:` L607-L624 里条件全落空的 else 分支。

```
新窗口请求（target="_blank" / window.open，targetFrame == nil）
   ├─ 当前页是搜索引擎？  ──────否──┐
   └─ 新地址主域 == 当前主域？ ──否──┤→ NSLog("拦截跨域弹窗: <url> (当前主域: <domain>)")
                                    ↓
                            return nil（WKWebView 不建任何窗口，也不 loadRequest）
                                    ↓
                          用户看到：点了没有任何反应
```

三个特征：

1. **只有新窗口请求会被拒**，同页跳转（主框架或 iframe）永远 Allow。
2. **无任何 UI 反馈**，只有一行 NSLog —— 这就是「有时点不动」最难自查的地方。
3. 同域判定用 `mainDomainForURL:`（忽略子域、正确处理多段公共后缀）。

两个边界情形（同样表现为"点了没反应"）：

- **`window.open('')` 再 `document.write()`**：请求 URL 是 `about:blank` → `host` 为空 → 主域为空 → `sameDomain` 为 NO → 被丢弃 → 我们 `return nil` → 页面 JS 拿到 `null` 抛异常 → 按钮彻底失效。
- **非 http(s) scheme**（`tel:` / `mailto:` / 自定义 scheme）走 `_blank` 时同样被域名判定吞掉；走主框架的虽放行，但 WKWebView 不会代你打开外部 App。

---

## 五、情况 3：点击后下载（WKDownload 通路）

| 步骤 | 回调（行号） | 行为 |
|---|---|---|
| 1 | `decidePolicyForNavigationResponse:` L716 | 命中 `isAttachment \|\| (!canShowMIMEType && isForMainFrame)` → `PolicyDownload`（**不再渲染，页面留在原地**） |
| 2 | `navigationResponse:didBecomeDownload:` L747 | WebKit 造出 `WKDownload` 交给我们 → `download.delegate = self`（不设拿不到任何后续回调）+ 登记进 `activeDownloads` L684，以便销毁时能取消 |
| 3 | `download:decideDestinationUsingResponse:suggestedFilename:` L755 | 空名兜底「未命名文件」→ `lastPathComponent` 只取末段（防 `/` 路径穿越）→ `uniqueDestinationURLForFilename:` L703 重名按 `(1)(2)…` 顺延 → 目标 `Documents/videos/downloads/`；同时把 `download → destination` 存进 `NSMapTable` |
| 4 | —（无回调） | WebKit **直接把字节写进我们给的文件**，中间没有 tmp 文件，也不需要自己搬 |
| 5a | `downloadDidFinish:` L770 | 从 map 取回地址 → Toast「已下载: 文件名 / 保存到: 相对 Documents 路径」→ 移出 map 与 `activeDownloads` |
| 5b | `didFailWithError:resumeData:` L781 | Toast 失败 + 清两处登记；`resumeData` **被丢弃**（没接 `resumeDownloadFromResumeData:`）；无 resumeData 时顺手删掉截断文件 |

**为什么第 3 步要额外记 map**：这套 SDK 里完成回调是 `downloadDidFinish:`，**不像旧版 `didFinishDownloadingToURL:` 会把 URL 给你**，所以必须自己记住落盘地址。map 用 **weak key**，下载对象一释放条目自动消失，不累积、无需手动清扫。

**闸门 2 的三个要点**：

1. `@available(iOS 14.5, *)` 是策略式下载 API 的下限。低于该版本静默回落成 `Allow`，附件下载表现为「点了没反应」。
2. `canShowMIMEType == NO` 时若回 `Allow`，导航会**直接失败**；转 `Download` 才是正确处置。
3. 本回调**对主框架与 iframe 的响应都会触发**（见 §1.4 结论 2），所以两种语义必须分开：服务器明标 `attachment` 时**不限 frame**（无论来自哪都是用户意图的真下载）；仅「渲染不了」时必须加上 `isForMainFrame`，否则隐藏 iframe 的 XML/JSON 回调响应会被偷偷存成文件。

✅ **两个曾经确定会做错事的点（本轮已修）**：

```
修复 1：闸门 2 的「渲染不了」分支补上 navigationResponse.isForMainFrame
     修前：隐藏 iframe 的 POST / JSON / XML 响应也被劫持成下载
              → 主框架不动、iframe 不可见 ⇒ 表现成「点了没反应」
              → 并在 downloads 里堆垃圾文件
     修后：`isAttachment || (!canShowMIMEType && isForMainFrame)`（L734-L735）

修复 2：`activeDownloads`（NSHashTable weak，L684）+ destroySharedBrowser 返回值
     修前：WKDownload.delegate 是 weak，destroySharedBrowser(L196) 把代理置 nil
              → 长按重置 Web 时进行中的下载静默失联，沙盒里留半截文件
     修后：接管即登记 → 先取回各 download 的落盘地址 → 逐个 `cancel:` → 删掉已写了一半的
              截断文件 → 回传被取消个数（NSUInteger）
              → MainController L59 拼进 Toast：「已销毁网页并清空缓存 / 取消了 N 个进行中的下载」
              （TSToast 是同位置叠 label，分两条弹会重叠，所以只合成一条）

附带修正：截断文件不只销毁时会产生。WebKit 直接往 destination 写字节、没有 tmp 中转，
任何失败都会在 downloads 留下打不开的半截文件（偏偏还能是 .mp4 这类会被视频列表认出来的名字）。
故 `didFailWithError:`（L781）也在 `resumeData == nil` 时删目标文件；有 resumeData 则保留——
那半截文件是续传凭据，即便本项目当前没接续传也不该擅自销毁。
```

---

## 六、落盘目录的选择与副作用

`VideoStore.folderNames` 只列 `Documents/videos/` 下的**子目录**。所以下载目录刻意定成 `downloadsDirectory` L693 = `[VideoStore videosDirectory]` + `downloads`，即 `Documents/videos/downloads/`：

- **收益**：`downloads` 自动作为一个普通文件夹出现在视频列表里，下载完直接可见可管 —— 因此原先「扫 Documents 根目录散落视频」的**扫描功能判定为多余并已移除**。
- **对照**：早先版本落在 `Documents/downloads/`，与 `videos` 是同级兄弟，视频列表永远不会读到它，才让人误以为"下载的东西不见了"。
- **副作用**：非视频文件（zip/pdf）也会落进 `videos/downloads/`，但被 `VideoStore.isVideoName:` 过滤，列表里看不到、也就无法在 UI 中删除。

**和 Chrome 的差异**：Chrome 的下载能出现在「文件 → 我的iPhone → Chrome」，是因为它写进自己沙盒 `Documents/` 并声明了 `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`。本项目**刻意不暴露** Documents（`CFBundleDocumentTypes` 已移除，理由见 `EditorController.m` 注释）。要把单个文件送出去，走视频列表长按的「导出到文件」（`UIDocumentPickerViewController` export 模式），点对点导出、不开放整个沙盒。

---

## 七、三种出口的判定条件汇总

| 出口 | 精确条件 | 代码 |
|---|---|---|
| 1 正常跳转 | 主框架**或** iframe 导航 **且** （`canShowMIMEType` **且** 无 `attachment`） | L661 / L734-L742 |
| 2 被拒绝 | 新窗口请求（`targetFrame == nil`） **且** 非搜索引擎页 **且** 跨主域 | L611-L621 |
| 3 转下载 | （**任意 frame** 且 `Content-Disposition` 含 `attachment`）**或**（**仅主框架** 且 `canShowMIMEType == NO`），且系统 ≥ iOS 14.5 | L719-L740 |

> **第四条通路（不在上表内）**：顶部「下载」按钮 / 地址栏弹窗「下载」是**纯手动**通路 —— `downloadClick:` L436 → M3U8DownloadController → `VideoDownloadTool`（m3u8 走 ffmpeg 转 mp4，mp4 走 `NSURLSession` 直下 + KVO 真实字节比），落 `Documents/videos/<用户选的文件夹>`，**完全不经过任何 navigation 回调**。
> 区分记忆：**手动通路 = 只处理视频、有进度、用户选文件夹；自动通路 = 点击触发、任意文件类型、无进度、固定进 downloads。**

---

## 八、当前已知缺口（代码现状，非推测）

| # | 缺口 | 现象 | 依据 |
|---|---|---|---|
| 1 | 跨域弹窗静默丢弃 | 用户看不到被拦，只能查控制台 | `createWebViewWithConfiguration` else 分支（L620） |
| 2 | 无进度、无取消 | 大文件下载期间界面无反馈 | SDK 移除 `didUpdateProgress`，需改用 `download.progress`（`NSProgressReporting`） |
| 3 | `resumeData` 丢弃 | 失败后无法续传 | `didFailWithError` 未保存 |
| 4 | `blob:` / `data:` 不支持 | 不走 `WKNavigationResponse`，点了无反应 | 无相关分支 |
| 5 | iOS < 14.5 无反应 | `@available` 保护后静默回落 `Allow` | L719 |
| 6 | 非视频文件混入 downloads | 落了盘但被 `isVideoName` 过滤，UI 里看不到也删不掉 | `VideoStore.isVideoName:` |

> 原先列在表首的两条 —— 「闸门 2 未判 `isForMainFrame`」与「单例销毁断代理」—— 已修，细节见 §五 末尾的修复记录。

---

## 九、速查：回调 → 关键参数 → 本项目的处理

| 回调 | 协议 | 触发时机 | 关键参数 | 本项目做什么 |
|---|---|---|---|---|
| `createWebViewWithConfiguration:` L607 | `WKUIDelegate` | 新窗口请求（`targetFrame == nil`） | `request.URL`、当前页 `webView.URL` | 搜索引擎/同主域 → 清候选 + 拉回；否则丢弃并 NSLog；恒 `return nil` |
| `decidePolicyForNavigationAction:` L661 | `WKNavigationDelegate` | 主框架**与 iframe** 导航发起前 | `targetFrame.isMainFrame`、`navigationType` | 仅 `isMainFrame && LinkActivated` 清候选；恒 `Allow` |
| `decidePolicyForNavigationResponse:` L716 | `WKNavigationDelegate` | 最终响应到达、渲染前（主框架与 iframe 都会） | `canShowMIMEType`、`Content-Disposition`、`isForMainFrame` | `attachment` 或（不可渲染且**主框架**）→ `PolicyDownload`；否则 `Allow` |
| `navigationResponse:didBecomeDownload:` L747 | `WKNavigationDelegate` | 上一行选了 Download | `WKDownload` 对象 | `delegate = self` + 登记 `activeDownloads` |
| `download:decideDestinationUsingResponse:...` L755 | `WKDownloadDelegate` | 下载需要落盘位置 | `suggestedFilename` | 三层防护后给 `videos/downloads/<唯一名>`；存 map |
| `downloadDidFinish:` L770 | `WKDownloadDelegate` | 完成 | **无 URL**（故需查 map） | Toast 文件名 + 相对路径；清两处登记 |
| `download:didFailWithError:resumeData:` L781 | `WKDownloadDelegate` | 失败 / 取消 | `error`、`resumeData`（丢弃） | Toast 失败 + 清两处登记 |
| `didCommitNavigation:` L816 / `didFinishNavigation:` L821 | `WKNavigationDelegate` | 内容开始提交 / 加载完成 | `webView.URL` | `recordLastURL`；完成时再取 HTML / innerText 供「下载」「copy」用 |
| `loadURL:` L301 / `reloadClick` L405 | — | 代码主动加载 / 下拉刷新 | — | 这两处各自主动清 m3u8 候选 |

## 十、术语表

| 术语 | 定义 |
|---|---|
| **frame** | 一份独立 HTML 文档的显示区域；一个 WKWebView 内构成一棵树，树根是主框架 |
| **main frame（主框架）** | frame 树的根，页面本体；`isMainFrame == YES` |
| **subframe（子框架）** | iframe 及其后代；`isMainFrame == NO`，但仍共用宿主 WKWebView 的 delegate |
| **`sourceFrame`** | 发起这次导航的 frame |
| **`targetFrame`** | 导航结果落在哪个 frame；**`nil` 表示目标尚不存在（新窗口请求）** |
| **`isForMainFrame`** | `WKNavigationResponse` 上由 WebKit 预算好的同类布尔，无需自己比对象；本项目已用它把「渲染不了→下载」限定到主框架（L734-L735） |
| **`navigationType`** | 导航诱因：`LinkActivated`（点链接）/ `Other`（程序化加载、JS 跳转、302、meta refresh）/ `BackForward` / `Reload` / `FormSubmitted` |
| **`canShowMIMEType`** | WebKit 能否原生内联渲染该响应的 MIME 类型；`NO` 时回 `Allow` 会导致导航失败 |
| **`WKDownload`** | iOS 13.4+ 的下载对象，承载一次「响应 → 文件」的写入；本项目用策略式方式创建（§五） |
| **SDK 27.1 已移除的相关 API** | `downloadWithDelegate:` → 用 `PolicyDownload` + `didBecomeDownload`；`didFinishDownloadingToURL:` → `downloadDidFinish:`；`didUpdateProgress:` → `download.progress`；`WKDownload.request` → `originalRequest` |
