# FrameRelay 架构和生命周期

## 1. 模块边界

```text
FrameRelayMain
  -> AppDelegate（@MainActor，应用状态和窗口关闭顺序）
      -> StatusMenuController（@MainActor，菜单栏）
      -> ReceiverWindowController（@MainActor，NSWindow）
          -> VideoHostView（@MainActor，NSView 宿主）
      -> AirPlayEngine（actor，唯一 C bridge 调用者）
          -> FrameRelayCoreBridge（纯 C，dlopen/dlsym/生命周期）
              -> uxplay-core.dylib（UxPlay fork，内部 worker/GStreamer）
```

FrameRelay 不重新截取自己的窗口，不使用 ScreenCaptureKit。视频已经由 UxPlay 的
`avlayer` 直接送入宿主 `NSView`，抖音直播伴侣只需捕获这个独立窗口。

## 2. 数据流

```text
iPhone 控制中心“屏幕镜像”
    │ AirPlay Legacy Protocol / Bonjour
    ▼
uxplay-core.dylib
    │ 解密、接收 H.264/AAC-ELD、GStreamer decodebin/音频解码
    ▼
UxPlay avlayer / NV12 appsink
    │ sync=false、有限队列、ready 检查
    ▼
AVSampleBufferDisplayLayer + DisplayImmediately（无 controlTimebase）
    ▼
VideoHostView.layer
    ▼
FrameRelay regular AppKit NSWindow
    ▼
抖音直播伴侣 Window Capture
    ▼
直播视频画面
```

v0.1 的 core 参数是：

```text
-p 47000 -nh -as osxaudiosink -vs avlayer -fps 60 -reset 8 -nofreeze -nohold -s 1920x1080
```

`-p 47000` 让 UxPlay 使用固定的 TCP/UDP `47000`、`47001`、`47002` 端口组；
UxPlay 会把选定的 RAOP/AirPlay 服务端口写入 Bonjour 广播，iPhone 按广播的端点
连接。FrameRelay 因此可以和 macOS 自带 AirPlay Receiver 同时运行。若绑定失败，
原因应从这组端口是否被占用以及 macOS 防火墙是否允许传入连接两方面排查。

`-as osxaudiosink` 在 UxPlay 内把手机音频输出到 Mac 默认音频设备。FrameRelay
不申请麦克风权限、不接管主播麦克风；主播麦克风由抖音直播伴侣直接读取。

AAC 镜像音频在 `audio_renderer` 内按到达顺序推入 GStreamer，不把 AirPlay/NTP 时间戳
与重连后新建的 appsrc base time 做跨时钟比较；否则时间戳可能早于新 base time，导致
接收到了音频包却在渲染前直接丢帧。每次音频格式开始都会重启对应 pipeline，并以五秒
低频日志记录 received/valid/pushed/flow_errors，便于区分手机未发包、解码前丢帧和
appsrc/sink 推送失败。ALAC 的原有时间戳同步策略不变。

`-fps 60` 是 AirPlay 协商的最高请求，不强制 iPhone 输出 60 fps。正式命令行仍不
添加 `-vsync no`，但自定义 live `avlayer` 分支在视频 renderer 内固定使用
`sync=false` 的 appsink，并将 `vsync_prop` 置为 false；因此这条实时镜像路径不会把
发送端 NTP PTS 写回 GStreamer appsrc。它不是文件或 VOD 播放器，不能让一条已经
被锁屏/解锁打乱的旧时间轴决定当前画面。

`AVLayerSink` 为每个 NV12 帧创建 `CMSampleBuffer`，使用三个无效的
`CMSampleTimingInfo` 字段，并始终设置 `kCMSampleAttachmentKey_DisplayImmediately`。
它不创建、不绑定 `CMTimebase`，也不把 `controlTimebase` 与 immediate attachment
组合使用。这样显示层按帧到达顺序尽快显示；`readyForMoreMediaData == false` 时仍
丢弃当前旧帧以限制延迟，恢复/格式切换的第一枚帧仍有一次性 seed 权限。渲染回调每秒
写一条 pulled/enqueued/dropped/output_fps 统计，不写逐帧日志；其中 `output_fps` 是
送入 AVLayer 的计数，不代表物理显示器的 vsync。

