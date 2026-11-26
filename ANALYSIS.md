# FilzaReplacer 1.0.7 分析报告（Craft Anything Deep 模式）

分析对象：用户提供的 `1.0.7.ipa`（1,677,611 字节），解包于
`~/workspace/filza-clone/extracted/FilzaReplacer.app/`。
分析工具：`craft-anything-cli 0.6.1` Deep 模式（triage / strings / feature-find /
function-study / ObjC 类表）+ `strings` / Info.plist 直接读取。
分析时间：2026-11-26。**静态分析，未动态运行、未抓包。**

## 证据编号

| 证据 | 内容 |
|---|---|
| ev_33c0f9f1…030a6 | triage：Mach-O arm64，Swift，符号表已剥离 |
| ev_ab8571dd…ebcbab | 4 个 `api.php` 端点字符串及引用函数 |
| ev_50b3641b…9687ff | 6 个 ObjC/Swift 类 |
| ev_ae410142…5a01fe | `request_token` 功能追踪（1 个函数 sub_100040ab8） |
| strings_all.txt | `analysis/strings_all.txt`，二进制全部字符串（4638 行） |
| study_request_token.json | `analysis/study_request_token.json`，request_token 函数 dossier |

## 1. App 是干什么的

**一句话：短视频草稿视频替换工具。** 它扫描抖音 / 快手 / 小红书这三个
App 保存在手机里的“草稿”视频，让用户从相册选一个新视频，按草稿原有的
时间范围做分段处理后，写回草稿文件的位置（同名覆盖），这样在抖音等 App
里打开草稿，播放的就是替换后的视频。

证据：

- 类型名：`MediaReplaceApp`、`MediaReplaceViewModel`、`ReplaceEngine`、
  `ReplaceError`、`VideoSegmentProcessor`、`ProcessError`、`MediaFileInfo`、
  `PlatformChannel`、`SubChannel`、`ReplaceState`、`DeleteState`、
  `PickerDelegate`、`PickerError`、`FilePreviewSheet`、`MarqueeNoticeView`、
  `NoticeLoader`、`ContentView`、`ScaleButtonStyle`。
- 目标包名（字符串原文）：`com.ss.iphone.ugc.Aweme`、
  `com.ss.iphone.ugc.AwemeInhouse`、`com.ss.iphone.ugc.AwemeLite`（抖音）、
  `com.kuaishou.gifshow`（快手）、`com.xingin.discover`（小红书）。
- 容器根路径：`/var/mobile/Containers/Data/Application`、
  `/private/var/mobile/Containers/Data/Application`，容器识别靠读每个容器下
  的 `/.com.apple.mobile_container_manager.metadata.plist`（`MCMMetadataIdentifier`）。

### 草稿目录（字符串原文）

| 平台 | 相对路径 |
|---|---|
| 抖音 | `Documents/drafts`、`Documents/aweme_drafts`、`Documents/AwemeDrafts`、`Library/Application Support/drafts`、`Library/Caches/drafts` |
| 快手 | `Documents/Gifshow/Drafts`、`Library/Application Support/gifs` |
| 小红书 | `Documents/Post/Drafts`、`Documents/Post/drafts`、`Library/Application Support/Post/Drafts` |

另有 `Documents/draft`（单数）一个字符串，未确认属于哪个平台。

## 2. 身份与包信息（Info.plist，逐字）

- `CFBundleName` = FilzaReplacer；`CFBundleDisplayName` = 误闯天家
- `CFBundleIdentifier` = com.wuchuangtianjia.app
- `CFBundleShortVersionString` = 1.0；`CFBundleVersion` = 1
- `MinimumOSVersion` = 14.0；`UIDeviceFamily` = [1]（仅 iPhone）
- `UISupportedInterfaceOrientations` = 仅竖屏；`UIUserInterfaceStyle` = Dark
- `NSPhotoLibraryUsageDescription` = 需要访问相册以选择要替换的视频文件
- `NSAppTransportSecurity` = `NSAllowsArbitraryLoads: true`
- 构建环境：Xcode 2630，SDK iphoneos 26.2；主二进制 527,008 字节，arm64，
  `cryptid=0`（已解密，可直接读）；无内嵌 `_CodeSignature` 目录。
- 唯一权限就是相册；无后台模式、无 URL Scheme、无 IAP。

链接的系统库（triage）：Foundation、AVFoundation、CoreMedia、SwiftUI、
UIKit、Combine、Security、CoreGraphics、QuartzCore；无第三方库。

## 3. 完整使用流程（观察到的结构）

1. **启动**：`MediaReplaceApp` → `ContentView`（SwiftUI）。
   `NoticeLoader` 拉取 `https://xxb.zjwhcmxy.com/notice.txt`，用
   `MarqueeNoticeView` 以跑马灯形式显示公告。
2. **激活检查**：`TokenManager` 查本地缓存（见 §5），无效则向服务器
   `request_token`，再用 `verify` 校验；通过后才能用替换功能。
   （激活是原 App 自己的服务器验码，新 App 不需要它，见 §5。）
