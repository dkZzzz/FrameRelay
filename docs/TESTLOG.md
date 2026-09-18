# FrameRelay 测试日志

## 记录规则

真实设备条目必须填写以下字段，不能用“能编译”代替连接结果：

```text
Date:
Mac:
macOS:
iPhone:
iOS:
Network:
FrameRelay build:
Core commit:
Test:
Result:
Observed latency:
Observed resolution:
Observed FPS:
Disconnect behavior:
Rotation behavior:
Douyin capture result:
Log path:
```

## 2026-09-14 — Phase 4 音频约 2 小时直播回归：长时间静音

```text
Date: 2026-09-14（Asia/Shanghai）
Mac: MacBook Pro 2021, Apple M1 Pro, arm64
macOS: 26.5（build 25F71）
iPhone: iPhone 15 Pro Max（iPhone16,2）
iOS: 26.5
Network: Wi-Fi；IPv6 link-local；沿用既有局域网
FrameRelay build: dist/FrameRelay.app 0.1.0；patches/0001–0008；`--diagnostic-1080p`
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: 用户进行约 2 小时实际直播；分析 `~/Library/Logs/FrameRelay/FrameRelay.log.2`、`.1`、`FrameRelay.log` 的轮转日志，并按 UxPlay 启动实例拆分时间线。
Result: 视频基本稳定；用户反馈前一小时以上没有手机音频，末段约十几至二十分钟恢复有声。日志中真正的长时间实例是 UTC `18:08:44Z` 启动、`18:08:51Z` 连接、`19:56:13Z` 断开，约 1 小时 47 分。当前诊断没有音频包/解码帧/sink 输出计数，因此不能仅凭日志确定长时间静音发生在网络、AAC 解码还是 `osxaudiosink`。
Audio evidence: 旧实例 UTC `17:14:55Z` 明确记录 `audio_disabled`；另一启用音频的实例在 `17:32:39Z` 协商 `AAC-ELD 44100/2`，`17:33:20Z` 出现 189 条 `invalid ntp_time < gst_audio_pipeline_base_time`，代码路径会直接 return 丢弃音频帧。长时间实例在 `18:09:08Z` 协商 `AAC-ELD 44100/2`、`18:09:09Z` 启动 audio RTP，之后没有 `GStreamer error (audio)`、invalid audio frame 或 invalid NTP 日志。
Video evidence: 长时间实例约 6125 个 transport/pipeline 诊断窗口平均输入约 58.7 FPS；`push_flow_errors=0`，视频持续入队。视频链路未显示出足以解释一小时静音的整体网络中断。
Observed audio: 用户现场确认前段长时间无声，末段恢复有声；FrameRelay 日志未记录 Mac 音频设备实际出声状态，不能将“开始音频协商”误报为“持续可听”。
Observed video: 持续显示，用户反馈画面基本无问题。
Disconnect behavior: 通过。`video_reset: type = RTP_Shutdown`、`Open connections: 0` 在 `19:56:13Z` 出现。
Rotation behavior: 长时间实例的视频诊断持续运行；本次重点为音频，未重新判定视觉旋转。
Douyin capture result: 用户在实际直播中完成；音频连续性失败。
Log path: `~/Library/Logs/FrameRelay/FrameRelay.log`、`.1`、`.2`
Files changed: docs/STATUS.md; docs/TESTLOG.md
Next exact action: 增加 AAC 分层音频计数和 GStreamer sink 状态日志，修复 AAC 镜像流重连后的时间基准丢帧，再做至少 30 分钟持续音乐回归。
```

## 2026-09-15 — Phase 4 AAC 镜像音频实时播放修复构建

```text
Date: 2026-09-15（Asia/Shanghai）
Mac: MacBook Pro 2021, Apple M1 Pro, arm64
macOS: 26.5（build 25F71）
iPhone: iPhone 15 Pro Max（真实设备回归待执行）
iOS: 26.5（真实设备回归待执行）
Network: 真实设备回归待执行
FrameRelay build: dist/FrameRelay.app 0.1.0；patches/0001–0009
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: AAC 音频实时路径修复；固定顺序执行 `Scripts/build-core.sh`、`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`、`Scripts/build-app.sh`、`Scripts/bundle-gstreamer.sh`、`Scripts/verify-bundle.sh`、`Scripts/package-dmg.sh`，并执行 `git diff --check`、0009 reverse-check、产物 SHA-256。
Result: 本地验证通过。core 编译通过；Swift Testing 13/13；App 签名、GStreamer bundle、依赖和 DMG 静态校验通过。DMG 为 `dist/FrameRelay-0.1.0-arm64.dmg`。
Artifacts: App SHA-256 `01d73d6d7885ff546e6a533e71286c9045a1484c2d8694e374c16f564c92ba12`; core SHA-256 `9d141a3e61264472baec62c6d30b8342f5ae74cb2fbdf4cd33a0d40021d8878f`; DMG SHA-256 `d1a301237af422b96bb84bb2380d439722c875c5db14c3418897840f38de8298`。
Fix evidence: `audio_renderer.c` 对 AAC-ELD/AAC-LC 使用 `sync=false` 按到达顺序推送；重复音频格式开始会重启 pipeline；每五秒记录 `received/valid/invalid/pushed/flow_errors`。ALAC 时间戳同步未改变。
Real-device result: pending；不能把本地编译和静态验证当作音频可听见或长时间连续性的通过。
Observed audio: 尚未执行修复包现场回归。
Observed video: 上一轮真实设备视频基本稳定；本轮未重新宣称设备通过。
Disconnect behavior: 本轮未执行真实设备断连验收。
Rotation behavior: 本轮未执行真实设备旋转验收。
Douyin capture result: 本轮未执行修复包直播验收。
Log path: `~/Library/Logs/FrameRelay/FrameRelay.log`
Files changed: patches/0009-uxplay-audio-live-clock.patch; Scripts/build-core.sh; docs/UPSTREAM.md; docs/PLAN.md; docs/DECISIONS.md; docs/ARCHITECTURE.md; docs/STATUS.md; docs/TESTLOG.md; third_party/uxplay/renderers/audio_renderer.c
Next exact action: 启动新构建 App，播放持续音乐至少 30 分钟，检查 Mac 可听见音频、`FrameRelay audio stats` 持续增长且 `flow_errors=0`，再覆盖手机暂停/播放和锁屏唤醒。
```

## 2026-09-12 — 修复前本地自动化/静态验证基线

```text
Date: 2026-09-12
Mac: MacBook Pro 2021, Apple M1 Pro, arm64（主机工具链）
macOS: 26.5（build 25F71）
iPhone: 未执行真实设备测试
iOS: 未执行真实设备测试
Network: 仅完成本机 Bonjour/启动检查准备；未验证 iPhone 与 Mac 的同一局域网连接
FrameRelay build: Swift 6.2.3 release/debug build; bundle version 0.1.0
Core commit: 587111368390479b7f65feb881c9257c02e508b5，应用项目唯一 worker-exit patch
Test: Swift Testing、C bridge 错误路径/生命周期、UxPlay standalone 本地启动停止、arm64 导出检查、GStreamer bundle 静态检查、ad-hoc codesign、clean-environment startup loop
Result: 通过。Swift Testing 11/11；C bridge 缺失 dylib、缺失 symbol、错误缓冲区 NUL、start twice、重复 stop、stop/clear/destroy 顺序连续 20 次均通过；standalone 能启动并在本地停止；发布 App 和 DMG 静态验证通过；App 复制到临时独立目录后在干净环境启动，通过了 bundle 路径和依赖检查；未把这些结果当成真实 AirPlay 连接通过
Observed latency: 未测量
Observed resolution: 未测量
Observed FPS: 未测量
Disconnect behavior: 仅通过 parser/状态和本地生命周期测试；未在 iPhone 上观察
Rotation behavior: 仅通过日志几何和 rotationHint 单元测试；未在 iPhone 上观察
Douyin capture result: 未执行
Log path: ~/Library/Logs/FrameRelay/FrameRelay.log（实际运行时路径）
```

## 2026-09-12 — 端口修复后本地验证（历史记录）

