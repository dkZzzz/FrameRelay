# FrameRelay 完整执行计划

本文件是项目的执行版计划。它不是建议清单，执行 agent 必须按顺序执行、按
固定命令执行、按验收条件停留。任何未解决问题都必须写入
`docs/STATUS.md`，不能只留在聊天上下文中。

## 1. 目标和不可变边界

唯一目标是：在 iPhone 15 Pro Max 上打开“控制中心 → 屏幕镜像”，选择
`FrameRelay`，让手机画面进入一个普通、可移动、可调整大小的 macOS 窗口，随后
由抖音直播伴侣的“窗口捕获”捕获这个窗口。

链路固定为：

```text
iPhone 控制中心“屏幕镜像”
    -> Bonjour/mDNS 发现 FrameRelay
    -> uxplay-core.dylib
    -> AirPlay Legacy Mirror 接收
    -> GStreamer 解码
    -> UxPlay avlayer
    -> AVSampleBufferDisplayLayer
    -> FrameRelay VideoHostView
    -> 独立 NSWindow
    -> 抖音直播伴侣“窗口捕获”

音频链路：

```text
iPhone AirPlay audio RTP
    -> uxplay-core.dylib AirPlay audio decrypt/receive
    -> GStreamer AAC/ALAC decoder
    -> audioconvert/audioresample/volume
    -> osxaudiosink
    -> Mac 默认音频输出设备
```
```

固定事实：

- iPhone 由手指触控操作；Mac 不接管 iPhone。
- Mac 不进入全屏，Mac 仍可操作抖音直播伴侣。
- 抖音只捕获 FrameRelay 窗口，不捕获整个桌面。
- 当前开发阶段同时处理视频和手机音频；手机音频输出到 Mac 默认音频设备。
- 抖音直接读取 Mac 麦克风；FrameRelay 不申请麦克风权限。
- 不使用 QuickTime Player、macOS `iPhone Mirroring`、ReplayKit iPhone App、
  OBS、ScreenCaptureKit、虚拟摄像头或外部 UxPlay 子进程。
- 不使用 SwiftUI、Rust 宿主、第三方 Swift 依赖或云服务。
- 真实协议验收必须在 iPhone 15 Pro Max / iOS 26.5 上完成；能编译不等于能连接。
- 如果实际 iOS 26.5 设备不能发现、连接或持续收视频，必须停止在协议门禁，写入
  `BLOCKED_PROTOCOL_IOS_26_5`，不得悄悄切换技术路线。

项目根目录固定为：

```text
/Users/danko/workspace/FrameRelay
```

当前 `/Users/danko/workspace/chat` 和其中的 `TokChan` 不属于项目范围，任何
阶段都不得修改。

## 2. 固定环境和版本

```text
Mac: MacBook Pro 2021, Apple M1 Pro, arm64
macOS: 26.5
iPhone: iPhone 15 Pro Max
iOS: 26.5
Swift: 6.2，当前主机工具链为 Apple Swift 6.2.3
Deployment target: macOS 26.0
UI: AppKit 原生窗口
```

AirPlay 引擎固定为：

```text
Repository: https://github.com/Recluse/UxPlay.git
Branch: popyachsa-integration
Commit: 587111368390479b7f65feb881c9257c02e508b5
Output: uxplay-core.dylib
```

本项目允许的上游补丁只有 `patches/` 中明确保存并由构建脚本应用的补丁。
补丁不能改变引擎路线，不能将 core 改为子进程，不能让 pinned commit 漂移。

设备名称和选项固定为：

```text
Device name: FrameRelay
Options: -p 47000 -nh -as osxaudiosink -vs avlayer -fps 60 -reset 8 -nofreeze -nohold -s 1920x1080
Port group: TCP 47000, 47001, 47002; UDP 47000, 47001, 47002
```

参数不可增删：

- `-p 47000` 使用固定的自定义 Legacy AirPlay 端口组；UxPlay 使用 TCP/UDP
  `47000`、`47001`、`47002`，不使用动态端口。
- `-nh` 不追加主机名。
- `-as osxaudiosink` 将手机音频输出到 Mac 的默认音频设备；FrameRelay 不申请麦克风权限。
- `-vs avlayer` 使用 UxPlay fork 的自定义 macOS 渲染器。
- `-fps 60` 请求最高 60 fps。
- 不在正式命令行中加入 `-vsync no`；但自定义 live `avlayer` 分支在 renderer 内固定
  使用 `sync=false` appsink、`vsync_prop=false`，不把发送端 PTS 附到 appsrc。该路径
  使用无时间戳 `CMSampleBuffer` 加 `DisplayImmediately`，不创建或绑定 `CMTimebase`，
  避免锁屏/解锁后的旧时间轴让已经到达的实时帧停在显示层队列中。
- `-reset 8` 八秒没有 AirPlay 心跳时由 UxPlay 重置连接。
- `-nofreeze` 重置后不保留旧帧。
- `-nohold` 允许新客户端接管连接。
- `-s 1920x1080` 请求最高 1920×1080。
- 不加入 `-h265`，不显式指定 `-vd`，保留 UxPlay `decodebin` 自动解码选择。

运行时只使用 bundle 内配置：

```text
UXPLAYRC=<Bundle>/Contents/Resources/FrameRelay.uxplayrc
GST_PLUGIN_PATH_1_0=<Bundle>/Contents/Resources/gstreamer-1.0
GST_PLUGIN_SYSTEM_PATH_1_0=
GST_PLUGIN_SCANNER=<Bundle>/Contents/Resources/gstreamer-1.0/gst-plugin-scanner
GST_REGISTRY_1_0=~/Library/Caches/com.framerelay.FrameRelay/gstreamer-registry.bin
```

`FrameRelay.uxplayrc` 必须为空；FrameRelay 不读取用户目录下已有的
`~/.uxplayrc`。

固定宿主条件：macOS 自带的 AirPlay Receiver 可以保持开启。FrameRelay 的 `-p 47000`
使用独立的 TCP/UDP `47000–47002` 端口组，UxPlay 会把选定的 AirPlay/RAOP 端口通过
Bonjour 广播给 iPhone。实际测试前必须确认这组端口没有被其他程序占用，并确认 macOS
防火墙允许 FrameRelay 的传入连接；关闭系统 AirPlay Receiver 只允许作为端口问题的
临时诊断手段。这个方案仍然是 iPhone 控制中心的“屏幕镜像”，不使用 macOS
`iPhone Mirroring`，也不允许执行 agent 改动固定端口组。

## 3. 固定目录和长期记忆

项目必须保持以下布局。`build/`、`dist/`、`.build/` 是生成目录；源码、脚本、
文档、补丁和许可证纳入 Git。

```text
/Users/danko/workspace/FrameRelay/
├── AGENTS.md
├── Package.swift
├── README.md
├── LICENSE
├── NOTICE
├── docs/
│   ├── PLAN.md
│   ├── DECISIONS.md
│   ├── STATUS.md
│   ├── ARCHITECTURE.md
│   ├── TESTLOG.md
│   ├── UPSTREAM.md
│   └── OPERATIONS.md
├── Sources/
│   ├── FrameRelayApp/
│   └── FrameRelayCoreBridge/
├── Tests/
│   └── FrameRelayTests/
├── Resources/
│   ├── Info.plist
│   ├── FrameRelay.uxplayrc
│   └── LICENSES/
├── Scripts/
│   ├── bootstrap.sh
│   ├── build-core.sh
│   ├── build-app.sh
│   ├── bundle-gstreamer.sh
│   ├── verify-bundle.sh
│   ├── package-dmg.sh
│   └── restart-loop.sh
├── patches/
├── third_party/
│   └── uxplay/
├── build/
└── dist/
```