如果 live AVLayer 在视频输入和 GStreamer 回调仍持续时连续三秒拒绝所有普通帧，
`AVLayerSink` 会在渲染 worker 内执行一次 `flushAndRemoveImage`，随后只允许一枚
seed sample 绕过旧的 readiness gate；最多尝试两次，仍然持续拒收才写入
`FrameRelay avlayer watchdog: action=restart reason=ready-stuck`。Swift 日志解析器把
该标记转换为受控自动重启事件，沿用既有 0.5/1/2 秒退避和三次上限，不在主线程直接
停止 C core。诊断汇总额外记录 `ready_watchdog_flushes` 和
`ready_watchdog_escalations`，普通路径不逐帧写日志。

Phase 3B/3C 的 PTS 重基准和显示时钟 anchor 曾用于诊断锁屏恢复，但真实设备日志证明
“持续入队而画面冻结”仍会发生。0007 因此只改变自定义 live AVLayer 的呈现调度：
时间戳重基准代码仍保留给通用 timestamped sink，live AVLayer 不执行它；队列上限、
ready gate、pause/format flush 和 seed 恢复机制仍保留。

诊断模式是显式的命令行例外，不属于正式 v0.1 运行配置：

```text
--diagnostic-1080p -> 固定 1920×1080 路径 + -FPSdata
--diagnostic-720p  -> 固定 1280×720 路径 + -FPSdata
--diagnostic-1080p-nosync -> 固定 1920×1080 路径 + -vsync no + -FPSdata
```

普通双击启动不带这些参数，因此仍然严格使用上面的正式 options。`-FPSdata` 由固定
提交中的 UxPlay core 记录 iPhone 每秒发来的性能 plist；Swift 不把这些报告当作状态
事件，也不打开逐帧 debug flood。三个诊断 profile 只用于同一网络条件下的 A/B 测试，
不会改变正式分辨率、音频策略、端口或 AirPlay 引擎。

诊断 profile 还会把同一个 `-FPSdata` 开关传入 UxPlay 的视频 renderer。只有该开关
为真时，核心才启用以下低频指标；普通双击启动不会执行这些计时和汇总日志：

```text
FrameRelay diagnostic transport:
  AirPlay 视频包/访问单元数量、输入 FPS、输入码率、video_process 回调平均/最大耗时、
  相邻输入单元的最大到达间隔

FrameRelay diagnostic decoder:
  decodebin 实际选中的视频 decoder element、factory 和 GStreamer klass

FrameRelay diagnostic caps:
  appsink 收到的实际协商 raw caps（格式、宽高、framerate 等）

FrameRelay diagnostic pipeline:
  appsrc push 数量/FPS/平均与最大耗时、最大 push 间隙、Flow 错误、appsink 回调耗时、
  输入 queue 水位、appsink 水位和 dropped 属性

FrameRelay diagnostic avlayer:
  ready 拒绝、PixelBuffer 创建/锁定、NV12 拷贝、format description、sample 创建、
  enqueue 的数量与平均/最大耗时，以及 pause/resume 后首个成功帧恢复耗时

FrameRelay diagnostic marker:
  AirPlay 0x56/0x5e pause 和 0x16/0x1e resume marker 的 monotonic 时间
```

这些指标每秒汇总一次，不在每帧路径上调用 Swift、不触碰 AppKit，也不写逐帧日志。
`avlayer performance.output_fps` 仍然只是送入自定义显示层的计数，不代表真实显示器
vsync；分析时必须和上述分段指标以及 iPhone 的 `encoderCurrentFPS` 一起看。诊断日志
只写入现有 `FrameRelay.log`，不会改变默认端口、分辨率、音频、窗口或同步模式。
诊断模式还会记录 `FrameRelay diagnostic pts` 的重基准标记，以及 Swift 宿主在收到
`videoStarted` 后是否实际应用了几何和当前窗口内容尺寸：