```text
Date: 2026-09-12
Mac: MacBook Pro 2021, Apple M1 Pro, arm64（主机工具链）
macOS: 26.5（build 25F71）
iPhone: 未执行真实设备测试
iOS: 未执行真实设备测试
Network: 本机端口绑定和本机 Bonjour 启动检查；未验证 iPhone 与 Mac 的同一局域网连接
FrameRelay build: dist/FrameRelay.app 0.1.0；修复后重新构建
Core commit: 587111368390479b7f65feb881c9257c02e508b5，应用项目唯一 worker-exit patch
Test: 修复 GStreamer pipeline 日志误判；固定 `-p 47000` 端口组；Swift Testing；standalone 自定义端口启动/停止；干净环境 App 启动；bundle 验证；DMG 打包
Result: 通过。`Begin streaming to GStreamer video pipeline` 不再产生 `clientConnected`；配置固定为 `-p 47000 -nh -a -vs avlayer -fps 60 -vsync no -reset 8 -nofreeze -nohold -s 1920x1080`；standalone 和 App 日志均显示 TCP/UDP 47000、47001、47002，并成功初始化 server socket；clean-environment restart loop 2/2 及扩展的 20/20 均通过；未把本地结果当成真实 AirPlay 连接通过
Observed latency: 未测量
Observed resolution: 未测量
Observed FPS: 未测量
Disconnect behavior: 未执行真实设备断连；本地未观察到旧 TCP 7000 socket error
Rotation behavior: 未在 iPhone 上观察
Douyin capture result: 未执行
Log path: ~/Library/Logs/FrameRelay/FrameRelay.log（实际运行时路径）
```

## 2026-09-12 — 窗口、帧节奏与锁屏恢复修复后本地验证

```text
Date: 2026-09-12
Mac: MacBook Pro 2021, Apple M1 Pro, arm64（主机工具链）
macOS: 26.5（build 25F71）
iPhone: 未执行真实设备测试
iOS: 未执行真实设备测试
Network: 本机端口绑定和本机 Bonjour 启动检查；未验证 iPhone 与 Mac 的同一局域网连接
FrameRelay build: dist/FrameRelay.app 0.1.0；修复后重新构建；dist/FrameRelay-0.1.0-arm64.dmg
Core commit: 587111368390479b7f65feb881c9257c02e508b5，应用项目 patches/0001 和 patches/0002
Test: 普通 App/原生窗口静态验收；横屏/竖屏 VideoWindowSizer 单元测试；默认 timestamp sync；avlayer PTS/duration、零基准 CMTimebase、ready queue 丢帧和 pause/resume flush 构建验收；Swift Testing release；bundle/codesign；干净环境 restart loop 20 次
Result: 通过本地实现与静态/自动化验收。App 使用 regular activation policy，不声明 LSUIElement，窗口具备标题栏、关闭、最小化、缩放和 Stage Manager 应用身份；横竖屏几何测试通过；上游修复补丁可从干净固定提交重放并成功构建 core/standalone；Release Swift Testing 12/12；clean-environment restart loop 20/20；bundle 无 Homebrew 或项目 build 绝对依赖。未把本地结果当成真实 AirPlay 连接通过
Observed latency: 未测量（必须由真实 iPhone 连接后测量）
Observed resolution: 未测量（必须由真实 iPhone 日志中的 videoStarted 几何记录）
Observed FPS: 未测量；运行时日志会以 avlayer performance 每秒记录 pulled/enqueued/dropped/output_fps/drop_fps；不把 -fps 60 当作强制值
Disconnect behavior: 未执行真实设备断连；pause/resume 与正常 stop 路径已实现显示层清空和时间基准重置
Rotation behavior: 未在 iPhone 上观察；横屏/竖屏尺寸计算单元测试通过
Douyin capture result: 未执行
Log path: ~/Library/Logs/FrameRelay/FrameRelay.log（实际运行时路径）
```

## 2026-09-12 — 真实 iPhone 15 Pro Max / iOS 26.5 门禁

```text
Date: 2026-09-12
Mac: 待现场填写：MacBook Pro 2021, M1 Pro, arm64
macOS: 待现场填写：26.5
iPhone: 待执行：iPhone 15 Pro Max
iOS: 待执行：26.5
Network: 待填写：同一局域网、是否启用客户端隔离、Mac 接口
FrameRelay build: dist/FrameRelay.app 0.1.0（待现场运行）
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: standalone 固定命令 -> iPhone 控制中心“屏幕镜像”选择 FrameRelay -> 真实游戏 -> 10 分钟 -> 横竖屏 -> 停止镜像 -> 再次连接 -> 抖音窗口捕获
Result: PENDING_REAL_DEVICE
Observed latency: 待测量
Observed resolution: 待观察
Observed FPS: 待观察；记录 iPhone 实际发送值，不把 -fps 60 当作强制值
Disconnect behavior: 待观察；必须确认不保留冻结最后一帧
Rotation behavior: 待观察
Douyin capture result: 待执行；必须确认只捕获 FrameRelay 窗口
Log path: ~/Library/Logs/FrameRelay/FrameRelay.log
```

## 2026-09-13 — 真实 iPhone 15 Pro Max / 1080p no-sync 对照

```text
Date: 2026-09-13（北京时间；日志时间为 2026-09-12 UTC）
Mac: MacBook Pro 2021, Apple M1 Pro, arm64
macOS: 26.5
iPhone: iPhone 15 Pro Max（日志识别为 iPhone16,2）
iOS: 26.5
Network: Wi-Fi；沿用本轮测试网络；Mac 与 iPhone 通过 IPv6 link-local 建立连接
FrameRelay build: dist/FrameRelay.app 0.1.0；启动参数 --diagnostic-1080p-nosync
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: 关闭 macOS 隔空播放接收器；不启用抖音窗口捕获；连接后等待、快速滑动、静置、iPhone 锁屏 5 秒后解锁；随后主动退出 FrameRelay
Result: 成功连接，FrameRelay 未崩溃并正常退出；快速滑动仍明显卡顿；延迟稳定但偏高，没有继续累积；解锁后约 1–2 秒恢复。日志显示初始客户端 encoderCurrentFPS=60，随后长期为 30；接收端 avlayer output_fps 在 0.5–29.5 之间波动，抽取到的 120 个统计点平均约 15.68；绝大多数统计点 dropped=0，但该计数只代表 AVLayer enqueue 路径，不代表真实屏幕呈现帧率。客户端 FPSdata 中 sinkOverflowDropFPS 最高约 60，lossAvg 最高约 0.50，encoderQueueDropFPS 持续为 0 或接近 0。
Observed latency: 稳定偏高；未用双屏高速摄影做绝对毫秒测量
Observed resolution: 498×1080；source 886×1920，portrait，rot=0x00
Observed FPS: no-sync 未改善；客户端从 60 fps 很快降至 30 fps；本地 avlayer enqueue 统计明显低于客户端报告并且持续抖动
Disconnect behavior: 主动退出后记录 video_reset: RTP_Shutdown、Open connections: 0；未观察到崩溃
Rotation behavior: 本轮未主动做横竖屏切换；锁屏恢复阶段出现 0x56 暂停标记，约 7 秒后出现 0x16 恢复标记并重新开始视频流日志
Douyin capture result: 未启用；本轮只验证 FrameRelay 单独显示
Log path: ~/Library/Logs/FrameRelay/FrameRelay.log；本次会话约为 UTC 16:24:48–16:27:43
```

## 2026-09-13 — Phase 3A 分段诊断实现与本地构建

```text
Date: 2026-09-13（Asia/Shanghai）
Mac: MacBook Pro 2021, Apple M1 Pro, arm64（主机工具链）
macOS: 26.5, build 25F71
iPhone: 待执行：iPhone 15 Pro Max
iOS: 待执行：26.5
Network: 待执行；真实设备复测必须沿用同一 Wi-Fi/AP
FrameRelay build: dist/FrameRelay.app 0.1.0；诊断入口为 --diagnostic-1080p
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: 应用 0003 诊断补丁；重复构建 core/standalone；构建 App；打包并校验 GStreamer bundle；验证 ad-hoc 签名、arm64 和相对依赖
Result: 通过。`Scripts/build-core.sh`、`Scripts/build-app.sh`、`Scripts/bundle-gstreamer.sh`、`Scripts/verify-bundle.sh` 全部通过；0003 可在 0001/0002 后 reverse-check；普通启动选项未改变。`swift test -c release` 未通过，原因是现有测试导入 `Testing` 但当前 Package/主机没有该模块；未因本次诊断引入第三方 Swift 依赖。
Observed latency: 待真实设备复测；本阶段不测量
Observed resolution: 待真实设备复测；诊断 profile 请求 1920×1080 上限
Observed FPS: 待真实设备复测；新日志应同时记录 encoderCurrentFPS、transport input_fps、pipeline push/callback_fps 和 avlayer performance
Disconnect behavior: 待真实设备复测
Rotation behavior: 待真实设备复测
Douyin capture result: 待执行；本阶段不改变抖音配置
Log path: ~/Library/Logs/FrameRelay/FrameRelay.log
Expected diagnostic lines: `FrameRelay diagnostic transport`, `decoder`, `caps`, `pipeline`, `avlayer`；锁屏/解锁测试还应出现 `FrameRelay diagnostic marker`
Commands: `./Scripts/build-core.sh`; `swift test -c release`; `./Scripts/build-app.sh`; `./Scripts/bundle-gstreamer.sh`; `./Scripts/verify-bundle.sh`
```