每次执行 agent 开始任务时，必须按此顺序读取：

```text
AGENTS.md
docs/PLAN.md
docs/DECISIONS.md
docs/STATUS.md
docs/ARCHITECTURE.md
```

每完成一个阶段，必须更新 `docs/STATUS.md` 和 `docs/TESTLOG.md`，写入实际命令、
结果、文件变更、测试证据和下一个精确动作。

## 4. 代码设计固定版

### 4.1 C bridge 目录和边界

```text
Sources/FrameRelayCoreBridge/
├── include/FrameRelayCoreBridge.h
└── FrameRelayCoreBridge.c
```

Swift 只接触项目自有 opaque handle、整数状态、C 字符串、`void *` 宿主地址和
日志回调。Swift 不得接触 GStreamer、GLib、C++、`airplay_core_t`、`dlopen`
句柄或上游函数指针。

`FrameRelayCoreBridge.h` 的 ABI 必须保持如下定义：

```c
#ifndef FRAMERELAY_CORE_BRIDGE_H
#define FRAMERELAY_CORE_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct FRCoreHandle FRCoreHandle;

typedef void (*FRCoreLogCallback)(
    int32_t level,
    const char *message,
    void *user
);

typedef enum FRCoreStatus {
    FRCoreStatusOK = 0,
    FRCoreStatusInvalidArgument = -1,
    FRCoreStatusLoadFailed = -2,
    FRCoreStatusSymbolMissing = -3,
    FRCoreStatusCreateFailed = -4,
    FRCoreStatusConfigureFailed = -5,
    FRCoreStatusAlreadyRunning = -6
} FRCoreStatus;

FRCoreHandle *fr_core_open(
    const char *dylib_path,
    char *error_message,
    size_t error_capacity
);

FRCoreStatus fr_core_set_window(FRCoreHandle *handle, void *nsview);
FRCoreStatus fr_core_set_device_name(FRCoreHandle *handle, const char *utf8_name);
FRCoreStatus fr_core_set_options(FRCoreHandle *handle, const char *argv_tail);

void fr_core_set_log_callback(
    FRCoreHandle *handle,
    FRCoreLogCallback callback,
    void *user
);

FRCoreStatus fr_core_start(FRCoreHandle *handle);
void fr_core_stop(FRCoreHandle *handle);
void fr_core_close(FRCoreHandle *handle);

#ifdef __cplusplus
}
#endif

#endif
```

`FrameRelayCoreBridge.c` 的执行顺序固定：

1. `fr_core_open` 对给定路径执行 `dlopen(path, RTLD_NOW | RTLD_LOCAL)`。
2. 按下列顺序解析 8 个符号：

   ```text
   airplay_core_create
   airplay_core_set_device_name
   airplay_core_set_log_callback
   airplay_core_set_window
   airplay_core_set_options
   airplay_core_start
   airplay_core_stop
   airplay_core_destroy
   ```

3. 任一符号缺失时，释放已打开的 dylib，写错误缓冲区，返回空 handle，不能崩溃。
4. 所有符号存在后立即调用上游 `airplay_core_create`。
5. `dlopen` 句柄保留到 `airplay_core_destroy` 返回之后才能 `dlclose`。
6. bridge 设有进程级单运行实例锁；第二个 handle 调用 start 必须得到
   `FRCoreStatusAlreadyRunning`。
7. `fr_core_stop` 必须等待上游 worker 退出；上游 stop 的 join 不能在主线程执行。
8. `fr_core_close` 顺序固定为：

   ```text
   fr_core_stop
   清除上游 log callback
   清除宿主 NSView 指针
   airplay_core_destroy
   dlclose
   销毁 bridge mutex
   释放 FRCoreHandle
   ```

9. 所有错误写入函数都必须在容量大于零时保证 NUL 终止。
10. bridge 不调用 AppKit，不创建窗口，不暴露音视频库类型。

固定 pinned core 上游补丁用于把嵌入 worker 的异常返回通过已建立的日志回调报告
为 `FrameRelay worker exited unexpectedly`。主动 stop 先设置 stop 标志，因此不会
误报；Swift 状态机只对这条精确标记执行自动重启。

### 4.2 Swift Package 和值类型

`Package.swift` 必须使用 Swift tools 6.2、`.macOS(.v26)`，只包含以下 target：

```text
FrameRelayCoreBridge
FrameRelayApp
FrameRelayTests
```

`FrameRelayApp` 是 AppKit executable，启用主 actor 默认隔离和完整并发检查；测试
使用 Swift Testing，不改用 XCTest，不引入 Combine 作为核心状态管理。

固定值类型：

```swift
struct AirPlayConfiguration: Sendable, Equatable {
    let deviceName: String
    let options: String
}

extension AirPlayConfiguration {
    static let liveVideo = AirPlayConfiguration(
        deviceName: "FrameRelay",
        options: "-p 47000 -nh -a -vs avlayer -fps 60 -reset 8 -nofreeze -nohold -s 1920x1080"
    )
}

struct VideoGeometry: Sendable, Equatable {
    let width: Int
    let height: Int
    let rotationHint: Int
}

enum EngineEvent: Sendable, Equatable {
    case serverStarting
    case serverReady
    case clientConnected
    case videoStarted(VideoGeometry)
    case clientReset
    case clientDisconnected
    case engineError(String)
    case engineStopped
}

enum ReceiverState: Sendable, Equatable {
    case stopped
    case starting
    case waitingForIPhone
    case connecting
    case streaming(VideoGeometry)
    case reconnecting
    case failed(String)
}
```

### 4.3 `AirPlayEngine` actor

唯一可以调用 C bridge 的 Swift 类型是：

```swift
actor AirPlayEngine {
    init(coreURL: URL, configuration: AirPlayConfiguration)
    func start(hostViewAddress: UInt) async throws
    func stop() async
    func restart(hostViewAddress: UInt) async throws
    func eventStream() -> AsyncStream<EngineEvent>
}
```

实现规则：

- 所有 C bridge 调用只能在 actor 内串行执行。
- `fr_core_stop` 可以阻塞，但只阻塞 `AirPlayEngine` actor。
- actor 不持有或访问 AppKit 对象，只接收 `UInt` 地址。
- NSView 地址只在窗口存在期间有效。
- 窗口关闭前必须 `await engine.stop()`，stop 返回后才清理 view。
- C 日志回调来自 AirPlay/GStreamer worker 线程，必须立即复制 C 字符串。
- 回调只向线程安全 `AsyncStream` 送 `EngineLog`，不操作 AppKit 或主 actor。
- stop 返回前保证上游回调不再发生，然后释放 Swift log sink。
- `restart` 的内部 stop 不发出中间 `engineStopped` 事件，避免 AppController 把一次
  明确的 stop/start 误识别为异常退出；普通 `stop()` 仍发送 `engineStopped`。