```text
FrameRelay diagnostic host: videoStarted geometry=1920x884 rotation=0x07 applied=true windowContent=...
```

## 3. C ABI 和动态加载

Swift 导入的只有 `FrameRelayCoreBridge.h`。`FRCoreHandle` 是 opaque 指针，
上游 `airplay_core_t`、GStreamer/GLib 类型和原始函数指针都留在
`FrameRelayCoreBridge.c` 内。

bridge 打开 core 的顺序：

```text
检查路径
  -> dlopen(path, RTLD_NOW | RTLD_LOCAL)
  -> dlsym 8 个 airplay_core_* 符号
  -> 创建上游 airplay_core_t
  -> 返回 FRCoreHandle
```

必须解析的符号：

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

任何 `dlopen`、`dlsym` 或 create 失败都只写调用方提供的错误缓冲区并返回空
handle；错误函数在容量大于零时始终 NUL 终止。动态库句柄直到 destroy 完成
之后才 `dlclose`。

UxPlay 内部使用文件静态状态，因此 bridge 有一个进程级运行所有权：同一进程
只能有一个运行中的 core。第二个 handle 的 start 返回
`FRCoreStatusAlreadyRunning`。

## 4. C 生命周期和 stop 语义

`fr_core_start` 在 bridge handle mutex 和进程级 mutex 保护下执行上游 start，
成功后登记唯一运行 owner。

`fr_core_stop` 的语义是同步等待上游 stop 返回。上游 `airplay_core_stop` 会请求
GMainLoop 退出并 join 内部 worker；因此该调用只能在 `AirPlayEngine` actor 内执行，
不能在 AppKit 主线程执行。

`fr_core_close` 的严格顺序：

```text
1. fr_core_stop（等待 worker join）
2. 上游 set_log_callback(NULL, NULL)
3. 上游 set_window(NULL)
4. 上游 airplay_core_destroy
5. dlclose
6. 销毁 bridge mutex
7. 释放 FRCoreHandle
```

固定补丁 `patches/0001-uxplay-report-embedded-worker-exit.patch` 为嵌入式
上游 worker 的异常返回发出一条精确日志：

```text
FrameRelay worker exited unexpectedly
```

主动 stop 会先设置原子 stop 标记，因此不会发出此事件；Swift 只对这条标记执行
固定的 0.5/1/2 秒重启策略。

## 5. Swift actor 和回调线程

`AirPlayEngine` 是唯一调用 bridge 的 actor。它保存 core URL、固定配置、C opaque
handle、log sink 和两个 `AsyncStream`：

```text
AirPlay/GStreamer worker
    -> C FRCoreLogCallback
    -> 立即复制 const char * 到 Swift String
    -> EngineLogSink（线程安全 continuation）
    -> AirPlayEngine 日志任务
    -> LogWriter actor + EngineLogParser
    -> EngineEvent AsyncStream
    -> AppDelegate 主 actor
```

C callback 线程上严禁：

- 触碰 AppKit、NSWindow、NSView 或菜单栏；
- 直接访问 `@MainActor` 对象；
- 等待主线程；
- 保存上游传入的 `const char *` 而不复制。

`fr_core_stop` 返回前，worker 和 callback 都已结束。之后才释放
`Unmanaged<EngineLogSink>` 用户对象、清空 Swift core handle，并允许宿主 view 清理
layer。

`AirPlayEngine.restart` 把 stop/start 作为一次逻辑操作，内部 stop 不发送中间
`engineStopped`，避免 AppDelegate 重新排队第二次自动重启。独立的用户 stop
仍发 `engineStopped`。

## 6. 日志、状态和重连

`EngineLogParser` 是纯值类型；不能识别的日志只写日志文件，不改变接收状态。固定
解析映射：