## 自动化测试明细

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：11 项通过。
- 真实上游 parser marker：`Initialized server socket(s)`、`advertised AirPlay service`、
  `connection request from`、`Open connections: 1/0`、裸 `Begin streaming`、reset、
  stop：通过；`Begin streaming to GStreamer video pipeline` 明确不产生事件：通过。
- C bridge 动态 fixture：缺失 dylib、缺失 symbol、短错误缓冲区、重复 start/stop、
  `stop -> log callback clear -> window clear -> destroy` 连续 20 次：通过。
- `Scripts/build-core.sh`：core 和 standalone 均为 Mach-O arm64，8 个固定 C ABI 导出
  存在。
- `Scripts/verify-bundle.sh`：Info.plist、资源、arm64、codesign、无 Homebrew/项目
  build 绝对依赖：通过。
- 修复前 bundle clean-environment 启动曾因当前 macOS ControlCenter 监听 TCP 7000，
  使旧的 UxPlay Legacy socket 报 `Error initialising socket 48`；这是本次端口修复的
  回归基线，不是缺插件。
- 修复后 standalone 和 bundle clean-environment 启动均记录：
  `using network ports UDP 47000 47001 47002 TCP 47000 47001 47002`、
  `Initialized server socket(s)`；未再出现 TCP 7000 socket error。
- `dns-sd -B _airplay._tcp`：在端口冲突期间仍观察到 `FrameRelay` 广播；尚未完成
  可连接的 `_raop._tcp`/iPhone 端到端验收。
- `env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$HOME" STARTUP_WAIT_SECONDS=6
  Scripts/restart-loop.sh 2`：2/2 通过；没有缺插件、worker 意外退出或 socket error。
- `env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$HOME" STARTUP_WAIT_SECONDS=2
  Scripts/restart-loop.sh 20`：20/20 通过；验证连续启动/停止不会重新引入旧端口冲突或
  启动错误。该循环不替代真实 iPhone 视频持续时间测试。
- standalone 固定命令（追加 `-p 47000`）：启动、报告自定义端口组、收到停止信号后
  清理 `Stopping RAOP Server...`：通过。