- 启动前设置 bundle 内 `UXPLAYRC`、GStreamer plugin、scanner 和用户缓存 registry
  路径；不继承用户 `~/.uxplayrc` 的选项。

### 4.4 日志解析和状态机

`EngineLogParser` 是纯值类型、`Sendable`，不能因为不认识的日志改变状态。必须
解析以下固定模式：

```text
begin video stream wxh = 1920x1080; source 1920x884 (rot=0x04)
Initialized server socket(s)
register_dnssd: advertised AirPlay service ...
connection request from ...
Open connections: 1
Begin streaming to GStreamer video pipeline
Open connections: 0
connection reset
lost connection with client
video_reset: ...
Stopping RAOP Server
ERROR / FATAL / GStreamer pipeline 创建失败
FrameRelay worker exited unexpectedly
```

几何日志解析为 `VideoGeometry(width, height, rotationHint)`；损坏或空日志返回
`nil`。`Stopping RAOP Server` 先于其他模式匹配，避免被误识别为客户端事件。
`Begin streaming to GStreamer video pipeline` 只是视频 pipeline 已开始工作的日志，
必须返回 `nil`，不能当作新的 `clientConnected`，否则会重新启动 12 秒视频 watchdog。

固定状态转换规则：

- start 前为 `.stopped`，调用 start 后为 `.starting`。
- server ready 后为 `.waitingForIPhone`。
- client connected 后为 `.connecting`，开始 12 秒视频超时计时。
- video started 后为 `.streaming(geometry)` 并清除重启计数。
- 已经是 `.streaming` 后收到重复连接标记不得回退到 `.connecting`，也不得重新计时
  12 秒视频 watchdog。
- 手机停止镜像、`Open connections: 0` 或普通断开后清理画面，回到
  `.waitingForIPhone`，不重启整个 App。
- 内部 reset 清理旧画面，仍保持核心运行。
- 主动 stop、关闭窗口或退出 App 不自动重启。
- worker 异常退出、或连接后 12 秒没有 videoStarted，进入固定自动重启。
- 自动重启延迟严格为 0.5 秒、1 秒、2 秒；60 秒内三次仍失败为 `.failed`，不无限重启。
- “重新启动”菜单清除失败计数并从第一档开始。

### 4.5 AppKit 宿主

实现 `@MainActor final class AppDelegate: NSObject, NSApplicationDelegate` 的等价
主控制器，并在入口执行：

1. 创建 `NSApplication`。
2. 设置 `.regular`，让 FrameRelay 具有 Dock 图标、标准应用菜单和 Stage Manager
   中的正常 App 身份。
3. 创建标准应用菜单、`NSStatusItem` 和接收窗口；应用菜单必须提供关于、隐藏和
   `⌘Q` 退出，窗口菜单必须提供最小化、缩放和关闭。
4. 创建 `VideoHostView`。
5. 自动启动 engine，菜单栏显示“等待 iPhone”。
6. 持续运行主循环。

窗口固定属性：

```text
content: 1280×720
minimum: 320×240
style: titled + closable + miniaturizable + resizable
background: black, opaque
level: normal
sharingType: .readOnly
```

窗口可移动、可调整大小、可放在普通桌面，不强制全屏，不显示状态文字、FPS、调试
信息或水印。`VideoHostView` 设置 `wantsLayer = true`、黑色 backing layer，自动填满
内容区域，不处理鼠标，不建立第二个视频窗口。收到 `videoStarted(VideoGeometry)`
后，`VideoWindowSizer` 必须按协商宽高比在当前显示器可见区域内计算新 content size，
在横竖屏切换时自动调整，并设置 `contentAspectRatio` 让用户手动缩放仍保持比例。
上游 `avlayer` 将 `AVSampleBufferDisplayLayer` 安装到该宿主 view。

avlayer 的 live 镜像路径不得把 GStreamer buffer 的 PTS/duration 用于显示调度。显示层
使用无效的 `CMSampleTimingInfo` 和 `kCMSampleAttachmentKey_DisplayImmediately`，不创建
或绑定 `CMTimebase`；appsink 使用有限容量和 `readyForMoreMediaData` 检查，不能无限积压
旧帧。每秒最多写一条 pulled/enqueued/dropped/output_fps 统计，不允许逐帧 debug 日志。
通用 timestamped sink 可以保留自己的 PTS 路径，但不影响自定义 live AVLayer。

AirPlay 的视频 pause/resume 回调必须清理显示层：pause 和 resume 都清除当前图像/队列
并 arm 一枚 seed；第一枚恢复后的解码帧使用 immediate sample 尽快显示。第一枚恢复帧
允许一次性绕过 `readyForMoreMediaData` 的陈旧拒绝，普通播放仍必须使用有限队列和
ready gate。这样 iPhone 锁屏解锁后不会把旧时间轴当成实时显示时钟，也不会停在第一枚
恢复帧。

窗口关闭顺序固定：

```text
window close
    -> desiredRunning = false
    -> 异步 await engine.stop()
    -> stop 返回
    -> 清理 VideoHostView layer
    -> orderOut/关闭窗口
    -> 菜单栏状态更新为未启动
```

禁止在 `windowWillClose` 或其他主线程回调里同步调用 `fr_core_stop`。

菜单固定包含：

```text
FrameRelay
├── 显示接收窗口
├── 隐藏接收窗口
├── 启动接收
├── 停止接收
├── 重新启动
├── 复制诊断信息
├── 打开日志目录
├── ─────────
└── 退出 FrameRelay
```

状态文字固定为：未启动、正在启动、等待 iPhone、正在连接、正在接收
`宽×高`、正在重连、启动失败。

“复制诊断信息”必须包含 FrameRelay 版本、macOS 版本、Mac 芯片、arm64、core
SHA、GStreamer 版本、当前状态、最近 50 条错误、App bundle 路径、日志路径和
当前网络接口概况。

## 5. Bundle、构建和脚本固定版

### 5.1 Info.plist

必须包含：

```xml
<key>CFBundleIdentifier</key>
<string>com.framerelay.FrameRelay</string>
<key>CFBundleName</key>
<string>FrameRelay</string>
<key>CFBundleDisplayName</key>
<string>FrameRelay</string>
<key>CFBundleExecutable</key>
<string>FrameRelay</string>
<key>CFBundlePackageType</key>
<string>APPL</string>
<key>LSMinimumSystemVersion</key>
<string>26.0</string>
<key>NSLocalNetworkUsageDescription</key>
<string>FrameRelay 需要在本地网络接收 iPhone 的 AirPlay 屏幕镜像。</string>
<key>NSBonjourServices</key>
<array>
    <string>_airplay._tcp</string>
    <string>_raop._tcp</string>
</array>
```

不申请麦克风、屏幕录制、摄像头、Apple Events 或 App Sandbox 权限。

### 5.2 构建顺序

在项目根目录依次执行：

```bash
./Scripts/bootstrap.sh
./Scripts/build-core.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./Scripts/build-app.sh
./Scripts/bundle-gstreamer.sh
./Scripts/verify-bundle.sh
./Scripts/package-dmg.sh
```

`bootstrap.sh` 固定安装：

