# FrameRelay 使用和故障处理

## 1. 启动

1. 双击 `FrameRelay.app`。从 DMG 第一次打开 ad-hoc App 时，使用“右键 → 打开”；
   不做 Developer ID/notarization。
2. 如果 macOS 弹出本地网络权限提示，选择允许。
3. FrameRelay 启动后会作为普通 macOS App 出现在 Dock、应用切换器和台前调度中，
   同时在菜单栏显示波纹图标。窗口自动出现，菜单栏状态应为“等待 iPhone”。窗口
   带原生标题栏和左上角关闭按钮，可移动、可缩放，不会接管整个桌面；可以用
   `⌘W` 关闭窗口，用应用菜单或 `⌘Q` 退出 App。
4. 不要打开 QuickTime Player、macOS `iPhone Mirroring` 或 OBS 作为中转。FrameRelay
   接收的是 iPhone 控制中心的“屏幕镜像”，不是 Mac 控制 iPhone 的功能。

## 2. iPhone 打开屏幕镜像

1. 确认 iPhone 15 Pro Max 与 Mac 位于同一个局域网。
2. 在 iPhone 右上角向下滑打开控制中心。
3. 点击“屏幕镜像”。
4. 在设备列表选择 `FrameRelay`。
5. 首次连接出现确认时完成确认。
6. 用手指继续操作 iPhone 游戏；Mac 不会获得 iPhone 控制权。
7. FrameRelay 菜单栏状态从“等待 iPhone”变为“正在连接”，收到第一帧后显示
   “正在接收 宽×高”。

收到第一帧或手机横竖屏切换时，FrameRelay 会按协商到的宽高比自动调整窗口内容区域。
窗口仍可手动缩放，但会保持视频比例；如果窗口在台前调度中，使用原生窗口缩略图，
不会把整个 Mac 桌面作为视频源。

FrameRelay v0.1 请求最高 1920×1080/60 fps，但手机实际发送的分辨率和帧率由
   iPhone/AirPlay 协商决定；如果实际为 30 fps，按实际结果记录，不把请求值当作
   强制值。`-fps 60` 不是把 ProMotion 的 120 Hz 强行截成 60 Hz 的开关；性能问题
   需要结合日志里的 `avlayer performance`（pulled/enqueued/dropped/output_fps）和
   实际延迟判断。

## 3. 抖音直播伴侣配置

1. 先让 FrameRelay 窗口已经显示手机画面。
2. 打开抖音直播伴侣，在视频来源中添加“窗口捕获”。
3. 选择 `FrameRelay` 视频窗口，不选择整个桌面。
4. 拖动/缩放 FrameRelay 窗口验证抖音仍只看到该窗口内容。
5. 在音频/麦克风设置中选择 Mac 的实际麦克风，并在直播伴侣中测试音量。
6. 输出设置按直播需要选择 1080p；不要把 FrameRelay 的窗口标题当作音频来源。

FrameRelay v0.1 使用 `-a`，手机媒体音频不会由 FrameRelay 播放。FrameRelay 不申请
麦克风权限，也不接管 Mac 麦克风；主播声音必须由抖音直播伴侣直接读取 Mac 麦克风。

## 4. 本地网络权限

FrameRelay 通过 Bonjour/mDNS 发布 `_airplay._tcp` 和 `_raop._tcp` 服务。首次运行
需要允许“本地网络”。如果之前点过拒绝：

1. 打开“系统设置 → 隐私与安全性 → 本地网络”。
2. 找到 FrameRelay 并打开权限。
3. 完全退出 FrameRelay 后重新打开。

不要授予屏幕录制、摄像头、Apple Events 或麦克风权限来解决发现问题；v0.1 不需要
这些权限。

## 5. macOS 防火墙

如果“屏幕镜像”列表没有 FrameRelay：

1. 打开“系统设置 → 网络 → 防火墙 → 选项”。
2. 允许 `FrameRelay.app` 接受传入连接。
3. 若当前是“阻止所有传入连接”，先关闭该模式进行测试。
4. 确认路由器没有开启无线客户端隔离、访客网络隔离或 VLAN 隔离。
5. 确认 Mac 和 iPhone 不在两个不同 SSID/子网。