- 修复后 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test -c release`：
  12 项通过；新增横屏/竖屏窗口尺寸计算测试，并覆盖 0002 视频修复所依赖的固定配置。
- 修复后 `Scripts/build-core.sh`：从固定 UxPlay commit 重放 patches/0001 与 patches/0002，
  core/standalone 均成功构建为 arm64；avlayer 时间戳、队列限流和 pause/resume 清帧代码
  编译通过。macOS 26 SDK 仅产生已记录的 AVSampleBufferDisplayLayer 弃用警告。
- 修复后 `Scripts/verify-bundle.sh` 与 `Scripts/package-dmg.sh`：App/DMG 重新生成，
  Info.plist 不含 LSUIElement，签名、arm64、插件目录和相对依赖检查通过。

历史构建产物 SHA-256（2026-09-12）：

```text
FrameRelay.app/Contents/MacOS/FrameRelay:
10471b40bf24e7bce93b65046f879018da4c7d340c7b66f1e922b8ac2d8b35ac
FrameRelay.app/Contents/Frameworks/uxplay-core.dylib:
2f0748c80b229fcc9b8c20665dd08ec23470f673add62e308115db7857116153
FrameRelay-0.1.0-arm64.dmg:
2cc448a17fef3b95c5dd2f670f3c0569eb84a051f610983b1da43fd23c60ae42
```

## 2026-09-12 — 帧率根因诊断模式构建（真实设备待执行）

```text
Date: 2026-09-12
Mac: MacBook Pro 2021, Apple M1 Pro, arm64（主机工具链）
macOS: 26.5
iPhone: 待执行：iPhone 15 Pro Max
iOS: 待执行：26.5
Network: 待执行；两次测试必须保持同一 Wi-Fi、同一 AP、同一网络设置
FrameRelay build: dist/FrameRelay.app 0.1.0；增加 opt-in --diagnostic-1080p/--diagnostic-720p；本轮增加 --diagnostic-1080p-nosync
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: Release Swift Testing、诊断 profile 选项/参数测试、App 重建、GStreamer bundle、静态验证
Result: 本轮源代码/文档变更已完成本地构建验证；13/13 Swift Testing、App/bundle/codesign、arm64、GStreamer bundle 和 DMG 验证通过。真实 1080p/720p 已执行；1080p no-sync 尚未执行
Observed latency: 待真实设备测量
Observed resolution: 待真实设备观察；诊断配置分别宣告 1920×1080 和 1280×720 上限
Observed FPS: 已完成的 1080p/720p 日志已读取 UxPlay -FPSdata 和 avlayer performance；no-sync profile 待真实设备观察
Disconnect behavior: 未执行本次诊断断连测试
Rotation behavior: 未执行本次诊断旋转测试
Douyin capture result: 未执行；诊断阶段先不改变抖音配置
Log path: ~/Library/Logs/FrameRelay/FrameRelay.log
```

## 2026-09-13 — Phase 3A 分段诊断构建（真实设备待执行）

```text
Date: 2026-09-13
Mac: MacBook Pro 2021, Apple M1 Pro, arm64（主机工具链）
macOS: 26.5（build 25F71）
iPhone: iPhone 15 Pro Max；本记录尚未执行新诊断采样
iOS: 26.5；本记录尚未执行新诊断采样
Network: 待真实设备复测；保持 Mac 与 iPhone 同一 Wi-Fi、同一 AP
FrameRelay build: dist/FrameRelay.app 0.1.0；新增 `--diagnostic-1080p` 分段诊断 profile
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: 固定 UxPlay commit 上的 patch 0003；core/standalone 构建；App 构建；GStreamer 打包；bundle/codesign/DMG 静态验证；patch reverse-check
Result: core、standalone、App、GStreamer bundle、ad-hoc codesign、`Scripts/verify-bundle.sh` 和 DMG 均通过；普通启动路径未改变。`swift test -c release` 当前环境失败于缺少 `Testing` 模块，未引入第三方依赖或改变测试框架；真实设备诊断尚未执行
Observed latency: 待真实设备复测
Observed resolution: 待真实设备复测；profile 请求 1920×1080 上限
Observed FPS: 待读取 `encoderCurrentFPS`、transport `input_fps`、pipeline/appsrc/appsink 和 avlayer 分段指标
Disconnect behavior: 待真实设备复测
Rotation behavior: 待真实设备复测
Douyin capture result: 待执行；本轮先不改变抖音配置
Log path: ~/Library/Logs/FrameRelay/FrameRelay.log
App SHA-256: e3efe306b329527460a77eae50135ea9c2ec7501671fac24de07c2c898f61600
Core SHA-256: 8da101bee18c6e012c7740c625d862a36f9f14b254ed72097204d97a503d855e
DMG SHA-256: 980d775ab39d3ceae7688e931f4095231aa5c20d84dd44abaefb7b5ca4d37de6
```

## 2026-09-12 — 1080p no-sync 诊断 profile 构建（真实设备待执行）

```text
Date: 2026-09-12
Mac: MacBook Pro 2021, Apple M1 Pro, arm64（主机工具链）
macOS: 26.5
iPhone: iPhone 15 Pro Max（上一轮日志已识别为 iPhone16,2）
iOS: 26.5
Network: 必须沿用上一轮测试的同一 Wi-Fi、同一 AP、同一网络设置
FrameRelay build: dist/FrameRelay.app 0.1.0；新增 --diagnostic-1080p-nosync
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: 1920×1080；仅增加 -vsync no 和 -FPSdata；不改变端口、avlayer、-fps 60 或 -a
Result: 本地构建、13/13 Swift Testing、arm64 App、GStreamer bundle、静态 Bundle 校验、ad-hoc 签名和 DMG 均通过；待真实设备执行
Observed latency: 待与此前 1080p timestamp-sync 测试比较
Observed resolution: 预期仍为 iPhone 实际协商的 1920×1080 上限路径
Observed FPS: 待读取 encoderCurrentFPS、avlayer output_fps 和 dropped
Disconnect behavior: 待观察
Rotation behavior: 本轮不主动旋转；待连接期间自然变化时记录
Douyin capture result: 本轮先不改变抖音配置；如使用抖音，记录 FrameRelay 窗口和抖音预览分别是否卡顿
Log path: ~/Library/Logs/FrameRelay/FrameRelay.log
```

## 2026-09-13 — 真实 iPhone 15 Pro Max / 锁屏解锁恢复诊断

```text
Date: 2026-09-13（北京时间 01:20–01:22；日志时间为 2026-09-12 UTC 17:20–17:22）
Mac: MacBook Pro 2021, Apple M1 Pro, arm64
macOS: 26.5
iPhone: iPhone 15 Pro Max（日志识别为 iPhone16,2）
iOS: 26.5
Network: Wi-Fi；沿用本轮真实设备连接网络
FrameRelay build: dist/FrameRelay.app 0.1.0；启动参数 `--diagnostic-1080p`
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: 1080p 默认 timestamp sync；连接后观察滑动；按 iPhone 锁屏键；点亮但不解锁；再解锁回到横屏游戏；观察 FrameRelay 恢复；结束时主动退出
Result: 锁屏前链路正常。01:21:49 左右出现 `FrameRelay diagnostic marker: action=pause code=0x56`；01:21:58 出现 `action=resume code=0x16`，并收到 `498×1080 rot=0x00` 的竖屏流。随后约 8 秒后再次收到 `1920×884 rot=0x07` 的横屏流。手机已经恢复发送视频，但显示层在 resume 后先只接受少量帧，随后持续拒绝新帧，造成旧游戏画面冻结和窗口/画面方向恢复异常。
Observed latency: 未做绝对毫秒测量；锁屏恢复表现为明显延迟
Observed resolution: 锁屏前 `1920×884 rot=0x07`；resume 后 `498×1080 rot=0x00`；约 8 秒后重新出现 `1920×884 rot=0x07`
Observed FPS: 锁屏前 `encoderCurrentFPS=60`、transport 约 59–60、avlayer 约 59–60；resume 后第一段含约 8.96 秒到达间隔，随后 input 约 66.5 FPS 但 output 约 7.9 FPS；再后 input 约 55–62 FPS 而 output 为 0，`ready_rejects` 连续约 56–63。PixelBuffer/copy/format/sample 计数在拒收期间为 0，说明瓶颈在 AVSampleBufferDisplayLayer 入队前的 ready/back-pressure 状态，不在拷贝或解码耗时。
Disconnect behavior: 测试结束时主动退出；未出现应用崩溃
Rotation behavior: UxPlay 核心正确识别了 portrait `rot=0x00` 和随后 landscape `rot=0x07`；但 resume 后 AVLayer 持续拒收，画面仍停留在旧帧。日志没有记录 Swift 窗口几何回调，因此窗口是否在第二次横屏几何事件后调整还需要在修复版增加宿主侧日志确认。
Douyin capture result: 未启用抖音窗口捕获
Log path: ~/Library/Logs/FrameRelay/FrameRelay.log
Root cause hypothesis: `avlayer_sink_pause/resume` 将显示 timebase 重置为零，但同一 GStreamer pipeline 在 PAUSED -> PLAYING 后继续产生相对旧 pipeline base time 的 PTS；少量样本进入后填满 AVSampleBufferDisplayLayer 的时间队列，`readyForMoreMediaData` 长时间为 false，导致后续帧全部被拒收。该假设需通过 PTS 重基准修复和下一轮日志验证。
Next action: 在不改变端口、编码器、窗口架构或正常启动参数的前提下，为 pause/resume 增加首个恢复帧 PTS 重基准；同时增加 Swift `videoStarted`/窗口几何应用日志；重新构建并重复同一锁屏/点亮/解锁测试。
```

## 2026-09-13 — Phase 3B 锁屏/解锁 PTS 重基准修复本地构建

```text
Date: 2026-09-13
Mac: MacBook Pro 2021, Apple M1 Pro, arm64（主机工具链）
macOS: 26.5（build 25F71）
iPhone: 待真实回归：iPhone 15 Pro Max
iOS: 待真实回归：26.5
Network: 待真实回归；必须沿用同一 Wi-Fi、同一 AP
FrameRelay build: dist/FrameRelay.app 0.1.0；增加 pause/resume 首帧 PTS 重基准和 Swift host 几何诊断日志
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: 四个 UxPlay patch 幂等重放；core/standalone 构建；Swift release build；Swift Testing；GStreamer 打包；bundle/codesign/DMG 静态验证
Result: 本地验证通过：core、standalone、App、GStreamer bundle、ad-hoc codesign、verify-bundle、DMG 和 13/13 Swift Testing 均通过。`patches/0004-uxplay-resume-pts-rebase.patch` reverse-check 通过。真实设备锁屏/点亮不解锁/解锁回游戏尚未执行，不能据此标记修复验收通过。
Observed latency: 待真实回归
Observed resolution: 待真实回归；正常配置仍请求最高 1920×1080
Observed FPS: 待真实回归；诊断日志应核对 resume 后 output_fps/enqueue 是否恢复
Disconnect behavior: 待真实回归
Rotation behavior: 待真实回归；诊断日志应核对第二次横屏 videoStarted 的 applied=true
Douyin capture result: 待真实回归
Log path: ~/Library/Logs/FrameRelay/FrameRelay.log
App SHA-256: 8cf4e6e93e930a0ddf1ae352d7f2871e9daf724b263c712fe27edb3d2a9b908c
Core SHA-256: fb76d6ba3d65e108ddf70e423f0e762a44af22f5e50ac3117c1e66f10464e7cb
DMG SHA-256: 231ce9d224c31c13f3e430ac40a7a6a60669c44c8692f41d7db03789020a73a4
```

## 2026-09-13 — Phase 3B 打包后运行时启动检查

```text
Date: 2026-09-13
Mac: MacBook Pro 2021, Apple M1 Pro, arm64（主机工具链）
macOS: 26.5（build 25F71）
iPhone: 未连接
iOS: 不适用
Network: 未进行 iPhone 连接
FrameRelay build: dist/FrameRelay.app 0.1.0；Phase 3B 修复版
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: STARTUP_WAIT_SECONDS=2 ./Scripts/restart-loop.sh 1
Result: 1/1 通过；签名后的 App 成功加载内置 uxplay-core.dylib 和 GStreamer 运行库并正常退出；没有 dyld、缺插件、worker 异常退出或固定端口启动错误。本测试未连接 iPhone，不替代真实设备回归。
Observed latency: 不适用
Observed resolution: 不适用
Observed FPS: 不适用
Disconnect behavior: 未连接 iPhone
Rotation behavior: 未连接 iPhone
Douyin capture result: 未执行
Log path: ~/Library/Logs/FrameRelay/FrameRelay.log
```

## 2026-09-13 — Phase 3C 触发条件：快速锁屏/点亮/解锁后画面冻结

```text
Date: 2026-09-13（北京时间约 03:16；日志时间为 2026-09-12 UTC 19:16–19:18）
Mac: MacBook Pro 2021, Apple M1 Pro, arm64
macOS: 26.5
iPhone: iPhone 15 Pro Max（日志识别为 iPhone16,2）
iOS: 26.5
Network: Wi-Fi；沿用真实设备连接网络
FrameRelay build: dist/FrameRelay.app 0.1.0；Phase 3B 修复版；启动参数 `--diagnostic-1080p`
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: 完成前五步后误按 iPhone 锁屏键，随后立即点亮、解锁并回到横屏游戏；观察 FrameRelay 窗口
Result: 锁屏前连接、窗口和投屏正常。恢复后窗口变为横向，但画面停留在竖屏锁屏密码界面，
  两侧出现黑边；截图证明旧的竖屏密码帧仍在显示层，不能视为正常的锁屏画面转场。
Observed latency: 快速恢复后画面未实时跟随；出现持续冻结
Observed resolution: 恢复前横屏 `1920×884 rot=0x04`；恢复阶段曾收到竖屏 `498×1080 rot=0x00`，
  窗口随后按横屏 `1920×884` 几何调整
Observed FPS: 恢复后的 transport/input 和解码回调约 58–60 FPS；AVLayer `output_fps=0`，
  `ready_rejects` 连续覆盖输入帧；PixelBuffer、copy、format、sample 计数在拒收区间为 0
Disconnect behavior: 用户结束测试并退出；未观察到 FrameRelay 崩溃
Rotation behavior: Swift host 几何应用成功；AVLayer 因恢复后的 ready/back-pressure 停滞而继续显示旧竖屏帧
Douyin capture result: 未启用抖音窗口捕获
Log path: ~/Library/Logs/FrameRelay/FrameRelay.log
Root cause: Phase 3B 虽然把恢复帧 PTS 重基准到零，但 resume marker 到第一枚恢复帧之间约 756 ms
  的空档仍让显示 CMTimebase 提前运行；同时 layer 的 `readyForMoreMediaData` 保持 NO。结果是
  第一枚恢复帧到达时已经落后，后续帧在 enqueue 前全部被 ready gate 拒收。窗口几何本身不是根因。
