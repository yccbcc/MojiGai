# WKWebView 导航流程与 target=_blank 处理

> 适用文件：`Mojigai/WebBrowserView.m`、`Mojigai/UIKit/TSWebView.m`
> 说明对象：`WKNavigationDelegate` 的 `decidePolicyForNavigationAction` 与 `WKUIDelegate` 的 `createWebViewWithConfiguration` 两个回调，在不同导航场景下的触发时机与关键参数状态。

---

## 1. 两个核心回调的职责

### 1.1 `decidePolicyForNavigationAction`（导航决策）

```objc
- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler;
```

- **作用**：在 WKWebView **准备发起一次「同框架 / 主框架」导航前**调用，让你决定放行还是取消。
- **能拦到的导航**：首次加载、同窗口点链接、`location.href` 跳转、前进/后退、reload、服务端 302 重定向、`meta refresh`。
- **拦不到的导航**：**开新窗口的请求**（`target="_blank"`、`window.open()`）——那种走下面 1.2 的回调。
- **控制手段**：`decisionHandler(WKNavigationActionPolicyAllow)` 放行 / `...Cancel` 阻止。

### 1.2 `createWebViewWithConfiguration`（新窗口创建）

```objc
- (nullable WKWebView *)webView:(WKWebView *)webView
    createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
               forNavigationAction:(WKNavigationAction *)navigationAction
                    windowFeatures:(WKWindowFeatures *)windowFeatures;
```

- **作用**：当页面请求**打开一个新窗口/标签页**时调用。**WKWebView 默认不会自己开新窗口**，必须由本回调决定。
- **本项目处理方式**：不返回新窗口，而是 `return nil`，同时把请求 `loadRequest:` 到**当前 webview** 里，让 `target="_blank"` 表现为「在当前页打开」。

当前代码（`WebBrowserView.m`）：

```objc
- (nullable WKWebView *)webView:(WKWebView *)webView
    createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
               forNavigationAction:(WKNavigationAction *)navigationAction
                    windowFeatures:(WKWindowFeatures *)windowFeatures {
    if (!navigationAction.targetFrame.isMainFrame) {
        [webView loadRequest:navigationAction.request];   // 拉回当前页打开
    }
    return nil;
}
```

> ⚠️ 若去掉 `loadRequest` 改成「永远直接 `return nil`」，则 `target="_blank"` 点击**不会有任何反应**（新窗口不开、当前页也不跳）。这行 `loadRequest` 是让 `target="_blank` 有反应的**唯一来源**。

---

## 2. target=_blank 的完整跳转流程

```
用户点击 target="_blank" 链接 / 页面调用 window.open(url)
        │
        ▼
WebView 判定「这是一个开新窗口的请求」
        │   （此时 navigationAction.targetFrame == nil）
        ▼
触发 UI 回调：createWebViewWithConfiguration:forNavigationAction:...
        │
        ├── 检查 navigationAction.targetFrame.isMainFrame
        │       targetFrame 为 nil → 对 nil 发消息 → 返回 NO
        │       → !NO == YES → 进入分支
        ▼
执行 [webView loadRequest:navigationAction.request]   （在当前 webview 加载新 URL）
        ▼
这次 loadRequest 又触发一次：decidePolicyForNavigationAction
        │   navigationType == WKNavigationTypeOther（程序化加载）
        │   targetFrame == nil → isMainFrame == NO
        ▼
正常加载新页面，随后 didCommitNavigation / didFinishNavigation
```

**要点：**

1. `target="_blank"` **首先触发的是 `createWebViewWithConfiguration`**，不是 `decidePolicyForNavigationAction`。
2. 它的 `navigationAction.targetFrame == nil`，所以 `targetFrame.isMainFrame` 恒为 `NO`。
3. 我们把它转成 `loadRequest` 后，才产生一次 `navigationType == Other` 的常规导航决策。
4. 结论：`target="_blank"` 这条路**不会命中**「`isMainFrame && LinkActivated`」的清空条件，所以旧 m3u8 候选不会被清（靠 URL 去重兜底）。

---

## 3. 各场景的触发时机与关键参数状态