FrameRelay 固定使用自定义 Legacy AirPlay 端口组 `47000–47002`：TCP 和 UDP 都会使用
`47000`、`47001`、`47002`。UxPlay 会把实际 AirPlay/RAOP 服务端口通过 Bonjour 广播，
iPhone 会连接广播出来的端点。网络设备不能阻断 Bonjour 或这组 AirPlay 连接端口。

### 5.1 与 macOS 自带 AirPlay Receiver 共存

FrameRelay 使用独立的 `47000–47002` 端口组，所以 macOS 自带的“AirPlay 接收器”可以
保持开启，不需要为了运行 FrameRelay 关闭它。正常启动后，在菜单“打开日志目录”查看日志，
应看到类似以下内容：

```text
using network ports UDP 47000 47001 47002 TCP 47000 47001 47002
Initialized server socket(s)
```

如果出现 `Error initialising socket 48` 或 `Address already in use`：

1. 先确认没有其他程序占用 TCP/UDP `47000–47002`。
2. 确认 macOS 防火墙允许 FrameRelay 接收传入连接；不要只允许 Bonjour 而阻断 AirPlay
   数据连接。
3. 关闭系统“AirPlay 接收器”只用于临时诊断端口或系统服务问题，不是 FrameRelay 的常规
   前置条件。
4. 使用菜单“复制诊断信息”保存当前状态、网络接口和最近错误日志；不要随意改动固定端口
   或设备名称。

这不是把 macOS `iPhone Mirroring` 当作视频输入；FrameRelay 仍然只接收 iPhone 控制中心
的“屏幕镜像”。

## 6. FrameRelay 不出现在 iPhone 列表

按以下顺序检查：

1. FrameRelay 是否正在运行，菜单栏是否显示“等待 iPhone”。
2. 设备名称是否确实是 `FrameRelay`。
3. 本地网络权限是否打开。
4. macOS 防火墙是否允许传入连接。
5. iPhone 和 Mac 是否在同一非隔离局域网。
6. 是否有另一个程序占用了 UxPlay 固定端口；退出其他 UxPlay/接收器。
7. 在终端观察 Bonjour：

   ```bash
   dns-sd -B _airplay._tcp
   dns-sd -B _raop._tcp
   ```

8. 退出并重新打开 FrameRelay，再重新打开 iPhone 控制中心。
9. 从菜单栏选择“复制诊断信息”，将诊断和日志目录中的
   `~/Library/Logs/FrameRelay/FrameRelay.log` 一并保存。

如果真实 iOS 26.5 设备仍然不能建立连接，记录为
`BLOCKED_PROTOCOL_IOS_26_5`，包含 iPhone 型号、iOS、core SHA、完整日志、Bonjour
结果、连接阶段和最后成功事件；不要改用 macOS iPhone Mirroring、ReplayKit、OBS
或其他 AirPlay 引擎。

## 7. 断连、冻结画面和重新连接

- 手机主动停止镜像：FrameRelay 保持服务运行，清空旧画面并回到“等待 iPhone”。
- 重新选择 `FrameRelay`：应重新进入“正在连接”并恢复画面。
- 手机锁屏时 AirPlay 会发送视频 pause marker；FrameRelay 会清空当前画面并 arm 一枚
  恢复 seed。解锁或点亮后收到新的视频帧时，FrameRelay 使用没有 PTS 的
  `DisplayImmediately` sample 尽快显示，不让锁屏前的 sender timestamp 决定显示层的
  时间轴。该首帧允许一次性通过短暂的 AVLayer not-ready 状态，普通帧仍受有限队列和
  ready gate 限制；不能保证手机锁屏期间每一段动画都被发送，但不会因为旧时间轴停在
  第一枚亮屏/解锁帧。
- 如果锁屏/解锁期间手机先发送竖屏解锁流、再回到横屏游戏流，FrameRelay 会先更新
  `videoflip` 方向，再清掉 AVLayer 中旧方向的当前图像和排队样本，并让下一枚新格式
  immediate 视频帧唤醒显示层；当前 live AVLayer 没有需要重置的媒体时钟。诊断模式可用
  `FrameRelay avlayer format transition`、`FrameRelay diagnostic sample: output=WxH`
  和 `format_flushes` 核对这条路径。