Next action: 实施 Phase 3C：resume 时停止显示时钟，首枚恢复帧到达时完成 timebase anchor，并允许
  仅一枚恢复 seed 帧通过 not-ready gate；保持普通播放的有限队列和低延迟丢帧策略不变。
```

## 2026-09-13 — Phase 3C 修复版本地构建与独立启动检查

```text
Date: 2026-09-13（Asia/Shanghai）
Mac: MacBook Pro 2021, Apple M1 Pro, arm64（主机工具链）
macOS: 26.5（build 25F71）
iPhone: 待真实回归：iPhone 15 Pro Max
iOS: 待真实回归：26.5
Network: 待真实回归；必须沿用同一 Wi-Fi、同一 AP
FrameRelay build: dist/FrameRelay.app 0.1.0；Phase 3C 恢复首帧显示时钟锚定修复；启动参数仍为默认 1080p，诊断测试使用 `--diagnostic-1080p`
Core commit: 587111368390479b7f65feb881c9257c02e508b5；patches/0001–0005
Test: build-core；Swift release build；Swift Testing；build-app；bundle-gstreamer；verify-bundle；package-dmg；清空 Homebrew 环境变量后 restart-loop 2 次
Result: 通过。core、standalone、App、内置 GStreamer 依赖、ad-hoc codesign、DMG 和静态 bundle 检查均通过；clean-environment restart loop 2/2 通过。未连接真实 iPhone，不能替代 Phase 3C 设备验收。
Observed latency: 待真实回归
Observed resolution: 待真实回归；正常配置仍请求最高 1920×1080
Observed FPS: 待真实回归；Phase 3C 未改变 `-fps 60` 或正常 timestamp sync
Disconnect behavior: 待真实回归
Rotation behavior: 待真实回归；必须核对恢复后的第二次横屏 host geometry `applied=true`
Douyin capture result: 待真实回归
Log path: ~/Library/Logs/FrameRelay/FrameRelay.log
App SHA-256: 6171029c83aec5007a94a8bdee6e66dfc7fffbd5654a943d450ca8743ea8d6a8
Core SHA-256: 978699d205a512c48b7203bab0802747743d10e8cace0435dab0ba939a1e68cb
DMG SHA-256: 08efbb01c0b360c3082c9f91c12ff99e25da2fa350715e0be3346efaa6cfaa24
Compiler note: pinned macOS SDK reports existing AVSampleBufferDisplayLayer compatibility API deprecation warnings；构建无错误，verify-bundle/codesign 通过
```

## 2026-09-13 — Phase 3D 格式切换恢复实现与 core 构建

```text
Date: 2026-09-13（Asia/Shanghai）
Mac: MacBook Pro 2021, Apple M1 Pro, arm64
macOS: 26.5（build 25F71）
iPhone: iPhone 15 Pro Max（真实回归待执行）
iOS: 26.5（真实回归待执行）
Network: 待真实回归；必须沿用既有 Wi-Fi、AP 和本地网络权限
FrameRelay build: dist/FrameRelay.app 0.1.0；Phase 3D 格式切换恢复；dist/FrameRelay-0.1.0-arm64.dmg
Core commit: 587111368390479b7f65feb881c9257c02e508b5；patches/0001–0006
Test: patch 0006 reverse-check；从 pinned SHA 依次应用 0001–0006 的源码一致性；git diff check；build-core；Swift release build/test；build-app；bundle-gstreamer；verify-bundle；package-dmg；clean-environment restart-loop 2 次
Result: 通过。`uxplay-core.dylib`、standalone `uxplay` 和 App 均以 arm64 成功构建；Swift Testing 13/13 通过；内置 GStreamer 依赖、ad-hoc codesign、静态 bundle 检查、DMG 和无 Homebrew 环境启动 2/2 均通过。仅有 macOS 26 SDK 对既有 AVSampleBufferDisplayLayer 兼容 API 的弃用警告。尚未连接真实 iPhone，不能替代设备验收。
Observed latency: 待真实回归
Observed resolution: 待真实回归；正式路径仍为最高 1920×1080
Observed FPS: 待真实回归；本 patch 不改变 `-fps 60` 或默认 timestamp sync
Disconnect behavior: 待真实回归
Rotation behavior: 待真实回归；必须核对竖屏锁屏流→横屏游戏流的实际 sample output 尺寸和 `format_flushes`
Douyin capture result: 待真实回归
Log path: ~/Library/Logs/FrameRelay/FrameRelay.log
Static evidence: `FrameRelay avlayer format transition`、`FrameRelay diagnostic sample: output=WxH` 和 `format_flushes` 已加入待收集日志项
App SHA-256: 047f72449de9b5d2f6c14cb4f158308b08f9e2aa600f6ce6c8552842350723aa
Core SHA-256: 26f1ee9c6881f150a506ac8eb4523cf55275a019ca8770c8b5a10b6c42c2a613
DMG SHA-256: 17c202091745344bd605e9a0d8a278aa2df97c889ac623ed6798d0461b3192a3
```

## 2026-09-13 — Phase 3D 真实设备：输入持续但显示画面冻结

```text
Date: 2026-09-13（北京时间 04:40:53–04:41:00；日志时间为 2026-09-12 UTC 20:40:53–20:41:00）
Mac: MacBook Pro 2021, Apple M1 Pro, arm64
macOS: 26.5
iPhone: iPhone 15 Pro Max（日志识别为 iPhone16,2）
iOS: 26.5
Network: Wi-Fi；沿用真实设备连接网络，IPv6 link-local
FrameRelay build: dist/FrameRelay.app 0.1.0；Phase 3D / patches 0001–0006；启动参数 `--diagnostic-1080p`
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: 横屏游戏→锁屏→点亮但不解锁并观察锁屏操作→解锁回横屏游戏；观察画面是否持续更新
Result: 失败。日志显示 pause marker `0x56`、resume marker `0x16`，实际视频流从 `1920×884 rot=0x07` 切到 `498×1080 rot=0x00`，再切回横屏；transport/input、decoder、PixelBuffer、copy、sample 和 enqueue 均持续增长，`ready_rejects=0`，但用户可见画面仍停在亮屏/解锁后的第一帧。该证据把问题定位到显示呈现调度，而不是输入、解码或 ready gate 拒收。
Observed latency: 未做绝对毫秒测量；画面稳定但明显不实时
Observed resolution: portrait `498×1080`，随后 landscape `1920×884`；source 约 `886×1920`
Observed FPS: 输入约 57–65 FPS；AVLayer `pulled/enqueued` 约 59–63 FPS；`ready_rejects=0`。`output_fps` 只代表 enqueue，不代表物理显示器呈现 FPS
Disconnect behavior: 测试结束时主动退出；未观察到崩溃
Rotation behavior: 竖屏→横屏的 `videoStarted`、实际 appsink 输出尺寸和 format flush 均出现；窗口 geometry 已应用，但图像仍冻结
Douyin capture result: 未启用抖音窗口捕获
Log path: ~/Library/Logs/FrameRelay/FrameRelay.log
Conclusion: Phase 3B/3C 的 PTS rebase 与 CMTimebase anchor 不能解决“持续入队但首帧冻结”；进入 Phase 3E，移除 live AVLayer 的时间基准调度，改为无时间戳 `DisplayImmediately`
```

## 2026-09-13 — Phase 3E live immediate presentation build

```text
Date: 2026-09-13（Asia/Shanghai）
Mac: MacBook Pro 2021, Apple M1 Pro, arm64（主机工具链）
macOS: 26.5（build 25F71）
iPhone: 待真实回归：iPhone 15 Pro Max
iOS: 待真实回归：26.5
Network: 待真实回归；必须沿用既有 Wi-Fi、AP 和本地网络权限
FrameRelay build: dist/FrameRelay.app 0.1.0；Phase 3E；启动参数仍为默认 1080p，诊断使用 `--diagnostic-1080p`
Core commit: 587111368390479b7f65feb881c9257c02e508b5；patches/0001–0007
Test: patch 0007 reverse-check；从 pinned SHA 依次应用 0001–0007 并比对源码；core/standalone；Swift build/test；App/bundle/codesign/DMG；20 次 clean-environment restart loop
Result: 通过本地验证。自定义 live AVLayer 删除 `CMTimebase` 创建/绑定/anchor，使用无效 sample timing 和 `DisplayImmediately`；custom renderer 设置 `vsync_prop=false`，不向 appsrc 附加 sender PTS；有限队列、ready gate、pause/format flush 和 seed 保留。真实 iPhone 回归尚未执行，不能据此宣称视觉问题已修复。
Observed latency: 待真实回归
Observed resolution: 正式路径仍请求最高 1920×1080
Observed FPS: 待真实回归；本地没有真实视频帧输入
Disconnect behavior: clean-environment 20/20 启动/退出通过；真实设备待测
Rotation behavior: 待真实回归；需验证亮屏锁屏操作和解锁后横屏游戏均持续更新
Douyin capture result: 待真实回归
Log path: ~/Library/Logs/FrameRelay/FrameRelay.log
App SHA-256: 7aaeaf02ed0b16a75939b4047b93d6bd0703978b2925faab247ab879edd9c877
Core SHA-256: 32f04ddc063f6e74b9be8789da811c0d0aa4bf9c16ec858595b0edad7fb52c3d
DMG SHA-256: 8a826977ffb7235989e4bd5d72b513d9dc863fecbce00bbf3687da073c48e2960
```

## 2026-09-13 — Phase 3E 真实设备回归：锁屏恢复通过，保留唤醒延迟

```text
Date: 2026-09-13（北京时间约 05:21:28–05:22:58；日志时间为 2026-09-12 UTC 21:21:28–21:22:58）
Mac: MacBook Pro 2021, Apple M1 Pro, arm64
macOS: 26.5
iPhone: iPhone 15 Pro Max（日志识别为 iPhone16,2）
iOS: 26.5
Network: Wi-Fi；IPv6 link-local；沿用真实设备局域网
FrameRelay build: dist/FrameRelay.app 0.1.0；Phase 3E / patches 0001–0007；启动参数 `--diagnostic-1080p`
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: 1080p 横屏游戏→锁屏→点亮并操作锁屏界面→解锁回横屏游戏；重复快速锁屏/点亮/解锁；最后退出 App
Result: 通过。共检测到 9 组 pause/resume。锁屏操作和解锁后的横屏游戏均能继续更新，未再出现停在亮屏或解锁第一帧的冻结。横竖屏格式切换、窗口几何应用和恢复后的持续入队均正常。
Observed latency: 未做端到端绝对延迟测量；AirPlay 唤醒恢复耗时约 0.7–1.6 秒，最长诊断 recovery 约 1624 ms；恢复后不是冻结而是回到稳定视频流。
Observed resolution: portrait `498×1080`；landscape `1920×884`；source 约 `886×1920`
Observed FPS: 59 个诊断窗口；transport input_fps 范围 15.3–66.7，平均 52.1（包含唤醒空档）；稳定恢复区间约 55–66 FPS。AVLayer pulled=3321、enqueued=3278、dropped=43；`output_fps` 仅代表 enqueue 计数，不代表物理显示器 vsync。
Disconnect behavior: 结束时出现 `RTP_Shutdown`，随后 `Open connections: 0` 和 `Stopping RAOP Server`；无崩溃、死锁或残留 FrameRelay 进程
Rotation behavior: 记录 9 次需要应用的格式/窗口几何变化；`videoStarted ... applied=true`；重复相同几何时 `applied=false` 为预期行为
Douyin capture result: 未在本次回归中启用抖音窗口捕获
Log path: ~/Library/Logs/FrameRelay/FrameRelay.log（本次日志区间约为第 18020–19615 行）
Diagnostic evidence: `layer_failed_flushes=0`、PixelBuffer/format/sample 失败为 0、`push_flow_errors=0`、`appsink_dropped=0`、`sinkOverflowDropFPS=0`；恢复后 enqueue 持续增长
Known limitation: AirPlay 唤醒阶段约 0.7–1.6 秒恢复延迟；当前不改协议、不添加 `-fps 120`，也不把该延迟误判为显示层冻结
Next action: 继续剩余 Phase 3/Phase 4 验收：抖音窗口捕获、30/60 分钟稳定性、断连处理和从 DMG 独立目录启动
App SHA-256: 7aaeaf02ed0b16a75939b4047b93d6bd0703978b2925faab247ab879edd9c877
Core SHA-256: 32f04ddc063f6e74b9be8789da811c0d0aa4bf9c16ec858595b0edad7fb52c3d
DMG SHA-256: 8a826977ffb7235989e4bd5d72b513d9dc863fecbce00bbf3687da073c48e2960
```

## 2026-09-13 — Phase 3F 唤醒空档归因与 AVLayer 快速恢复本地验证

```text
Date: 2026-09-13（Asia/Shanghai）
Mac: MacBook Pro 2021, Apple M1 Pro, arm64
macOS: 26.5（build 25F71）
iPhone: 未连接；Phase 3E 的真实设备证据用于本阶段根因归因
iOS: 不适用本次本地验证
Network: 未进行本次 iPhone 连接
FrameRelay build: 当前源码；patches/0001–0008；正式 AirPlay options 未改变
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: `git diff --check`; `git -C third_party/uxplay diff --check`; `bash -n Scripts/build-core.sh`; `git -C third_party/uxplay apply --reverse --check ../../patches/0008-uxplay-fast-avlayer-resume.patch`; `Scripts/build-core.sh`; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Result: 0008 reverse-check、源码检查、core/standalone arm64 构建和 Swift Testing 均通过。Swift Testing 13/13 通过。构建只有既有 macOS 26 AVSampleBufferDisplayLayer 兼容 API 弃用警告。
Observed latency: 从既有 Phase 3E 日志重新计算：pause `0x56` 到 resume `0x16` 约 1510 ms；最大视频 arrival gap 约 1661 ms；原 recovery 1624 ms 是从 pause 计时，不能作为 resume 后本地恢复耗时。0008 已改为从 resume marker 计时。
Observed resolution: 未连接设备；正式路径仍请求最高 1920×1080
Observed FPS: 未连接设备；正式路径仍为 `-fps 60`
Disconnect behavior: 未连接设备；待真实回归
Rotation behavior: 未连接设备；待真实回归
Douyin capture result: 未执行
Log path: `~/Library/Logs/FrameRelay/FrameRelay.log`；根因证据来自 Phase 3E 真实设备区间约第 18020–19615 行
Files changed: `patches/0008-uxplay-fast-avlayer-resume.patch`; `Scripts/build-core.sh`; `docs/UPSTREAM.md`; `docs/PLAN.md`; `docs/DECISIONS.md`; `docs/ARCHITECTURE.md`; `docs/STATUS.md`; `docs/TESTLOG.md`; patched UxPlay renderer sources
Next exact action: 完成 App/bundle/verify/DMG 固定构建顺序，再用真实 iPhone 15 Pro Max / iOS 26.5 验证 resume→first accepted sample。
```

## 2026-09-13 — Phase 3F 发布包与幂等性验证

```text
Date: 2026-09-13（Asia/Shanghai）
Mac: MacBook Pro 2021, Apple M1 Pro, arm64
macOS: 26.5（build 25F71）
iPhone: 未连接；真实设备回归待执行
iOS: 26.5（待真实回归）
Network: 未进行 iPhone 连接
FrameRelay build: dist/FrameRelay.app 0.1.0；patches/0001–0008
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: `Scripts/build-app.sh`; `Scripts/bundle-gstreamer.sh`; `Scripts/verify-bundle.sh`; `Scripts/package-dmg.sh`; `env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$HOME" STARTUP_WAIT_SECONDS=2 ./Scripts/restart-loop.sh 2`; 0008 reverse→forward→reverse-check
Result: 全部通过。App、bundled GStreamer、arm64 core、ad-hoc signature、静态依赖检查、DMG 和 clean-environment restart loop 2/2 均通过。0008 可逆重放且 reverse-check 通过。
Observed latency: 未连接设备；真实回归必须分别记录 pause→resume、resume→first accepted sample、arrival_gap_max_ms。
Observed resolution: 未连接设备；正式路径仍请求最高 1920×1080
Observed FPS: 未连接设备；正式路径仍为 `-fps 60`
Disconnect behavior: clean-environment 启动/退出 2/2 通过；真实断连待测
Rotation behavior: 未连接设备；待真实回归
Douyin capture result: 未执行
Log path: `~/Library/Logs/FrameRelay/FrameRelay.log`
App SHA-256: cc6bea487ffa3d2a2d746ea847016504cef34c6a50f8fb088291023485ef0d90
Core SHA-256: d2a7527eb8744b261ebdf4531dfedf01dc35e325c1991fbc2b8250279ff4ba2e
DMG SHA-256: 2bdd37b6a4953ae4b0f14be684ee860dd5d4be0a026d56a49210f5b2cb351bbb
Next exact action: 用新 App/DMG 在 iPhone 15 Pro Max / iOS 26.5 上执行 Phase 3F 真实锁屏唤醒回归。
```

## 2026-09-14 — Phase 3F 0008 真实设备锁屏唤醒回归

```text
Date: 2026-09-14（Asia/Shanghai）
Mac: MacBook Pro 2021, Apple M1 Pro, arm64
macOS: 26.5（build 25F71）
iPhone: iPhone 15 Pro Max（iPhone16,2）
iOS: 26.5
Network: Wi-Fi；IPv6 link-local；沿用既有局域网
FrameRelay build: dist/FrameRelay.app 0.1.0；patches/0001–0008；`--diagnostic-1080p`
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: 用户按 `docs/OPERATIONS.md` 启动 `/Users/danko/workspace/FrameRelay/dist/FrameRelay.app/Contents/MacOS/FrameRelay --diagnostic-1080p`，连接 Control Center → Screen Mirroring → FrameRelay，执行锁屏→亮屏不解锁→锁屏操作→解锁回游戏，并检查 `~/Library/Logs/FrameRelay/FrameRelay.log`。
Result: 通过。最新 session（UTC `2026-09-13T17:14:55Z`–`17:16:51Z`）出现 6 次 pause marker，其中前 5 次均有 resume，最后一次 pause 后用户退出。5 组完整回归均继续产出视频；最后一组长暂停后也没有 pipeline error 或显示层失败。
Observed latency: 5 组 pause→resume 分别约 0.680 ms、0.677 ms、0.518 ms、0.791 ms、3513.342 ms；最长一次对应 `arrival_gap_max_ms=3556.294`。关键 0008 指标为 resume→first accepted AVLayer sample `recovery_avg_ms=10.813`（recovery=1），说明接收端恢复不是 0.7–1.6 秒延迟的来源。
Observed resolution: 竖屏 `498x1080` 与横屏 `1920x884` 均出现；多次 `format transition` 和 `format_flushes=1` 后继续输出 sample。
Observed FPS: 长暂停所在统计窗口因发送端空档为 9.7 FPS；恢复后立即收到 61.5 FPS，随后约 55–60 FPS，显示层持续 enqueue。恢复瞬间出现短暂 ready gate backpressure，最大 `ready_rejects=8`，随后降到 0；不是 pipeline 卡死。
Transport/pipeline evidence: `push_flow_errors=0`、`appsink_dropped=0`、`pixel_create_fail=0`、`format_fail=0`、`sample_fail=0`；`enqueue` 持续跟随输入。
Disconnect behavior: 通过。`Stopping RAOP Server` 后 `Open connections: 0`，连接 socket 正常关闭，无 ERROR/FATAL。
Rotation behavior: 通过本次日志证据。会话中观测到 `498x1080 → 1920x884 → 498x1080`，每次切换后继续接收和入队；完整视觉确认由用户现场完成。
Douyin capture result: 未执行
Log path: `~/Library/Logs/FrameRelay/FrameRelay.log`
Files changed: docs/STATUS.md; docs/TESTLOG.md
Next exact action: 继续抖音窗口捕获、横竖屏长时间切换、30/60 分钟稳定性和最终 DMG 独立运行验收。
```

## 2026-09-14 — Phase 4 手机音频 → Mac 初版接入与本地验证

```text
Date: 2026-09-14（Asia/Shanghai）
Mac: MacBook Pro 2021, Apple M1 Pro, arm64
macOS: 26.5（build 25F71）
iPhone: 未连接；真实音频回归待执行
iOS: 26.5（待真实音频回归）
Network: 未进行本次 iPhone 音频连接
FrameRelay build: dist/FrameRelay.app 0.1.0；生产 options 改为 `-p 47000 -nh -as osxaudiosink -vs avlayer -fps 60 -reset 8 -nofreeze -nohold -s 1920x1080`
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: `Scripts/build-core.sh`; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`; `Scripts/build-app.sh`; `Scripts/bundle-gstreamer.sh`; `Scripts/verify-bundle.sh`; `env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$HOME" STARTUP_WAIT_SECONDS=3 ./Scripts/restart-loop.sh 1`
Result: 通过本地验证。Swift Testing 13/13；core/standalone arm64 构建；App 签名、GStreamer bundle、递归非系统依赖和静态验证均通过；clean-environment restart loop 1/1 通过。无设备启动日志不再出现 `audio_disabled`。
Audio implementation: 移除 `-a`；显式选择 `osxaudiosink`；bundle 增加 `libgstaudioconvert.dylib`、`libgstaudioresample.dylib`、`libgstlevel.dylib`、`libgstvolume.dylib`、`libgstosxaudio.dylib`；AAC/ALAC 解码继续使用 bundled `libgstlibav.dylib`。
Observed audio: 未连接真实 iPhone，尚未宣称手机声音已实际输出到 Mac。
Observed video: 未连接真实 iPhone；配置仍请求最高 1920x1080 / 60 fps。
Disconnect behavior: 本地启动/退出 1/1 通过；真实设备断连待测。
Rotation behavior: 未执行本阶段真实设备旋转测试。
Douyin capture result: 未执行；先验证手机声音 → Mac。
Log path: `~/Library/Logs/FrameRelay/FrameRelay.log`
Files changed: Sources/FrameRelayApp/Models.swift; Tests/FrameRelayTests/FrameRelayTests.swift; Scripts/bundle-gstreamer.sh; docs/PLAN.md; docs/ARCHITECTURE.md; docs/DECISIONS.md; docs/STATUS.md; docs/TESTLOG.md
Next exact action: 用新 App 连接真实 iPhone，播放有声音内容，确认 Mac 默认输出设备有声，并记录 `start audio connection`、audio codec、GStreamer audio pipeline 和 audio bus error。
App SHA-256: 9286084aa5912aee367f3c3c6d1dee46191b51cf7dc7c101d78c56ba48d17c68
Core SHA-256: 2e91ac82935673cf09871b9aabae7833b011bba14c9b527bb7179674edef51a2
DMG SHA-256: 954cf8a6546c677119213b3414bbcde57d5638c5b0de27bce85cdc4b6cf2f430
```

## 2026-09-17 — Phase 3G AVLayer 持续拒帧自恢复与重启可观测性本地验证

```text
Date: 2026-09-17（Asia/Shanghai）
Mac: MacBook Pro 2021, Apple M1 Pro, arm64
macOS: 26.5（主机工具链）
iPhone: 未连接；真实设备回归待执行
iOS: 26.5（真实设备回归待执行）
Network: 未进行本次 iPhone 连接
FrameRelay build: dist/FrameRelay.app 0.1.0；patches/0001–0010
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: `Scripts/bootstrap.sh`; `Scripts/build-core.sh`; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`; `Scripts/build-app.sh`; `Scripts/bundle-gstreamer.sh`; `Scripts/verify-bundle.sh`; `Scripts/package-dmg.sh`; `env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$HOME" STARTUP_WAIT_SECONDS=2 Scripts/restart-loop.sh 20`; `git diff --check`; 0010 reverse-check。
Result: 全部通过。core/standalone arm64 编译成功；Swift Testing 14/14；App、GStreamer bundle、arm64、ad-hoc signature、静态依赖校验和 DMG 全部通过；clean-environment restart loop 20/20；0010 reverse-check 通过。编译保留 macOS 26 AVSampleBufferDisplayLayer 已知弃用警告。
Fix evidence: live AVLayer 连续 3 秒 `readyForMoreMediaData == false` 时执行 `flushAndRemoveImage` 并 arm 单枚 seed，最多两次；仍拒收时写 `FrameRelay avlayer watchdog: action=restart reason=ready-stuck`。Swift 解析为 `.displayStalled`，经既有固定重启退避调度；手动/自动 restart 写入 reason 和 lifecycle generation。
Observed latency: 未连接设备；真实回归需记录 watchdog flush 到恢复入队的时间，以及自动重启是否只出现一个 generation。
Observed resolution: 未连接设备；正式路径仍请求最高 1920x1080。
Observed FPS: 未连接设备；正式路径仍为 `-fps 60`。
Disconnect behavior: clean-environment 启动/退出 20/20 通过；真实断连待测。
Rotation behavior: 未执行本阶段真实设备旋转测试。
Douyin capture result: 未执行；真实设备回归待执行。
Log path: `~/Library/Logs/FrameRelay/FrameRelay.log`
Files changed: patches/0010-uxplay-avlayer-ready-watchdog.patch; third_party/uxplay/renderers/avsample_sink.h; third_party/uxplay/renderers/avsample_sink.m; third_party/uxplay/renderers/video_renderer.c; Sources/FrameRelayApp/AirPlayEngine.swift; Sources/FrameRelayApp/AppController.swift; Sources/FrameRelayApp/EngineLogParser.swift; Sources/FrameRelayApp/Models.swift; Tests/FrameRelayTests/FrameRelayTests.swift; Scripts/build-core.sh; docs/PLAN.md; docs/DECISIONS.md; docs/ARCHITECTURE.md; docs/UPSTREAM.md; docs/STATUS.md; docs/TESTLOG.md
App SHA-256: 026d7c019c73ed8d8282654d5debcd332128502235e867ab75a3cac6fdffb893
Core SHA-256: 9f66fd008f4c342a5760b53f93c0b3d6a8f16c9827738aa3df05844a2e2de61c
DMG SHA-256: e8c405db4074b316ef308a93ada7c99b257d866ddc811c820169d03f7452dbde
Real-device result: PENDING_REAL_DEVICE；本地构建和静态验证不能替代 iPhone 15 Pro Max / iOS 26.5 画面恢复及 Douyin Window Capture 验收。
Next exact action: 启动新 App，连接真实 iPhone，观察 `ready_watchdog_flushes`、`ready_watchdog_escalations` 和 watchdog 后的 lifecycle generation；再完成音频连续性与 Douyin 窗口捕获回归。
```

## 2026-09-17 — Phase 3H 正常断连后视频 renderer 重建本地验证

```text
Date: 2026-09-17（Asia/Shanghai）
Mac: MacBook Pro 2021, Apple M1 Pro, arm64
macOS: 26.5（主机工具链）
iPhone: 未连接；真实设备断连重连回归待执行
iOS: 26.5（真实设备回归待执行）
Network: 未进行本次 iPhone 连接
FrameRelay build: dist/FrameRelay.app 0.1.0；patches/0001–0011
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: `Scripts/bootstrap.sh`; `Scripts/build-core.sh`; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`; `Scripts/build-app.sh`; `Scripts/bundle-gstreamer.sh`; `Scripts/verify-bundle.sh`; `Scripts/package-dmg.sh`; `env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$HOME" STARTUP_WAIT_SECONDS=2 Scripts/restart-loop.sh 20`; `git diff --check`; UxPlay 0011 reverse-check。
Result: 全部通过。core/standalone arm64 编译成功；Swift Testing 14/14；App、GStreamer bundle、arm64、ad-hoc signature、静态依赖校验和 DMG 全部通过；clean-environment restart loop 20/20；0011 reverse-check、源码和 patch diff check 通过。编译保留 macOS 26 AVSampleBufferDisplayLayer 已知弃用警告。
Fix evidence: 在 `conn_destroy()` 检测到最后一个 AirPlay 客户端关闭后，停止旧视频 renderer，设置 `full_video_reset`、`relaunch_video` 和 `reset_loop`，由既有 main loop 负责重建 renderer；HTTP server 不在 HTTP worker 回调中停止或 join。新增日志标记为 `FrameRelay video lifecycle: action=disconnect-reset reason=last-client-closed`。
Expected reconnect behavior: Swift 仍会清理断连时已脱离 host view 的旧 layer；下一次连接应经过 fresh renderer 和新的 `FrameRelay avlayer format transition`，避免新帧继续进入旧 layer 导致黑屏。
Observed latency: 未连接设备；真实回归需记录手动断开到下一次首帧入队的时间。
Observed resolution: 未连接设备；正式路径仍请求最高 1920x1080。
Observed FPS: 未连接设备；正式路径仍为 `-fps 60`。
Disconnect behavior: clean-environment 启动/退出 20/20 通过；真实设备手动断开后再次投屏待测。
Rotation behavior: 未执行本阶段真实设备旋转测试。
Douyin capture result: 未执行；真实设备回归待执行。
Log path: `~/Library/Logs/FrameRelay/FrameRelay.log`
Files changed: patches/0011-uxplay-rebuild-video-on-disconnect.patch; third_party/uxplay/uxplay.cpp; Scripts/build-core.sh; docs/ARCHITECTURE.md; docs/DECISIONS.md; docs/UPSTREAM.md; docs/STATUS.md; docs/TESTLOG.md
App SHA-256: 1b0e011cfc8f11aa95336b421e47c2ad2bd28ccf88aa6e9dd5fe01472b3a41ee
Core SHA-256: 293987f02da3139dc1b60b1666db94871085b9ea011b88fadca10b6e6f05f36b
DMG SHA-256: 328f5ce27e7f95cc8f51b3a08546035be4f02f661b4f003977ed094324f24a15
Real-device result: PENDING_REAL_DEVICE；本地构建和静态验证不能替代 iPhone 15 Pro Max / iOS 26.5 的手动断开、再次选择 FrameRelay、视频画面恢复及 Douyin Window Capture 验收。
Next exact action: 启动新 App，连接真实 iPhone，手动断开后不退出 App，立即再次选择 FrameRelay；确认 `disconnect-reset`、新的 AVLayer format transition 和连续入队，至少重复 3 次。
```

## 2026-09-18 — README、`.gitignore` 和提交前验证

```text
Date: 2026-09-18（Asia/Shanghai）
Mac: MacBook Pro 2021, Apple M1 Pro, arm64（主机工具链）
macOS: 26.5（主机工具链）
iPhone: 未连接；真实设备回归待执行
iOS: 26.5（真实设备回归待执行）
Network: 未进行本次 iPhone 连接
FrameRelay build: 文档和忽略规则整理；未重新生成发布包
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Test: `git diff --check`; 检查 README 正式 `-as osxaudiosink` 参数和文档链接；`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Result: 通过。README 已与当前音频、固定端口、诊断 profile、构建产物和真实设备验收边界对齐；`.gitignore` 覆盖 SwiftPM/Xcode、build/dist、日志和本地运行状态；Swift Testing 14/14；本次文档改动的 diff check 通过。全量 staged diff 另报告已有 UxPlay patch 文本的尾随空格/空行警告，未修改补丁内容。
Observed latency: 未连接设备；未测量
Observed resolution: 未连接设备；正式路径仍请求最高 1920x1080
Observed FPS: 未连接设备；正式路径仍为 `-fps 60`
Disconnect behavior: 未执行真实设备断连重连；沿用 Phase 3H 的 pending 状态
Rotation behavior: 未执行本阶段真实设备旋转测试
Douyin capture result: 未执行；真实 Window Capture 待现场验证
Log path: `~/Library/Logs/FrameRelay/FrameRelay.log`
Files changed: README.md; .gitignore; docs/STATUS.md; docs/TESTLOG.md
Tests not rerun: 固定 core/App/GStreamer/DMG 完整构建顺序和 clean-environment restart loop；上一条 Phase 3H 记录仍保留对应本地结果，本条不重复宣称。
Next exact action: 基于已读取的 `origin/main` 提交当前项目内容并推送到 `https://github.com/dkZzzz/FrameRelay`，随后核对远程分支和工作区状态。
```

## 2026-09-18 — 项目首个提交和远程推送

```text
Date: 2026-09-18（Asia/Shanghai）
Repository: https://github.com/dkZzzz/FrameRelay
Remote baseline: 14aa52b（仅含远程初始 MIT LICENSE）
Commit: 59a52bacb3d51fd75156cf38fd1ff2a3e191f90e — chore: initialize FrameRelay receiver
Push: `git push -u origin main` 成功；远程 `main` 与本地 HEAD 一致
Files: README.md、.gitignore、FrameRelay Swift/C bridge、构建脚本、文档、许可证、patches 和 pinned UxPlay gitlink
Result: 项目内容已推送到远程 `main`。根仓库没有未提交的普通文件；`third_party/uxplay` 保持 pinned commit `587111368390479b7f65feb881c9257c02e508b5`，其工作树保留由构建脚本应用的文档补丁，未把这些子模块内改动提交到根仓库。
Checks: `git status --short --branch`、`git log --oneline --decorate --max-count=3`、`git rev-parse HEAD`、`git rev-parse origin/main`、`git ls-remote --heads origin main`；本地和远程 SHA 均为 `59a52bacb3d51fd75156cf38fd1ff2a3e191f90e`。
Real-device result: PENDING_REAL_DEVICE；提交和推送不代表 iPhone 15 Pro Max / iOS 26.5 或 Douyin Window Capture 通过。
Next exact action: 启动新 App，完成真实断连重连、手机音频连续性和 Douyin Window Capture 回归，并把观察结果写入本日志。
```
