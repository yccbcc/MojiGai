# WebBrowserView 功能与时机速览

全局网页浏览器模块（可重置静态单例，挂在 window 上），顶部按钮：**上一页 / URL / 主页 / 关闭 / copy / 下载 / 下一页**。

## 功能一览

| 功能 | 做什么 | 执行时机 |
|---|---|---|
| 单例常驻 | 关闭只是 `hide` 移出 window，实例保留，历史/缓存不丢，下次秒开 | 各入口（Main / Editor / Source）调 `sharedBrowser` / `showOnWindow` |
| 销毁重建 | `destroySharedBrowser`：停加载 → 断代理 → 释放实例 → 清空 WKWebView 全部网站数据（缓存/Cookie/localStorage） | 长按 Web 入口 |
| URL 恢复 | 记住最后访问网址，重建后自动加载（无记录则加载主页） | 每次导航提交/完成时写入 `lastWebURL`；`showOnWindow` 时读取 |
| m3u8 收集① | 注入 JS 监听 XHR / fetch / 媒体元素 src，URL 含 `.m3u8/.m3u` 或响应体以 `#EXTM3U` 开头即入候选（去重） | 页面加载时实时捕获（TSWebView 每页自动重注入） |
| m3u8 收集② | 正则解析 HTML 里 `<video>/<source>` 的 m3u8 地址，补充漏抓的静态地址 | 点「下载」按钮时 |
| m3u8 清理 | 清空候选列表与来源标识 | 主动 `loadURL:`、点击页内链接跳转（仅 LinkActivated 主框架）、下拉刷新；单条下载完成后只移除那一条 |
| 下载 m3u8 | 候选列表页选择 → ffmpeg 转 mp4 → 存入 `Documents/videos/<文件夹>`，「下载」按钮显示进度 | 点「下载」→ 选地址 → 选文件夹 |
| 地址栏下载 | URL 弹窗里点「下载」：`.m3u8` 走转码，`.mp4` 走 NSURLSession 直下（KVO 报进度），非视频提示 | URL 按钮弹窗内 |
| 防广告 | `target="_blank"` / `window.open` 弹窗：同主域名拉回当前页加载，跨域直接丢弃；主域名比较支持 `.com.cn/.co.uk` 等多段后缀 | `createWebViewWithConfiguration` 回调时 |
| copy | 页面纯文本复制到剪贴板（优先 `body.innerText`，空则 HTML 过滤结果） | 点「copy」按钮 |
| 前进/后退 | 按钮或右滑手势：有网页历史则返回上一页，否则触发关闭 | 点按钮 / 左边缘右滑 |
| 下拉刷新 | 清空 m3u8 候选后 reload | 网页下拉 |

## 协作关系

```
WebBrowserView（单例）
  ├── TSWebView：注入 JS → 实时捕获 m3u8
  ├── HTMLTextTool：HTML 解析补充 / 正文提取
  ├── M3U8DownloadController：候选列表选文件夹
  ├── ConvertVideoFormat：ffmpeg m3u8 → mp4
  └── VideoStore：入库 Documents/videos
```
