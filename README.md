# FrameRelay

FrameRelay 是一个个人自用的 arm64 macOS AirPlay 接收器。它接收 iPhone 控制中心
“屏幕镜像”发来的画面，把画面放入一个普通、可移动、可调整大小的 AppKit 窗口，
再交给抖音直播伴侣的“窗口捕获”。iPhone 仍由手指操作，Mac 不接管手机。

```text
iPhone 控制中心“屏幕镜像”
    -> Bonjour / AirPlay Legacy
    -> FrameRelay（UxPlay core + GStreamer）
    -> AVSampleBufferDisplayLayer
    -> 独立 AppKit 窗口
    -> 抖音直播伴侣“窗口捕获”
```

FrameRelay 不使用 macOS `iPhone Mirroring`、ReplayKit、QuickTime、OBS、
ScreenCaptureKit、虚拟摄像头或外部 UxPlay 进程。Mac 不需要全屏，用户可以同时操作
抖音直播伴侣和其他应用。

## 当前状态

当前 v0.1 已完成 C bridge、AppKit 窗口、视频恢复、音频实时路径、GStreamer bundle、
ad-hoc 签名和 DMG 打包的本地实现。完整发布验收仍未完成：真实 iPhone 15 Pro Max /
iOS 26.5 的断连重连、音频连续性和抖音 Window Capture 还必须现场验证，不能用本地
编译结果代替真实设备结果。详见 [`docs/STATUS.md`](docs/STATUS.md) 和
[`docs/TESTLOG.md`](docs/TESTLOG.md)。

## 固定实现

```text
Host:        Swift 6.2 + AppKit，macOS 26.0+，arm64-only
AirPlay:     UxPlay popyachsa-integration
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Bridge:      纯 C dlopen/dlsym；AirPlay core 在进程内运行
Video:       avlayer -> AVSampleBufferDisplayLayer；最高请求 1920x1080 / 60 fps
Audio:       -as osxaudiosink -> Mac 默认音频输出
Window:      普通标题栏窗口；默认内容 1280x720，最小 320x240
App ID:      com.framerelay.FrameRelay
AirPlay 名称: FrameRelay
端口:        TCP/UDP 47000、47001、47002
Runtime:     GStreamer 和非系统 dylib 随 App 打包
```

正式运行参数固定为：

```text
-p 47000 -nh -as osxaudiosink -vs avlayer -fps 60 -reset 8 -nofreeze -nohold -s 1920x1080
```

`-fps 60` 是 AirPlay 的最高请求，不保证 iPhone 实际发送 60 fps；运行时应以 iPhone
协商结果和日志为准。手机媒体音频输出到 Mac 默认音频设备，FrameRelay 不申请麦克风
权限；主播麦克风由抖音直播伴侣直接读取。

## 构建

项目根目录固定为：

```text
/Users/danko/workspace/FrameRelay
```

需要 Apple Silicon Mac、macOS 26.5、Xcode/Apple Swift 6.2，以及 Homebrew。依赖、
UxPlay 子模块和固定 commit 由 `Scripts/bootstrap.sh` 准备。按以下顺序执行：

```bash
./Scripts/bootstrap.sh
./Scripts/build-core.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./Scripts/build-app.sh
./Scripts/bundle-gstreamer.sh
./Scripts/verify-bundle.sh
./Scripts/package-dmg.sh
```

构建期间可以使用 Homebrew；发布 App 的 GStreamer 和递归非系统 dylib 会复制到
bundle 内，目标 Mac 不需要安装 Homebrew。生成物为：

```text
dist/FrameRelay.app
dist/FrameRelay-0.1.0-arm64.dmg
```

`Scripts/verify-bundle.sh` 会检查 Info.plist、arm64 架构、ad-hoc 签名、GStreamer
资源以及依赖中是否残留 Homebrew、`/usr/local` 或项目 `build/` 的绝对路径。

## 运行和直播

1. 双击 `dist/FrameRelay.app`；从 DMG 第一次打开 ad-hoc App 时使用“右键 → 打开”。
2. 首次提示本地网络权限时选择允许。FrameRelay 会作为普通 App 出现在 Dock、应用
   切换器和台前调度中，并打开一个带标题栏的接收窗口。