```bash
brew install \
  cmake ninja pkg-config gstreamer gst-plugins-base gst-plugins-good \
  gst-plugins-bad gst-libav libplist openssl@3
```

然后初始化子模块、切到 `popyachsa-integration` 固定 SHA。`build-core.sh` 使用
以下不可变 CMake 参数：

```bash
cmake \
  -S third_party/uxplay \
  -B build/uxplay \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_CORE_DLL=ON \
  -DNO_MARCH_NATIVE=ON \
  -DGST_MACOS=1 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0

cmake --build build/uxplay --target uxplay-core
cmake --build build/uxplay --target uxplay
```

standalone 协议烟雾测试只使用：

```bash
build/uxplay/uxplay -n FrameRelay -nh -a -vs osxvideosink \
  -fps 60 -reset 8 -nofreeze -nohold
```

这条命令只验证协议和 standalone 生命周期，不是最终产品路径。

### 5.3 Bundle 布局和依赖重写

最终 App 必须至少包含：

```text
FrameRelay.app/Contents/
├── Info.plist
├── MacOS/FrameRelay
├── Frameworks/
│   ├── uxplay-core.dylib
│   └── 所有递归非系统 dylib
└── Resources/
    ├── FrameRelay.uxplayrc
    ├── gstreamer-1.0/
    │   ├── gst-plugin-scanner
    │   └── 运行所需视频插件
    └── LICENSES/
```

打包脚本必须从 Homebrew 复制 GStreamer、递归解析 `otool -L` 非系统依赖，并用
`install_name_tool` 完成以下 rpath：

```text
主程序: @executable_path/../Frameworks
Framework dylib/core: @loader_path
GStreamer plugin/scanner: @loader_path/../../Frameworks
```

所有 bundle dylib ID 使用 `@rpath/<basename>`；插件对 framework 使用
`@rpath/<basename>`，插件间依赖使用 `@loader_path/<basename>`。发布包不得包含：

```text
/opt/homebrew
/usr/local
/Users/danko/workspace/FrameRelay/build
```

所有二进制必须是 arm64。依赖重写和资源复制完成后，才执行：

```bash
codesign --force --deep --sign - dist/FrameRelay.app
codesign --verify --deep --strict --verbose=2 dist/FrameRelay.app
```

DMG 固定命令：

```bash
hdiutil create \
  -volname FrameRelay \
  -srcfolder dist/FrameRelay.app \
  -ov \
  -format UDZO \
  dist/FrameRelay-0.1.0-arm64.dmg
```

### 5.4 静态 Bundle 验收

`Scripts/verify-bundle.sh` 必须检查：

- Info.plist 可解析且 bundle 标识、可执行文件、最低系统版本、Bonjour 声明正确。
- `Contents/MacOS/FrameRelay`、`uxplay-core.dylib`、GStreamer plugin 目录和 scanner 存在。
- 每一个 Mach-O 只包含 arm64。
- ad-hoc codesign `--deep --strict` 通过。
- `otool -L` 不指向 Homebrew、`/usr/local` 或项目 build 目录。
- bundle 启动不依赖当前工作目录、不依赖 shell 中的 GStreamer 环境变量。

## 6. 阶段顺序和硬验收

### Phase 0：根目录、文档、依赖和协议门禁

开始条件：项目根目录可写，且当前工作目录不是 `chat`。

执行动作：

1. 建立 `/Users/danko/workspace/FrameRelay` 并初始化 Git。
2. 先创建 `AGENTS.md` 和 `docs/` 全部长期记忆文件。
3. 创建固定目录、`Package.swift` 占位和 `.gitignore`。
4. 初始化 `third_party/uxplay` 子模块并固定 SHA。
5. 安装固定 Homebrew 依赖。
6. 构建 core 和 standalone。
7. 运行上述 standalone smoke command。
8. 用 `dns-sd -B _airplay._tcp` 和 `dns-sd -B _raop._tcp`确认本机广播；确认日志中的
   端口组为 TCP/UDP `47000–47002`，并在 macOS 自带 AirPlay Receiver 保持开启时无端口冲突。
9. 在真实 iPhone 控制中心选择 FrameRelay，建立镜像并运行真实游戏至少 10 分钟。
10. 横竖屏切换、停止镜像、再次打开镜像。

通过条件：发现、连接、收视频、10 分钟稳定、旋转稳定、停止不崩溃、再次连接。

失败条件：若真实 iOS 26.5 设备任一连接步骤失败，`STATUS.md` 必须写
`BLOCKED_PROTOCOL_IOS_26_5`，并记录设备、系统、commit、完整日志、Bonjour 结果、
连接阶段和最后成功事件；停止继续 UI/音频/替代路线工作。

### Phase 1：C bridge 和 Swift 空宿主

开始条件：Phase 0 的真实设备协议门禁已通过。若实际设备尚未到场，只能完成不宣称
通过的本地构建准备；不得把 Phase 1/2/3 的软件结果写成真实协议通过。若已有协议
失败证据，则必须停留在 `BLOCKED_PROTOCOL_IOS_26_5`。

执行动作：

1. 落实固定 C header 和纯 C `dlopen` bridge。
2. 解析 8 个符号和错误缓冲区。
3. 加入进程级单实例锁、stop/destroy 顺序和 callback 清理。
4. 在 pinned core 上应用并记录唯一 worker-exit patch。
5. 实现 `AirPlayEngine` actor、日志 `AsyncStream` 和 parser。
6. 用 NULL 宿主地址执行 create/start/stop/destroy 测试。
7. 验证 start 第二次确定返回 AlreadyRunning；stop 重复调用无崩溃。

验收：release build、Swift Testing、缺少 dylib/symbol 不崩溃、错误缓冲区 NUL、
create/start/stop/destroy 20 次无 hang、主线程不调用 stop。

### Phase 2：AppKit 独立窗口和抖音捕获

开始条件：Phase 1 全部通过。

执行动作：

1. 创建 regular AppKit app、标准应用菜单、status item 和固定接收窗口。
2. 创建黑色 `VideoHostView` 并传 opaque 地址给 actor。
3. 接收 `EngineEvent`，实现固定状态文字和诊断信息。
4. 自动启动 core，等待 iPhone。
5. iPhone 控制中心选择 FrameRelay。
6. 抖音直播伴侣添加“窗口捕获”，只选择 FrameRelay 窗口。

验收：窗口独立可移动可缩放，Mac 可继续操作抖音，iPhone 继续触控，横竖屏画面
正常，抖音看不到其他窗口，断开清除旧帧，再次镜像恢复。

### Phase 3：稳定性和断连

固定执行 20 次启动/停止、20 次打开/关闭镜像、窗口关闭、菜单停止、退出 App、
iPhone 锁屏解锁、控制中心停止、Mac 断网、路由器短暂重启、横竖屏交替、30 分钟、
60 分钟、第二设备尝试连接、空 GStreamer 路径、缺插件、复制 App 到另一个目录。

验收：无崩溃、主线程不被 stop 卡住、无冻结旧画面、无第二窗口、无 orphan worker、
无 orphan uxplay 进程、20 次无死锁、60 分钟不退出、最多固定三次重连后清晰失败。

### Phase 3A：帧率根因分段诊断