| 场景 | `createWebView...` | `decidePolicyForNavigationAction` | `navigationAction.targetFrame` | `targetFrame.isMainFrame` | `navigationType` | 是否清空 m3u8 |
|---|---|---|---|---|---|---|
| **首次打开网页**（`loadURL` / `loadSavedURLIfNeeded` / `showOnWindowWithURL`） | 不触发 | 触发一次（程序化 `loadRequest`） | nil | NO | `Other` | ✅ 在 `loadURL` 里主动清空 |
| **同窗口点链接**（普通 `<a>`） | 不触发 | 触发一次 | 主框架对象 | YES | `LinkActivated` | ✅ 命中 `isMainFrame && LinkActivated` |
| **`target="_blank"` / `window.open`** | ✅ 触发（入口在此） | 转成 `loadRequest` 后再触发一次 | nil（入口与转加载后均为 nil） | NO | 转加载后 `Other` | ❌ 不命中清空条件 |
| **页内 `location.href=...` 跳转** | 不触发 | 触发一次 | 主框架对象 | YES | `Other` | ❌ 不清（属前端/广告跳转，需按域名过滤才能拦） |
| **服务端 302 / meta refresh** | 不触发 | 触发（重定向链每一跳都会触发） | 主框架 | YES | `Other` | ❌ 不清 |
| **前进/后退**（`goBack`/`goForward` / 右滑） | 不触发 | 触发一次 | 主框架 | YES | `BackForward` | ❌ 不清（避免误删当前页候选） |
| **下拉刷新 / reload** | 不触发 | 触发一次 | 主框架 | YES | `Reload` | ✅ 在 `reloadClick` 里主动清空 |

> 说明：`navigationType == Other` 是一大类，涵盖程序化 `loadRequest`、前端 JS 跳转、重定向等，光靠它无法区分「正常跳转」和「广告自动跳转」，要区分只能靠 **URL / 域名黑名单**。

---

## 4. 关键参数速查

- **`navigationAction.targetFrame`**
  - 常规导航 / 首次加载 / 后退 / reload：指向主框架对象 → `isMainFrame == YES`
  - `target="_blank"`、`window.open`、程序化 `loadRequest`：为 **nil** → `isMainFrame == NO`（对 nil 发消息返回 NO）

- **`navigationAction.navigationType`（`WKNavigationType`）**
  - `LinkActivated`：用户点击链接（最接近「用户主动切换网址」的信号）
  - `Other`：程序化加载、`location.href`、302、meta refresh 等
  - `BackForward`：前进/后退
  - `Reload`：重新加载
  - `FormSubmitted` / `FormResubmission`：表单提交

- **`createWebViewWithConfiguration` 返回值**
  - 返回新 `WKWebView`：真正开新窗口（本项目未用）
  - 返回 `nil`：不开新窗口；是否加载新页取决于你有没有手动 `loadRequest`

---

## 5. 与 m3u8 候选清理策略的关系

本项目的清理逻辑分散在三处，覆盖「真正的页面切换」而避开会误删当前页候选的额外导航：

1. **`decidePolicyForNavigationAction`**：仅当 `isMainFrame && navigationType == LinkActivated` 时清空 → 只响应用户真正点链接同窗口跳转。
2. **`loadURL`**：主动加载新网址（地址栏 / 主页 / 外部传入 / 恢复上次 URL）时清空。
3. **`reloadClick`**：下拉刷新时清空。

**为什么不在所有主框架导航里都清空？**
因为重定向、前端 JS 跳转、前进/后退等 `Other` 导航可能在**当前页 m3u8 已被捕获之后**才触发，无差别清空会把刚抓到的地址抹掉，表现为「跳转后新页面的 m3u8 没捕获到」。

**已知缺口**：`target="_blank"` 经 `createWebViewWithConfiguration` → `loadRequest` 这条路不命中清空条件，旧候选会保留（URL 去重兜底，通常不影响使用）。如需补齐，可在 `createWebViewWithConfiguration` 的 `loadRequest` 前显式调用 `clearM3U8Candidates`。

m3u8 的**捕获**本身由 `TSWebView` 注入的 JS（`WKUserScript` + `AtDocumentStart`，`forMainFrameOnly:NO`）完成，**每个新页面自动重注入并重跑**，所以清空后新页面照常重新捕获。

---

## 6. 附：广告/自动跳转的控制点

| 行为 | 控制回调 | 手段 |
|---|---|---|
| 弹窗 / `window.open` | `createWebViewWithConfiguration` | 命中黑名单则 `return nil` 且不 `loadRequest` |
| 同窗口自动跳转（`location.href` 等） | `decidePolicyForNavigationAction` | 命中黑名单则 `decisionHandler(...Cancel)` |
| 302 / meta refresh | `decidePolicyForNavigationAction`（必要时 `decidePolicyForNavigationResponse`） | 同上按 URL 过滤 |
| JS `alert/confirm` 弹窗 | `WKUIDelegate` `runJavaScriptAlertPanel...` 等 | 忽略不调 completion |

**权衡**：`Cancel` 过激会误伤正常跳转，纯靠域名名单无法做到 100% 拦截。