- 如果网络心跳连续八秒丢失：UxPlay 按 `-reset 8` 重置连接，`-nofreeze` 清除旧帧。
- 如果核心 worker 异常退出或连接后 12 秒没有第一帧：App 按 0.5 秒、1 秒、2 秒
  固定退避自动重启；60 秒内三次失败后显示“启动失败”，不会无限重启。
- 用户点击“停止接收”或关闭窗口后不自动重启。需要恢复时选择“启动接收”或
  “重新启动”；“重新启动”会清除失败计数。
- 如果状态持续“正在连接”，不要反复创建窗口；先等待固定超时，再查看菜单栏
  状态和日志。

关闭窗口的 stop 是异步执行的：点击左上角关闭后，先等待核心 worker 停止，再清理
视频层并完成真正的窗口关闭。不要强制杀掉 App 来替代正常的关闭或“停止接收”，
除非正在处理无法响应的系统级异常。

## 8. 日志和诊断

日志文件：

```text
~/Library/Logs/FrameRelay/FrameRelay.log
```

菜单“复制诊断信息”包含：FrameRelay 版本、macOS、Mac 芯片、arm64、固定 core
SHA、GStreamer 版本、当前状态、App bundle 路径、core 路径、网络接口、最近 50 条
错误。日志达到 5 MiB 时滚动保留 `.1` 和 `.2`。

不要打开 debug flood；逐帧日志会增加延迟并干扰直播。提交问题时至少附上：

- 复制的诊断信息；
- `FrameRelay.log`；
- iPhone 型号和 iOS；
- Mac/macOS；
- 是否同一局域网、是否有客户端隔离；
- 发生断连前的菜单栏状态。

### 8.1 帧率根因诊断

当窗口切换正常但滑动仍然卡顿时，使用项目提供的两个临时诊断配置。它们不会改变
正式双击启动的配置，也不需要关闭 macOS 自带的 AirPlay 接收器。

请严格按以下顺序操作：

1. 先退出当前运行的 FrameRelay；不要同时运行两个 FrameRelay 实例。
2. 保持 Mac 与 iPhone 在当前同一个 Wi-Fi 网络，不切换路由器、VPN 或热点。
3. 打开“终端”，粘贴并运行：

   ```bash
   /Users/danko/workspace/FrameRelay/dist/FrameRelay.app/Contents/MacOS/FrameRelay --diagnostic-1080p
   ```

4. 等待窗口状态显示“等待 iPhone”，在 iPhone 控制中心打开“屏幕镜像”，选择
   `FrameRelay`。
5. 连接成功后先等待 10 秒，再在同一个游戏画面中连续滑动或拖动约 20 秒；期间
   不旋转屏幕、不锁屏、不停止镜像，也不要修改系统设置。记住这次测试的大致开始
   时间。
6. 继续保持连接约 60 秒，然后在 iPhone 停止屏幕镜像，按 `⌘Q` 退出诊断实例。
7. 再次打开“终端”，运行 720p 对照：

   ```bash
   /Users/danko/workspace/FrameRelay/dist/FrameRelay.app/Contents/MacOS/FrameRelay --diagnostic-720p
   ```

8. 重复完全相同的连接、等待、滑动和 60 秒观察步骤。不要在两个测试之间改变
   Wi-Fi、游戏、抖音或系统 AirPlay Receiver 设置。
9. 测试完成后退出诊断实例；日常使用直接双击 `FrameRelay.app`，不要带诊断参数。

### 当前首轮分段诊断（1080p / 默认同步）

新诊断版的首轮采样固定使用 1080p，先把无线输入、解码、队列、PixelBuffer 拷贝、
SampleBuffer 入队和 pause-resume 的分段数据采齐。当前自定义 live AVLayer 使用
arrival-driven 的 immediate display；本轮不需要用 no-sync profile 重新区分 AVLayer
时间戳调度：

1. 先退出已经运行的 FrameRelay 或上一轮诊断实例。
2. 保持 Mac 与 iPhone 在同一个 Wi-Fi、同一个 AP；不要切换 VPN、热点或系统设置。
3. 在“终端”中运行：

   ```bash
   /Users/danko/workspace/FrameRelay/dist/FrameRelay.app/Contents/MacOS/FrameRelay --diagnostic-1080p
   ```

4. 在 iPhone 控制中心打开“屏幕镜像”，选择 `FrameRelay`。
5. 连接后先等待 10 秒，再在同一个游戏画面中连续滑动或拖动约 20 秒；期间不要
   旋转屏幕、锁屏、停止镜像或修改设置。