开始条件：真实设备已经能够发现、连接并显示视频；1080p `-vsync no` 对照已经完成，
但滑动卡顿仍存在。该阶段只测量，不实施队列策略、格式转换、PixelBuffer 缓存或
同步策略优化。

固定执行动作：

1. 保持正常启动配置不变；诊断只通过现有 `-FPSdata` profile 开启。
2. 在 pinned UxPlay checkout 上应用 `patches/0003-uxplay-frame-relay-diagnostics.patch`，
   由 `Scripts/build-core.sh` 从 0001/0002 之后幂等重放。
3. 在 AirPlay 输入线程记录视频访问单元数量、输入 FPS、码率、到
   `video_process` 的回调平均/最大耗时和最大到达间隔。
4. 在 GStreamer appsrc 记录 `gst_app_src_push_buffer` 的计数、平均/最大耗时、最大
   间隙和 Flow 错误；读取输入 queue、appsink 水位和 appsink dropped 属性。
5. 在第一次有效输出后记录 decodebin 实际视频 decoder factory 和 appsink 协商 caps。
6. 在 Objective-C AVLayer hot path 记录 ready 拒绝、PixelBuffer 创建/锁定、NV12
   copy、format description、CMSampleBuffer 创建和 enqueue 的数量及耗时。
7. 在 AirPlay pause/resume marker 记录 monotonic 时间，并统计 pause 到第一个成功
   enqueue 帧的恢复时间。
8. 所有指标每秒输出汇总，禁止逐帧日志；Swift 不建立逐帧 Task，不把指标送到
   AppKit 主线程。
9. 执行 `Scripts/build-core.sh`、`Scripts/build-app.sh`、`Scripts/bundle-gstreamer.sh`
   和 `Scripts/verify-bundle.sh`；记录确切命令和结果。
10. 让用户用 `--diagnostic-1080p` 连接同一台 iPhone，等待、快速滑动、静置、锁屏
    5 秒后解锁，再停止；从 `~/Library/Logs/FrameRelay/FrameRelay.log` 提取完整
    `FrameRelay diagnostic ...` 行。

本阶段通过条件：诊断包可构建、普通启动参数完全匹配锁定值、普通模式不出现诊断行、
诊断模式出现 transport/decoder/caps/pipeline/avlayer 五类汇总及 marker（若测试包含
锁屏）、App 不崩溃、日志足够支持下一阶段定位。没有真实日志前，不得宣称已经找到
瓶颈，也不得开始性能优化；不得使用 `-fps 120`。

### Phase 3B：锁屏/解锁 PTS 恢复修复

开始条件：Phase 3A 的真实 iPhone 诊断日志已经显示 pause/resume 后输入恢复，但
`AVSampleBufferDisplayLayer` 长时间拒收新帧，且没有 decoder、PixelBuffer 或 NV12
拷贝错误。执行 agent 不得重新选择协议、引擎、端口、分辨率、编码器或音频路线。

固定执行动作：

1. 在 pinned UxPlay checkout 上应用 `patches/0004-uxplay-resume-pts-rebase.patch`，
   且由 `Scripts/build-core.sh` 在 0001、0002、0003 之后幂等重放；patch reverse-check
   必须通过。
2. 在 `renderers/video_renderer.c` 保持两个文件静态变量：
   `gst_video_pts_rebase_pending` 和 `gst_video_pts_rebase_origin`。
3. `video_renderer_resume` 只在 timestamp-sync 路径把 pending 置为 true；恢复后第一枚
   有效 `raw_pts` 设置 origin 并清除 pending。
4. 当 origin 有效时，送入 GStreamer 的 PTS 固定为 `raw_pts - origin`；如果 sender
   clock 向后跳，立即以当前 raw PTS 作为新 origin 并使用零 PTS，禁止无符号下溢。
5. `video_renderer_start` 清除 pending 和 origin；正常启动 options、`-fps 60`、默认
   timestamp sync、`-a`、固定端口和窗口实现不得变化。
6. 诊断模式只增加三种低频 PTS 标记：pending、首次 rebase、向后跳 reset；不得增加
   逐帧 Swift Task 或 AppKit 调用。
7. Swift 在每次 `videoStarted` 处理后，将 `geometry`、`rotation`、`applied` 和当前
   window content size 写入现有 `FrameRelay.log`；普通启动不写 host diagnostic 行。
8. 固定执行 `Scripts/build-core.sh`、`swift build -c release`、`Scripts/build-app.sh`、
   `Scripts/bundle-gstreamer.sh`、`Scripts/verify-bundle.sh`、`Scripts/package-dmg.sh`；
   记录命令结果、patch 状态、SHA-256 和已知 `swift test` 环境问题。
9. 交付新的 `.app` 后，用户用同一 iPhone 按固定流程连接、滑动、锁屏 5 秒、点亮但不
   解锁、解锁回游戏，至少保持解锁后 15 秒，再退出并提供北京时间开始/结束时间。
10. 从同一日志核对：`resume-rebase-pending` 后出现 `resume-rebase origin_ns`；恢复后
    `avlayer performance` 的 `enqueue`/`output_fps` 重新增长；`ready_rejects` 不再无限
    持续；Swift host 的第二次横屏几何事件 `applied=true`。

本阶段通过条件：本地 core/App/bundle/codesign/DMG 构建和静态验证通过；普通模式配置
和窗口行为未被改动；真实设备解锁后不再停留在锁屏前旧游戏画面，横屏窗口恢复正确，
且恢复后 AVLayer 能持续入队。若真实设备仍然失败，只记录新的日志证据，不得自行改用
`-fps 120`、macOS iPhone Mirroring、ReplayKit、OBS、QuickTime 或其他 AirPlay 引擎。

### Phase 3C：恢复首帧显示时钟锚定修复

开始条件：Phase 3B 的真实设备日志已经显示，PTS 重基准标记成功出现，但快速锁屏、
点亮、解锁后首个恢复帧仍然晚到，且 `readyForMoreMediaData` 从恢复后持续为 `NO`；
同一日志中的 transport、decoder、PixelBuffer、NV12 copy 和 sample creation 均正常。
本阶段只修复 AVSampleBufferDisplayLayer 恢复时序，不重新选择 AirPlay 协议、端口、
编码器、分辨率、`-fps 60`、音频或窗口架构。

固定执行动作：

1. 在当前 pinned UxPlay checkout 上应用
   `patches/0005-uxplay-resume-display-clock-anchor.patch`；
   `Scripts/build-core.sh` 必须在 0001、0002、0003、0004 之后幂等重放该 patch，且
   patch reverse-check 必须通过。
2. 在 `renderers/avsample_sink.m` 保留两个 `_Atomic bool`：
   `resume_timebase_anchor_pending` 和 `resume_seed_pending`；在 sink resume 时先
   arm 两个 flag，即使宿主 layer 尚未异步发布也不能丢失本次恢复状态。
3. `avlayer_sink_resume` 必须先清除旧图像、停止 CMTimebase 并将其设为零；禁止在
   resume marker 到首个恢复帧之间以 rate 1.0 运行显示时钟。
4. `avlayer_sink_enqueue_nv12` 在读取 ready 状态前，使用原子的一次性
   `resume_timebase_anchor_pending` 完成 timebase anchor：将相对 `pts_ns` 设置为
   当前第一枚恢复帧的 display time，再以 rate 1.0 启动。正常启动和非恢复帧不执行
   该 anchor。