| 上游日志 | EngineEvent |
|---|---|
| `Initialized server socket(s)` | `serverReady` |
| `advertised AirPlay service` | `serverReady` |
| `connection request from` | `clientConnected` |
| `Open connections: 1` | `clientConnected` |
| `Begin streaming to GStreamer video pipeline` | 无事件；只记录日志 |
| `begin video stream wxh = W×H ... rot=0xR` | `videoStarted(VideoGeometry)` |
| `Open connections: 0` | `clientDisconnected` |
| `connection reset` / `lost connection` / `video_reset` | `clientReset` |
| `Stopping RAOP Server` | `engineStopped` |
| `ERROR`、`FATAL`、GStreamer pipeline error | `engineError` |
| `FrameRelay worker exited unexpectedly` | `engineError`，触发自动重启 |

状态规则：

```text
stopped
  -> starting
  -> waitingForIPhone
  -> connecting
  -> streaming(width × height)
```

手机主动停止镜像时，UxPlay 的最后一个客户端断开回调会先停止 live video renderer，
设置 `relaunch_video`/`reset_loop`，让现有主循环销毁并重建一个新的 renderer；RAOP
HTTP/Bonjour 服务保持运行，不在 HTTP worker 的 `conn_destroy` 回调里停止或 join 自己。
Swift 随后清空旧显示层并回到 `waitingForIPhone`，下一次连接使用重新绑定到同一个
`VideoHostView` 的新 AVLayer。只有 worker 异常退出或连接后 12 秒没有 `videoStarted` 才进入自动重启。60 秒窗口内
最多三次，延迟固定为 0.5 秒、1 秒、2 秒；三次后 `failed`，不无限重启。用户
点击“重新启动”会清空失败计数。

连接日志可能重复出现；一旦状态已经是 `streaming`，后续连接标记不会回退状态，
也不会重新启动“12 秒内必须收到视频”的 watchdog。GStreamer pipeline 的
`Begin streaming to GStreamer video pipeline` 日志同样不会被误判为新的连接。

## 7. AppKit 窗口生命周期

入口创建 `NSApplication`，设为 `.regular`，安装标准应用菜单，创建 Dock 可见的
普通接收窗口、status item 和宿主 view，自动启动 engine。这样 FrameRelay 是一个
真正的 macOS App，用户可以用窗口左上角关闭按钮、`⌘W` 关闭接收窗口，或用
`⌘Q`/应用菜单退出；窗口属于当前 App 的 Stage Manager 场景。

窗口属性固定为：

```text
默认内容尺寸：1280×720
最小内容尺寸：320×240
styleMask：titled / closable / miniaturizable / resizable
背景：黑色、不透明
层级：normal
sharingType：readOnly
```

窗口不全屏、不占用整个桌面、不绘制文字 overlay/FPS/水印、不处理鼠标点击；用户
可以通过原生标题栏移动或缩放它，并同时操作抖音直播伴侣。收到新的
`videoStarted(VideoGeometry)` 时，`VideoWindowSizer` 在当前显示器可见区域内按
视频宽高比重新计算 content size；横竖屏切换会自动调整窗口，窗口保留在当前显示器，
并把 `contentAspectRatio` 设为协商后的比例，避免手动缩放造成画面拉伸。
`VideoHostView` 只负责黑色 backing layer 和清理上游加入的 sublayer。

`AVSampleBufferDisplayLayer` 的生命周期仍由上游 sink 管理：窗口关闭、核心停止或
连接 reset 时，必须先让 engine worker 停止/flush，再清理 view。AirPlay 的锁屏
pause marker（`0x56`）调用 sink pause，清空当前图像并 arm 一枚恢复 seed；解锁 resume
marker（`0x16`）再次清空队列并 arm seed，不重置、不启动任何显示时间轴。第一枚恢复
帧使用无时间戳的 immediate sample 送入显示层；如果样本构造失败，permit 会保留给
下一帧，之后恢复普通 ready gate。这样锁屏间隔不会让旧 PTS 把恢复帧排到过去或未来。
诊断日志中的 `resume-rebase-*` 只适用于仍使用 timestamped sink 的通用路径；当前
live AVLayer 的关键证据是 `enqueue`、`output_fps`、`format_flushes`、实际画面是否
持续变化，以及 `recovery`（resume marker 到第一枚 accepted sample 的时间）。诊断
transport 的 `arrival_gap_max_ms` 单独表示 iPhone/AirPlay 是否在唤醒阶段停止发包，不能
把 pause marker 到 resume marker 的手机睡眠时长算作本地渲染恢复耗时。