6. 继续连接约 60 秒，记录本次测试的大致北京时间开始/结束时间，然后在 iPhone
   停止镜像并按 `⌘Q` 退出诊断实例。
7. 本轮不需要重新测试 720p 或 `--diagnostic-1080p-nosync`；维护时会把这次完整分段
   日志与此前的实测记录对齐分析。

`--diagnostic-1080p-nosync` 仍然保留作兼容性对照：它与
`--diagnostic-1080p` 的命令行差异是增加 `-vsync no`，两者都请求最高 1920×1080、60 FPS，
均使用 `avlayer`、固定 47000 端口和 `-FPSdata`。在 0007 之后，自定义 live AVLayer
无论该 profile 如何设置都不附加 sender PTS、不使用 `controlTimebase`；因此这个 profile
不能再用来证明 AVLayer 时间戳调度差异，除非专门排查通用 GStreamer 分支。它不改变
普通双击启动的正式配置。

诊断模式会在同一个日志文件中增加以下几类信息：

- `-FPSdata` 产生的 iPhone/AirPlay 客户端每秒性能报告，用来确认手机实际发送的
  帧率和客户端自身观察到的帧率；
- FrameRelay 已有的 `avlayer performance`，包括 `pulled`、`enqueued`、`dropped`
  和 `output_fps`，用来对比接收、解码和送入显示层的帧率。
- `FrameRelay diagnostic transport`，用来观察 AirPlay 输入包、`video_process` 回调
  和最大到达间隔；
- `FrameRelay diagnostic decoder` 与 `FrameRelay diagnostic caps`，用来确认实际
  GStreamer 解码器和协商出的 raw video 格式；
- `FrameRelay diagnostic pipeline` 与 `FrameRelay diagnostic avlayer`，用来定位
  appsrc、queue、appsink、PixelBuffer/NV12 拷贝、sample 创建和显示层入队的耗时；
- `FrameRelay diagnostic marker`，用来测量锁屏/解锁 pause-resume marker 到首帧恢复的
  路径；`FrameRelay diagnostic pts` 只用于仍采用 timestamped sink 的通用分支，当前
  live AVLayer 不依赖它；
- `FrameRelay diagnostic host` 用来确认每次 `videoStarted` 的几何是否被 AppKit 窗口
  实际应用，以及应用后的窗口内容尺寸。

这些诊断行每秒汇总一次，不是实际显示器 vsync；`output_fps` 也不能单独当作真实
显示 FPS，它只统计送入 AVLayer 的 sample。测试时不要打开 debug flood，不要把
`-fps 60` 改成 `-fps 120`，并同时记录 `encoderCurrentFPS`。当前版本若锁屏/解锁后
仍静止，重点对照“enqueue 是否持续增长”和“画面是否变化”，不要只看 `output_fps`。

日志仍然在 `~/Library/Logs/FrameRelay/FrameRelay.log`。测试期间不需要手动复制或
清空日志；只需告诉维护者本次 1080p 诊断的开始/结束北京时间，即可从同一份日志中
分段分析。若后续安排 720p 或 no-sync 对照，也只需额外提供对应区间的开始/结束时间。

## 9. 开发期间立即可用的硬件备援

如果软件接收器尚未通过真实 iOS 26.5 验收，马上开播使用硬件采集链路：

```text
iPhone 15 Pro Max USB-C
    -> USB-C 转 HDMI/DisplayPort 适配器
    -> HDMI
    -> 支持 UVC、1080p60、USB 3.0 的采集卡
    -> Mac
    -> 抖音直播伴侣“采集卡”来源
```

固定规则：

- iPhone 不连接 AirPods 或其他 Bluetooth 音频设备。
- iPhone 不处于静音状态。
- 抖音视频来源选择采集卡，不选择 QuickTime 窗口。
- 手机媒体音频通过 HDMI 进入采集卡；主播声音仍选择 Mac 麦克风。
- 不使用 QuickTime Player 中转，不把硬件备援混入 FrameRelay 软件实现。

硬件链路是绕过 1000 粉丝 iOS 投屏限制的立即方案，不依赖 AirPlay Legacy Protocol；
它与 FrameRelay 的软件架构相互独立。