5. 同一第一枚恢复帧使用 `resume_seed_pending` 一次性跳过 not-ready gate；只要
   PixelBuffer、format description、CMSampleBuffer 创建成功就消耗 permit 并入队。
   如果 sample 创建失败，必须把 permit 恢复给下一帧；不能因此永久回到旧的拒收状态。
6. 保留普通播放的 ready gate、旧帧丢弃和有限队列策略；不得把所有帧无条件 enqueue，
   不得把一次性 seed 扩展为持续 bypass，不得新增逐帧日志或 Swift Task。
7. 固定执行 `./Scripts/build-core.sh`、`swift build -c release`、`swift test -c release`、
   `./Scripts/build-app.sh`、`./Scripts/bundle-gstreamer.sh`、`./Scripts/verify-bundle.sh`
   和 `./Scripts/package-dmg.sh`；记录编译警告、patch 状态、静态验收结果和三个 SHA-256。
8. 用新包以 `--diagnostic-1080p` 执行一次真实设备回归：连接并滑动至少 15 秒；按锁屏
   键，点亮但不解锁，等待 2 秒，再解锁回横屏游戏；恢复后继续观察至少 15 秒；再
   重复一次快速锁屏/点亮/解锁；最后从菜单退出并提供北京时间开始/结束时间。
9. 从时间窗口提取 `FrameRelay diagnostic marker`、`FrameRelay diagnostic pts`、
   `FrameRelay diagnostic host`、`avlayer performance` 和 `FrameRelay diagnostic avlayer`；
   必须确认恢复首帧后 `enqueue`/`output_fps` 继续增长，`ready_rejects` 不再连续覆盖
   全部输入帧，且第二次横屏 geometry 的 `applied=true`。

本阶段通过条件：Phase 3C patch 可从 pinned SHA 幂等构建；普通启动 options 完全不变；
真实设备快速锁屏/点亮/解锁后不显示锁屏前旧游戏画面，恢复帧持续入队，窗口方向和大小
正确；没有新增崩溃、死锁、orphan worker 或第二个窗口。若仍失败，必须保留新的完整
诊断区间和日志，不得自行修改为 `-fps 120` 或切换到其他路线；只有真实设备日志通过
后才能进入 Phase 4。

### Phase 3D：竖屏锁屏流到横屏游戏流的显示格式切换恢复

开始条件：Phase 3C 的真实设备日志已经显示 transport、decoder、PixelBuffer、copy、sample
creation 和 AVLayer 入队均恢复到约 60 FPS，且第二次横屏 `videoStarted` 已被 Swift host
应用，但实际窗口仍显示先前的竖屏锁屏/解锁画面。该条件已经由北京时间约 03:52 的
真实截图和日志满足：后续横屏阶段 `output_fps≈59.8`、`ready_rejects=0`、host
`applied=true`，画面却仍为竖屏锁屏帧。本阶段只处理 AVSampleBufferDisplayLayer 的
“旧格式图像仍可见”问题，不重新选择 AirPlay 协议、端口、编码器、分辨率、`-fps 60`、
音频或窗口架构。

固定执行动作：

1. 在当前 pinned UxPlay checkout 上应用
   `patches/0006-uxplay-format-transition-recovery.patch`；`Scripts/build-core.sh` 必须
   在 0001、0002、0003、0004、0005 之后幂等重放该 patch，并通过 reverse-check。
2. 在 `renderers/avsample_sink.h` 的诊断结构中增加 `format_flushes`，并增加
   `avlayer_sink_flush_image(void *)`；该函数只清除 `AVSampleBufferDisplayLayer` 的当前
   图像和已排队样本，不重置正在运行的 CMTimebase。
3. 在 `renderers/video_renderer.c` 的 `apply_rotation_hint()` 中，固定按以下顺序执行：
   先将新的 `video-direction` 写入 live `videoflip`，再在方法、协商宽度或协商高度任一
   变化时调用 `avlayer_sink_flush_image()`；相同几何重复日志不能重复清空。
4. 格式切换清空完成后才 arm 一个 `resume_seed_pending`，只允许下一枚成功构造的
   CMSampleBuffer 唤醒显示层；如果样本构造失败，permit 必须恢复。该 permit 与
   pause/resume 的已有一次性 permit 共用，不得改成所有帧绕过 ready gate。
5. 不在格式切换时重置 PTS 或 CMTimebase；pause/resume 的 rebase 和首帧 clock anchor
   保持原行为。这样竖屏到横屏只改变像素格式/方向，不会引入第二个时间跳变。
6. 在 `avlayer_on_new_sample()` 记录 appsink 实际输出的 `GST_VIDEO_FRAME_WIDTH/HEIGHT`，
   只在尺寸变化时写一行 `FrameRelay diagnostic sample: output=WxH`；每秒 AVLayer 诊断
   还必须包含 `format_flushes`。这些日志用于区分“videoflip 没换格式”和“格式已换但
   AVLayer 仍显示旧图像”。
7. 不改变正式启动 options：仍为
   `-p 47000 -nh -a -vs avlayer -fps 60 -reset 8 -nofreeze -nohold -s 1920x1080`；
   不加入 `-fps 120`、`-vsync no` 或强制 decoder。
8. 固定执行：

   ```bash
   ./Scripts/build-core.sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --arch arm64
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test -c release
   ./Scripts/build-app.sh
   ./Scripts/bundle-gstreamer.sh
   ./Scripts/verify-bundle.sh
   ./Scripts/package-dmg.sh
   ```

   之后执行无 Homebrew 环境变量的启动/退出 smoke test，并记录签名包中主程序、core
   和 DMG 的 SHA-256。
9. 交付新包后，用 `--diagnostic-1080p` 做真实回归：连接后先保持横屏游戏 10–15 秒；
   锁屏并点亮但不解锁约 2 秒；解锁回到横屏游戏；继续观察至少 15 秒；再重复一次
   快速锁屏、点亮、解锁。最后退出 App，并记录北京时间起止时间。
10. 从同一时间段检查以下固定证据：
    `FrameRelay avlayer format transition`；实际输出尺寸从竖屏值（通常为
    `886x1920` 或等价协商值）变为横屏值（通常为 `1920x886`/`1920x884`）；
    `format_flushes` 增长；横屏 host geometry 为 `applied=true`；格式切换之后
    `output_fps` 和 `enqueue` 持续增长。若实际输出尺寸未改变，记录为 videoflip
    动态协商失败；若尺寸已改变而画面仍旧，记录为 AVLayer 显示层失败；两种情况都
    必须停在本阶段继续取证。

本阶段本地通过条件：0006 可从 pinned SHA 幂等应用，core/App/bundle/codesign/DMG
构建通过，普通 options 完全匹配，静态 bundle 不依赖 Homebrew。真实设备通过条件：
解锁后的横屏游戏帧实际进入显示层并替换竖屏锁屏帧，窗口继续横向且不显示旧帧，重复
测试无崩溃、死锁、orphan worker 或第二个窗口。真实设备未通过前不能进入 Phase 4，
不得自行切换到 `-fps 120`、macOS iPhone Mirroring、ReplayKit、OBS、QuickTime 或其他
AirPlay 引擎。