3. **选平台**：`PlatformChannel`（抖音 / 快手 / 小红书）+ `SubChannel`。
4. **扫草稿**：枚举 `/var/mobile/Containers/Data/Application` 下的容器，
   读 metadata plist 认出目标 App，再按上表相对路径找草稿目录，列出草稿
   视频（`MediaFileInfo`：`fileName`、`path`、`platform`、`isSelected`、
   `duration` 等字段名见字符串表）。
5. **预览**：点草稿进 `FilePreviewSheet` 预览。
6. **选替换视频**：`PickerDelegate` + `UIImagePickerController`
   （`UIImagePickerControllerMediaURL`）从相册选视频。
7. **分段处理**：开关 `enableSegmentProcess`（ViewModel 状态
   `_enableSegmentProcess`、`_isProcessingSegment`、`_showSegmentSheet`）；
   `VideoSegmentProcessor` 按草稿元数据的时间范围切分、重组替换视频。
8. **执行替换**：`ReplaceEngine` 把处理后的视频写回草稿文件位置，
   状态机 `ReplaceState`；另有删除草稿视频（`DeleteState`，
   SF Symbol `trash.circle.fill`）。
9. **结果**：成功 / 失败状态展示（`checkmark.circle.fill` /
   `exclamationmark.circle.fill` 等 SF Symbol）。

## 4. ReplaceEngine 与 VideoSegmentProcessor 的行为

### 4.1 分段规则

草稿元数据是 JSON，里面有时间范围字段。二进制里有以下正则模板
（字符串原文）：

- `"TargetTimeRange"\s*:\s*\{\s*"Duration"\s*:\s*\d+`
- `"TargetTimeRange":{"Duration":`
- `"SourceTimeRange"\s*:\s*\{\s*"Duration"\s*:\s*\d+`
- `"SourceTimeRange":{"Duration":`
- `"Duration"\s*:\s*\d+`、`"duration"\s*:\s*\d+`
- `"EndTime"\s*:\s*\d+`、`"StartTime"\s*:\s*\d+`

即：从草稿的 JSON 元数据里解析 `SourceTimeRange` / `TargetTimeRange`
（含 `Duration`、`StartTime`、`EndTime`），得到每一段的目标时间范围，
再对替换视频做相应切分与重组。**每段的具体时长规则（例如是否固定切
片、是否按原视频等比缩放）在静态分析中未确认**，标记为未确认。

### 4.2 视频处理管线（导入符号为证）

- `AVAsset`、`AVAssetTrack`、`AVMutableComposition`、
  `AVMutableVideoComposition`、`AVMutableVideoCompositionInstruction`、
  `AVMutableVideoCompositionLayerInstruction`、`AVMutableAudioMix`、
  `AVMutableAudioMixInputParameters`
- `insertTimeRange:ofTrack:atTime:error:`（把源视频的时间段插入合成轨道）
- `CMTimeRange`、`CMTime`、`CMTimeGetSeconds`、`kCMTimeZero`
- 导出：`AVAssetExportSession`，preset 为
  `AVAssetExportPresetPassthrough` 与 `AVAssetExportPreset1920x1080`
- 文件操作：`FileManager` 的 `contentsOfDirectoryAtURL` /
  `contentsOfDirectoryAtPath`、`copyItemAtURL:toURL:error:`、
  `createDirectoryAtURL`、`removeItemAtURL` / `removeItemAtPath`、
  `enumeratorAtURL`；属性列表读写 `CFPropertyListCreateWithData` /
  `CFPropertyListCreateFromXMLData`（读容器 metadata plist 与草稿 JSON）
- **输出写到哪里**：处理后的视频写回草稿目录内原视频文件的同名位置
  （替换），这是由“替换”这一行为与 `copyItemAtURL` / `removeItemAtURL`
  的组合推导出的结论，置信度为 derived；静态分析无法看到运行时的
  具体目标文件名，标记为未确认细节。

### 4.3 选视频

`UIImagePickerController` + `UIImagePickerControllerDelegate`，
取 `UIImagePickerControllerMediaURL`。仅声明了相册权限。

## 5. TokenManager / 激活流程（只写原 App 如何验证）

激活只走它自己的服务器，与替换逻辑本身无关。证据：

- 端点（字符串原文，ev_ab8571dd）：
  - `https://xxb.zjwhcmxy.com/api.php?action=verify`（引用函数 sub_10000a7e4）
  - `https://xxb.zjwhcmxy.com/api.php?action=unbind`（sub_1000099ac）
  - `https://xxb.zjwhcmxy.com/api.php?action=heartbeat`（sub_1000337b8）
  - `https://xxb.zjwhcmxy.com/api.php?action=request_token`（sub_100040ab8）
  - 公告：`https://xxb.zjwhcmxy.com/notice.txt`
