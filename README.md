# MediaReplace（媒体替换）

本地短视频草稿替换工具：扫描抖音 / 快手 / 小红书的草稿视频，从相册选一个替换视频，按草稿元数据里的时间范围做分段处理，再把处理后的视频写回草稿文件位置，之后在对应 App 里打开草稿就能看到新视频。

## 和原 App 的关系

本工程是对同类工具的**干净重写**：只复现了公开观察到的本地媒体替换功能，全部代码均为新写。

- **无激活、无联网**：没有任何网络请求代码，不连接任何服务器，不验证、不绑定、不心跳。
- **无原 App 资产**：没有使用原 App 的图标、品牌名、文案或任何美术资源。图标为本工程原创（深色底 + 青色播放 / 替换箭头几何图形），显示名“媒体替换”，包名 `com.cameron.mediareplace`。
- **改进**：替换前会把原草稿视频备份为同名 `.bak` 文件（原 App 未证实有备份功能）。

## 功能

- **扫描草稿**：按已知包名和相对路径枚举 `/var/mobile/Containers/Data/Application/` 下的容器，通过 `.com.apple.mobile_container_manager.metadata.plist` 的 `MCMMetadataIdentifier` 识别归属 App，再按相对路径找草稿视频。
  - 抖音：`com.ss.iphone.ugc.Aweme` / `AwemeInhouse` / `AwemeLite`，`Documents/drafts`、`Documents/aweme_drafts`、`Documents/AwemeDrafts`、`Library/Application Support/drafts`、`Library/Caches/drafts`
  - 快手：`com.kuaishou.gifshow`，`Documents/Gifshow/Drafts`、`Library/Application Support/gifs`
  - 小红书：`com.xingin.discover`，`Documents/Post/Drafts`、`Documents/Post/drafts`、`Library/Application Support/Post/Drafts`
- **选择草稿文件夹**：用系统文件选择器手动指定一个草稿目录（例如通过文件 App 共享出来的目录），拿到访问权限后同样扫描和替换。
- **仅本地处理并导出**：不依赖草稿也能用——选视频 → 分段处理 → 通过分享 Sheet 保存到相册或文件。
- **分段处理**：读取草稿 JSON 元数据里的 `SourceTimeRange` / `TargetTimeRange` / `Duration` / `StartTime` / `EndTime`，用 AVFoundation（`AVMutableComposition` + `insertTimeRange` + `AVMutableVideoComposition` / `AVMutableAudioMix` + `AVAssetExportSession`）按时间范围切段导出；分段开关关闭时整段导出；导出分“原画质直通”和“1080p”两档。
- **预览与管理**：草稿视频预览、替换视频选择（PHPicker）、删除草稿视频。

## 在 Mac 上打开工程

1. 需要一台 Mac + Xcode 16（或更新）。
2. 打开 `MediaReplace/MediaReplace.xcodeproj`。
3. 在 Target 的 Signing & Capabilities 里填入自己的 Development Team（工程里留空）。
4. 选择一台真机或模拟器，运行（⌘R）。

## GitHub Actions 打包

仓库自带工作流 `.github/workflows/build-ipa.yml`：在 `macos-14` runner 上用 `xcodebuild archive`（`CODE_SIGNING_ALLOWED=NO`，不签名），把 `.app` 打包成 `Payload/MediaReplace.ipa` 并作为 artifact 上传。

在 GitHub 上：推送到 `main` 分支（或手动触发 Actions → Build IPA），在运行记录里下载 `MediaReplace-unsigned-ipa`。

## 签名安装到手机

工作流产出的是**未签名**的 IPA，不能直接安装，需要自己签名，例如：

- 用 Xcode 打开工程，填好自己的 Team 和包名，直接真机运行安装；或
- 用自己的开发者证书 / 侧载工具（如 AltStore、Sideloadly 等）对 IPA 重新签名后安装。

## 已知限制（请先读）

- **草稿扫描在未越狱手机上扫不到**：原工具能读其他 App 的容器，是因为它带了越狱 / 侧载专用的 entitlements（`platform-application`、`com.apple.private.security.no-sandbox` 等）。正常开发者签名的 App 拿不到这些权限，在未越狱手机上直接扫描会返回空列表，App 会如实提示原因。请改用“选择草稿文件夹”或“仅本地处理并导出”模式。
- **仅竖屏**，最低支持 iOS 14。
- **工程未在本机编译过**：本工程是在 Linux 机器上编写的，没有 Xcode，无法本地编译；第一次编译以 GitHub Actions 的 macOS runner 结果为准。如 CI 报错，请把日志发回，按日志修。
- 替换前请确认草稿 App 已完全退出；写回后重新打开对应 App 查看草稿。
- `.bak` 备份文件和原草稿在同一目录，确认替换无误后可自行删除。