### Phase 3E：实时 AVLayer 呈现时钟移除与立即显示

开始条件：Phase 3D 的真实设备日志已经证明，锁屏/解锁后的 transport、decoder、appsink
和 CMSampleBuffer 入队持续约 57–65 FPS，`ready_rejects=0`，并且竖屏到横屏的实际
appsink 尺寸和窗口 geometry 都已经切换，但用户看到的画面仍然停在亮屏或解锁后的
第一帧。该证据说明问题在 AVSampleBufferDisplayLayer 的时间戳呈现调度，而不是帧没有
到达、videoflip 没有协商或普通 ready gate 拒收。本阶段只修复 live AVLayer 的呈现方式。

固定执行动作：

1. 在 pinned UxPlay checkout 上依次保留 0001–0006，并应用
   `patches/0007-uxplay-live-immediate-display.patch`。`Scripts/build-core.sh` 必须
   先识别已经完成的 0007 最终源状态，再跳过旧 patch 的重复套用；从干净 pinned SHA
   依次应用 0001–0007 时必须得到与工作树相同的源代码。
2. 在 `renderers/avsample_sink.m` 删除 live sink 的 `CMTimebase` 成员、创建、绑定和
   resume anchor。保留 `pts_ns`/`duration_ns` 的 C ABI 参数以避免破坏上游调用契约，
   但明确忽略它们；使用三个无效时间字段创建 `CMSampleBuffer`，并对每个接受的样本
   设置 `kCMSampleAttachmentKey_DisplayImmediately = true`。
3. 在 `renderers/video_renderer.c` 的自定义 live `avlayer` 分支固定设置
   `vsync_prop=false`。appsink 继续为 `sync=false`、`max-buffers=3`、`drop=true`；
   该分支不向 appsrc buffer 写入发送端 PTS。通用 timestamped sink 的既有 PTS 行为
   不改变，正式命令行仍保持原锁定字符串，不添加 `-fps 120` 或 `-vsync no`。
4. 保留并验证已有的有限队列、`readyForMoreMediaData` gate、pause/format flush、
   `resume_seed_pending` 和每秒诊断计数。`output_fps` 必须继续明确标注为 enqueue
   计数，不得把它当成显示器 vsync FPS；不增加逐帧日志或 Swift 每帧任务。
5. 固定执行本地验证：

   ```bash
   ./Scripts/build-core.sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --arch arm64
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test -c release
   ./Scripts/build-app.sh
   ./Scripts/bundle-gstreamer.sh
   ./Scripts/verify-bundle.sh
   ./Scripts/package-dmg.sh
   env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$HOME" \
     STARTUP_WAIT_SECONDS=2 ./Scripts/restart-loop.sh 20
   ```

   另做一次从 pinned SHA 的 0001–0007 sequential apply/diff check，并记录最终 App、core
   和 DMG 的 SHA-256。所有 `otool -L`、arm64、签名和无 Homebrew 检查仍必须通过。
6. 交付新包后，用 `--diagnostic-1080p` 做真实设备回归：连接后先保持横屏游戏 10 秒；
   锁屏并点亮但不解锁，连续在锁屏界面操作 2–3 秒；解锁回到横屏游戏并观察 15 秒；
   再重复一次快速锁屏→点亮→解锁。记录北京时间开始/结束时间，并检查锁屏操作和
   解锁后游戏是否都在持续变化。
7. 如果仍然静止，必须保留同一时间段的 `diagnostic transport`、`decoder`、`caps`、
   `pipeline`、`avlayer`、`marker`、`host` 和 `avlayer performance` 日志，明确说明
   是实际 enqueue 持续但图像仍不更新，还是输入已经停止；不得继续猜测 `-fps 120`，
   不得切换到 macOS iPhone Mirroring、ReplayKit、OBS、QuickTime 或其他 AirPlay 引擎。

本阶段本地通过条件：0007 可幂等重放，core/App/bundle/codesign/DMG 和 20 次 clean
environment 启动/退出通过，普通 options 和窗口架构未改变。真实设备通过条件：亮屏未
解锁时收到的锁屏操作可以持续更新；解锁后的横屏游戏可以持续更新并替换锁屏画面；
横竖屏窗口仍正确调整；重复测试无冻结、崩溃、死锁、orphan worker 或第二个窗口。
在该真实设备条件通过前不能进入 Phase 4。

真实设备回归结论（2026-09-13，北京时间约 05:21–05:23）：通过。最新日志记录了 9
组 pause/resume，锁屏操作和解锁后的横屏游戏均继续产生并入队视频帧，横竖屏格式和窗口
几何切换正常，未再出现解锁后停在第一帧的冻结。当前保留一个已知限制：AirPlay 从锁屏
唤醒时通常需要约 0.7–1.6 秒恢复到稳定视频流；恢复后输入和入队回到约 55–66 FPS。
该延迟属于手机/AirPlay 唤醒恢复过程，不视为 Phase 3E 的显示冻结失败；Phase 4 仍需
完成抖音窗口捕获、长时间运行和独立发布包验收。

### Phase 3F：AirPlay 唤醒空档归因与 AVLayer 快速恢复

开始条件：Phase 3E 已通过真实设备视觉恢复，但诊断仍显示约 0.7–1.6 秒的唤醒阶段
延迟。先区分手机睡眠期间的无包窗口和接收端 resume 后的本地尾延迟；不能把 pause 到
resume 的时长直接称为渲染恢复耗时。

固定执行动作：

1. 在 pinned UxPlay checkout 上保留 0001–0007，并应用
   `patches/0008-uxplay-fast-avlayer-resume.patch`。`Scripts/build-core.sh` 必须能在
   已应用的 0001–0008 工作树上重复运行，也必须能从 pinned SHA 顺序应用全部八个补丁。
2. 用 `resume_started_ns` 记录 resume marker 时间；`recovery` 只统计 resume marker 到
   第一枚成功入队的 AVLayer sample。保留 `arrival_gap_max_ms` 作为发送端无包证据。
3. live AVLayer resume 设置 GStreamer 为 PLAYING 后不再同步等待最多 100 ms；其他 sink
   的状态等待、pause/format flush、seed permit、固定 AirPlay options 和协议均不变。
4. 执行固定本地验证：

   ```bash
   Scripts/build-core.sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
   Scripts/build-app.sh
   Scripts/bundle-gstreamer.sh
   Scripts/verify-bundle.sh
   Scripts/package-dmg.sh
   ```

5. 用 `--diagnostic-1080p` 重做真实设备锁屏→点亮→解锁回游戏回归，分别记录
   pause→resume、resume→first accepted sample 和 `arrival_gap_max_ms`。如果 resume→first
   sample 已低于本地尾延迟而 pause→resume 仍为 0.7–1.6 秒，则保留为 iPhone/AirPlay
   sender 行为，不切换协议、不尝试 `-fps 120`。

本阶段本地通过条件：0008 可幂等重放，core/App/bundle/codesign/DMG 静态验证通过，
Swift 测试通过。真实设备通过条件：resume→first accepted sample 的测量口径正确、无
新增冻结/崩溃/死锁/orphan worker；sender 无包窗口可以记录为已知限制。Phase 4 仍需
完成抖音窗口捕获、长时间运行和独立发布包验收。