3. 确认 iPhone 与 Mac 在同一个未启用客户端隔离的局域网内，在 iPhone 控制中心点击
   “屏幕镜像”，选择 `FrameRelay`。
4. 等待窗口显示手机画面，在抖音直播伴侣添加“窗口捕获”，只选择 FrameRelay 窗口，
   不要选择整个桌面。
5. 在抖音直播伴侣中单独选择 Mac 麦克风。FrameRelay 的手机媒体音频会走 Mac 默认
   音频输出，不作为抖音的麦克风输入。

窗口支持移动、缩放、关闭和 `⌘W`；收到视频几何信息后，横竖屏会按协商宽高比调整，
手动缩放仍保持比例。手机锁屏、解锁、停止镜像和再次选择 FrameRelay 的具体操作、
日志位置和故障排查见 [`docs/OPERATIONS.md`](docs/OPERATIONS.md)。

FrameRelay 使用独立的固定端口组 `47000–47002`，因此 macOS 自带的 AirPlay Receiver
通常可以保持开启。若日志出现 `Error initialising socket 48` 或 `Address already in use`，
先检查这组 TCP/UDP 端口和 macOS 防火墙，不要改动项目锁定的端口或设备名称；关闭系统
AirPlay Receiver 只用于临时诊断。FrameRelay 仍然接收 iPhone 控制中心的“屏幕镜像”。

## 诊断模式

诊断 profile 只用于取证，不属于正式启动配置。先退出已运行的 FrameRelay，再从项目
根目录执行：

```bash
./dist/FrameRelay.app/Contents/MacOS/FrameRelay --diagnostic-1080p
./dist/FrameRelay.app/Contents/MacOS/FrameRelay --diagnostic-720p
./dist/FrameRelay.app/Contents/MacOS/FrameRelay --diagnostic-1080p-nosync
```

三个 profile 分别是 1080p、720p 和 1080p 加 `-vsync no` 对照，都会打开 UxPlay 的
`-FPSdata`。普通双击启动不带这些参数，不会改变正式的端口、音频、窗口、解码器或
分辨率策略。诊断日志写入：

```text
~/Library/Logs/FrameRelay/FrameRelay.log
```

重点关注 `encoderCurrentFPS`、`FrameRelay diagnostic transport/decoder/caps/pipeline/avlayer`、
`FrameRelay diagnostic marker`、`FrameRelay avlayer performance` 和
`FrameRelay diagnostic host`。`output_fps` 是送入 AVLayer 的计数，不等于显示器
vsync；不要把它单独当作真实显示帧率，也不要把 `-fps 60` 当成强制值。完整诊断流程
见 [`docs/OPERATIONS.md`](docs/OPERATIONS.md) 的“帧率根因诊断”章节。

## 开发约定

开始开发前按顺序阅读：

```text
AGENTS.md
docs/PLAN.md
docs/DECISIONS.md
docs/STATUS.md
docs/ARCHITECTURE.md
```

实现边界和长期决策都记录在 `docs/` 中。不要修改 `/Users/danko/workspace/chat` 或
`TokChan`，不要移动 `third_party/uxplay` 的 pinned commit，也不要编辑未在
`docs/UPSTREAM.md` 列出的上游补丁。每个实现阶段都要更新 `docs/STATUS.md` 和
`docs/TESTLOG.md`；真实设备验收只能填写现场观察结果。

## 开播备援

如果软件接收器还没有完成真实 iOS 26.5 验收，可使用独立硬件链路立即开播：

```text
iPhone USB-C
    -> USB-C 转 HDMI/DisplayPort 适配器
    -> 支持 UVC、1080p60、USB 3.0 的采集卡
    -> Mac
    -> 抖音直播伴侣“采集卡”来源
```

这条链路不使用 QuickTime 中转，也不改变 FrameRelay 的软件架构。

## 许可证

AirPlay engine 是 GPL-3.0-or-later 的 UxPlay-derived code。根目录 `LICENSE`、
`NOTICE` 和 `Resources/LICENSES/` 保留 UxPlay、GStreamer、OpenSSL、libplist 及
递归依赖的许可证和通知。项目面向个人自用，不提供账号系统、云服务、更新器、
Developer ID 或 notarization。