Phase 3F 的 live AVLayer resume 不再同步等待最多 100 ms 的 GStreamer
`PAUSED -> PLAYING` 状态转换；设置状态后立即返回给 RTP 线程，让后续 appsrc buffer
完成异步切换。该优化只作用于无时间戳的 live AVLayer 分支，通用 timestamped sink
仍保留原状态等待。

视频格式/方向变化是另一条固定恢复路径。收到新的 `videoStarted` 几何之前，UxPlay
会在视频 renderer 中更新 `videoflip` 的 `video-direction`；如果旋转方法、协商宽度或
协商高度与上次已应用值不同，随后立即调用 `avlayer_sink_flush_image`。该调用只执行
`AVSampleBufferDisplayLayer.flushAndRemoveImage`，并 arm 一个 `resume_seed_pending`。
由于当前 live AVLayer 没有 CMTimebase 或显示 PTS，flush 不需要维护或重置媒体时钟。
下一枚成功构造的 immediate `CMSampleBuffer` 作为新格式的唤醒帧；样本构造失败会归还
permit。之后仍回到普通 `readyForMoreMediaData` 检查和有限丢帧策略。重复的同一几何
事件不会重复 flush。

诊断模式在 appsink 映射成功后读取 `GST_VIDEO_FRAME_WIDTH/HEIGHT`，只在尺寸变化时
写 `FrameRelay diagnostic sample: output=WxH`；每秒 `FrameRelay diagnostic avlayer`
额外写 `format_flushes`。因此要分别判断：输入几何/`videoflip` 是否真的换成横屏，
以及 AVLayer 是否已经接受并显示新格式，不能只看窗口尺寸或 `output_fps`。

用户关闭窗口时不能同步 stop：

```text
NSWindow delegate
  -> desiredRunning = false
  -> 取消超时/重连 Task
  -> Task 内 await engine.stop()
  -> stop 返回
  -> clearVideoLayers()
  -> 隐藏窗口
  -> 状态“未启动”
```

这保证主线程不会等待 GStreamer worker，也保证上游
`AVSampleBufferDisplayLayer` 不会在 core 仍使用它时被释放。

## 8. Bundle 和 GStreamer 运行时

构建时可以使用 Homebrew；发布 App 不读取目标机器的 Homebrew。主程序和 core
放在 `Contents/Frameworks`，GStreamer plugin 和 scanner 放在
`Contents/Resources/gstreamer-1.0`。

运行时环境由 `AirPlayEngine` 按 core 所在 bundle 计算：

```text
UXPLAYRC = Contents/Resources/FrameRelay.uxplayrc
GST_PLUGIN_PATH_1_0 = Contents/Resources/gstreamer-1.0
GST_PLUGIN_SYSTEM_PATH_1_0 = 空字符串
GST_PLUGIN_SCANNER = Contents/Resources/gstreamer-1.0/gst-plugin-scanner
GST_REGISTRY_1_0 = ~/Library/Caches/com.framerelay.FrameRelay/gstreamer-registry.bin
```

bundle 脚本从 GStreamer 的固定视频插件集合开始，递归解析每个 Mach-O 的
`otool -L`，复制所有非系统 dylib，重写为 `@rpath`/`@loader_path`，然后才对
嵌套 Mach-O 和 App 做 ad-hoc 签名。发布验证拒绝 `/opt/homebrew`、`/usr/local`
和项目 build 目录的运行时依赖，拒绝非 arm64 二进制。

## 9. 权限和音频

`Info.plist` 只声明本地网络用途和 `_airplay._tcp`/`_raop._tcp` Bonjour 服务。
FrameRelay v0.1 不申请麦克风、屏幕录制、摄像头、Apple Events 或 Sandbox 权限。
手机音频不进入 FrameRelay；抖音麦克风设备选择独立于此接收窗口。