### Phase 3G：实时 AVLayer 持续拒帧自恢复和重启可观测性

开始条件：真实设备日志显示视频输入、GStreamer push/callback 持续，但
`ready_rejects` 连续覆盖全部输入，`enqueued=0`，且没有 decoder、PixelBuffer、sample
或 audio flow 错误。本轮日志已经满足该条件：UTC 17:39:38–17:48:33 的诊断窗口持续
出现 `ready_rejects≈pulled`、`enqueued=0`。

固定执行动作：

1. 在 pinned UxPlay checkout 上保留 0001–0009，应用
   `patches/0010-uxplay-avlayer-ready-watchdog.patch`；`Scripts/build-core.sh` 必须
   在已应用的 0001–0010 工作树上幂等运行，也必须能从 pinned SHA 顺序应用全部十个
   补丁。
2. live AVLayer 只用 monotonic 时间测量连续拒帧；连续三秒后执行一次
   `flushAndRemoveImage` 并 arm 单枚 seed，最多尝试两次。普通帧仍受
   `readyForMoreMediaData` gate 和有限队列限制，不增加逐帧日志或 Swift Task。
3. 两次 flush/seed 仍无法让任何正常帧恢复时，核心写入精确的
   `FrameRelay avlayer watchdog: action=restart reason=ready-stuck` 标记。Swift 解析为
   display-stalled 事件，经既有 0.5/1/2 秒退避自动重启；不在 AppKit 主线程直接调用
   `fr_core_stop`。
4. 手动和自动重启写入 reason 与 lifecycle generation；若重启进行中再次收到请求，
   记录 ignored，而不是交错执行第二个 stop/start。
5. 固定执行 core、Swift Testing、App、GStreamer bundle、静态验证和 DMG 构建；真实
   设备回归必须覆盖连续游戏、锁屏/唤醒、断开/重连和完整 Douyin Window Capture。

本阶段本地通过条件：0010 reverse-check 和顺序重放通过，Swift parser 测试通过，core/
App/bundle/codesign/DMG 构建通过，普通 AirPlay options 不变。真实设备通过条件：在
相同图形负载下人为或自然触发显示层拒帧后，窗口在 watchdog flush/seed 后恢复；若两次
尝试仍失败，日志必须显示带 generation 的单次受控自动重启，且不出现交错连接。未完成
真实设备回归前不得把本阶段标记为通过，也不得标记 v0.1 完成。

### Phase 4：独立发布包

开始条件：Phase 2/3 和真实抖音窗口捕获已通过。

执行固定脚本：

```bash
Scripts/build-app.sh
Scripts/bundle-gstreamer.sh
Scripts/verify-bundle.sh
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$HOME" \
  Scripts/restart-loop.sh 2
Scripts/package-dmg.sh
```

再把 App 复制到临时的独立目录，清空 Homebrew 相关环境变量启动，确认 Bonjour、
视频和窗口捕获不依赖项目当前目录。更新 README、OPERATIONS、UPSTREAM、STATUS 和
TESTLOG，填写依赖版本、`otool -L`、App/core/DMG SHA-256。

最终交付物必须是：

```text
/Users/danko/workspace/FrameRelay/dist/FrameRelay.app
/Users/danko/workspace/FrameRelay/dist/FrameRelay-0.1.0-arm64.dmg
```

## 7. 测试设计固定版

Swift Testing 必须覆盖：固定 options（包括 `-p 47000`）、正常/空/损坏日志、1920×1080、
带旋转提示、portrait rotation、server/client/disconnect/reset/stop 事件、固定重连退避、
三次失败、主动停止不重启，以及 `Begin streaming to GStreamer video pipeline` 不产生
连接事件。

C bridge 测试必须覆盖：缺失 dylib、缺失 symbol、错误缓冲区 NUL、第二次 start、重复
stop、`stop -> clear callback -> clear window -> destroy` 顺序。

诊断验收必须检查日志中存在并且字段可解释：
`FrameRelay diagnostic transport`、`decoder`、`caps`、`pipeline`、`avlayer`；如果
执行锁屏/解锁，还必须检查 `FrameRelay diagnostic marker` 和 recovery 数值。诊断行按
秒汇总，不能出现以每帧为粒度的日志洪水；普通启动日志不能因为诊断补丁新增这些行。

人工验收必须使用：

```text
MacBook Pro M1 Pro 2021 / macOS 26.5
iPhone 15 Pro Max / iOS 26.5
抖音直播伴侣 Mac 版
真实局域网
真实手机游戏
```

不能用模拟器、录屏文件或静态视频替代真实设备验收。

直播固定操作：打开 FrameRelay、iPhone 控制中心选择 FrameRelay、抖音添加窗口
捕获、选择 Mac 麦克风、输出 1080p。若手机实际发送 30 fps，记录实际值，不把
`-fps 60` 当成强制输出 60 fps。

## 8. 音频开发和立即备援

当前由项目负责人决定先进行音频开发。FrameRelay 使用 UxPlay 已有的 AirPlay 音频
接收、AAC/ALAC 解码和 GStreamer 输出链路，通过 `-as osxaudiosink` 输出到 Mac
默认音频设备；FrameRelay 不申请麦克风权限，抖音仍直接使用 Mac 麦克风。

音频真实验收必须在 iPhone 15 Pro Max / iOS 26.5 上完成，至少记录：音频 codec、
GStreamer audio pipeline、是否有 audio bus error、视频连接是否保持稳定，以及手机
播放/暂停和锁屏唤醒后的音频恢复情况。

AAC 镜像音频修复已记录为 `patches/0009-uxplay-audio-live-clock.patch`：AAC 使用
arrival-paced `sync=false`，避免 AirPlay/NTP 时间戳早于重连后的 GStreamer appsrc
base time 时被直接丢弃；重复的音频格式开始会重启对应 pipeline。每五秒输出一次
received/valid/pushed/flow_errors 计数。下一次真实回归必须同时确认 Mac 可听见音频、
这些计数持续增长且 `flow_errors=0`，并覆盖手机播放/暂停与锁屏唤醒。

FrameRelay 完成前的立即直播备援固定为：

```text
iPhone USB-C
  -> USB-C 转 HDMI/DisplayPort 适配器
  -> HDMI
  -> 支持 UVC、1080p60、USB 3.0 的采集卡
  -> Mac
  -> 抖音直播伴侣“采集卡”来源
```

iPhone 不连接 AirPods 或 Bluetooth 音频设备，不处于静音；采集卡提供视频和 HDMI
媒体音频，Mac 麦克风提供主播声音。不使用 QuickTime 中转。这是开发期间的固定
备援，不改变 FrameRelay 软件架构。

## 9. 完成定义

只有以下条件全部满足，才能在 `STATUS.md` 标为 v0.1 完成：

```text
iPhone iOS 26.5 能发现 FrameRelay
iPhone iOS 26.5 能建立屏幕镜像
游戏画面进入独立可调窗口
Mac 仍可正常使用
抖音能捕获 FrameRelay 窗口
横竖屏切换正常
断连后不显示冻结画面
重新连接正常
App 不依赖 Homebrew
App 可从 DMG 独立运行
连续 60 分钟无崩溃
所有长期记忆文档已更新
```