- 请求方式：`NSURLSession dataTaskWithRequest`，`Content-Type:
  application/x-www-form-urlencoded`，`URLRequest httpMethod / httpBody`，
  `NSJSONSerialization` 解析返回；`request_token` 函数内还用了
  `Date.timeIntervalSince1970`（时间戳参与请求，疑似签名，细节未确认）。
- 设备标识：文件 `wctj_device_id.txt`，UserDefaults 键
  `com.wuchuangtianjia.deviceid`；缓存字段 `cachedToken`、`cachedNonce`、
  `cachedExpires`、`tokenSecret`；Keychain 用 `SecItemAdd` /
  `SecItemCopyMatching` / `SecItemDelete` 存取。
- 二进制内另有三段与 token 相关的硬编码字符串（字符串原文）：
  `tk_W7x2Nq9RmK4pTz6Y_secret_2026`、`W7x2Nq9RmK4pTz6Y`、
  `mK4pcH5nW7x2bL8s`。**新 App 不得复用这些值。**
- 错误类型：`TokenError`（含 `invalidToken` 字段名）。

**为什么新 App 不需要激活**：激活只是原 App 的商业锁，校验发生在它
自己的服务器上；替换功能本身是纯本地 AVFoundation + FileManager 操作，
不依赖服务器返回的任何数据。新 App 从设计上就不联网、不验证，因此不
存在“绕过验证”的问题。

## 6. UI 结构与关键字符串

- SwiftUI，`ContentView` 为主界面，`MediaReplaceViewModel` 为状态层
  （`@Published` 字段名：`_notice`、`_showSegmentSheet`、
  `_enableSegmentProcess`、`_isProcessingSegment`）。
- 子视图：`FilePreviewSheet`（预览）、`MarqueeNoticeView`（跑马灯公告）、
  `ScaleButtonStyle`（按钮样式）。
- SF Symbol（字符串原文）：`link.badge.minus`、`arrow.triangle.2.circlepath`、
  `checkmark.shield.fill`、`exclamationmark.circle.fill`、
  `checkmark.circle.fill`、`video.badge.plus`、
  `exclamationmark.triangle.fill`、`trash.circle.fill`、`xmark.circle.fill`。
- 可见文本字符串：二进制里**没有任何中文字面量**；可辨认的界面相关字面量
  只有 `TikTok` 与 `Token `（带尾空格，疑似标签前缀）。其余界面文案极
  可能以 SF Symbol / 图标为主，或来自服务器下发的 `notice.txt`。
  **原 App 的逐字界面文案标记为未确认**，新 App 使用自己的原创文案。
- 另有系统版本读取：读 `/System/Library/CoreServices/SystemVersion.plist`
  的 `ProductVersion`，格式化为 `%d.%d.%d`（用途未确认，疑似上报设备信息）。

## 7. 关键限制：原 App 能读别的 App 容器是有前提的

二进制内嵌的 entitlements（字符串原文）：

```xml
<key>platform-application</key><true/>
<key>com.apple.private.security.no-sandbox</key><true/>
<key>com.apple.private.security.storage.AppDataContainers</key><true/>
<key>com.apple.security.exception.files.absolute-path.read-write</key>
<array><string>/var/mobile/</string><string>/var/</string></array>
```

这是越狱 / 特殊侧载才有的权限组合：平台级应用、不走沙盒、可读写
`/var/mobile/` 与 `/var/` 下的绝对路径。**正常开发者签名或 App Store
的 App 拿不到这些权限**。因此：

- 在未越狱的普通 iPhone 上，原 App 的“扫描抖音草稿”功能本身也无法
  直接读到别的 App 的容器；新 App 同样受此限制。
- 新 App 的处理：保留同样的扫描路径实现（有权限时可用），扫不到时
  诚实提示原因；另提供“手动选择草稿文件夹”（UIDocumentPicker）与
  “仅本地处理并导出到相册/文件”两种在普通手机上可行的用法。详见
  `README.md`。

## 8. 未确认事项

1. 服务器请求/返回 JSON 的具体字段名（需动态抓包，未做）。
2. 分段处理每段的具体时长规则（见 §4.1）。
3. 替换写回时的具体目标文件名与是否保留原文件（见 §4.2）。
4. 原 App 界面的逐字文案（见 §6）。
5. `heartbeat` 的间隔与 `verify` 失败后的具体行为。
6. `ProductVersion` 读取结果的用途。

## 9. 结论

原 App = 草稿扫描（抖音/快手/小红书容器内草稿目录）+ 相册选视频 +
按草稿元数据时间范围分段处理（AVFoundation 合成导出）+ 写回替换，
外加一套独立的服务器激活锁。激活与核心功能解耦，去掉激活不影响
本地替换能力。新 App（`MediaReplace`，`com.cameron.mediareplace`）
按本报告 §3–§4 的本地行为干净重写，不联网、不验证、不使用原 App
的任何资源与标识；草稿扫描在普通手机上的权限限制如 §7 所述。
