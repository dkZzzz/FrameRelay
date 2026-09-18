Current phase: Phase 3H 正常断连后视频 renderer 重建；README/.gitignore 文档整理和提交前验证完成，等待提交推送
Current status: 已应用并接入 `patches/0011-uxplay-rebuild-video-on-disconnect.patch`。最后一个 AirPlay 客户端正常断开时，运行中的 UxPlay core 会先停止旧视频 renderer，再设置既有 main-loop 重建标志；HTTP/Bonjour 服务保持运行，下一次投屏使用全新的 AVSampleBufferDisplayLayer。这样 Swift 清理旧 host layer 后，重新选择 FrameRelay 不再把视频帧送入已脱离窗口的旧 layer。没有重启整个 App，也没有从 HTTP worker 回调中停止/加入 HTTP server。
Last completed action: 完成 README 和 `.gitignore` 整理；检查文档路径和 README 正式音频参数；运行 `git diff --check` 与 Swift Testing 14/14。此次没有把本地结果当作真实设备通过。
Last command: `git diff --check`; `rg --pcre2 '(^|\\s)-a(\\s|$)' README.md`; `rg --fixed-strings '-as osxaudiosink' README.md`; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Last command result: 文档范围全部通过。README 未发现过时的独立 `-a` 参数；固定 `-as osxaudiosink`、文档链接目标和必需文档路径存在；Swift Testing 14/14；README、`.gitignore`、`docs/STATUS.md` 和 `docs/TESTLOG.md` 的 `git diff --check` 通过。全量 staged diff 另有上游 patch 文本的尾随空格警告，未修改这些补丁内容。
Files changed: README.md; .gitignore; docs/STATUS.md; docs/TESTLOG.md
Tests passed: README/.gitignore 文档检查；README、`.gitignore`、`docs/STATUS.md` 和 `docs/TESTLOG.md` 的 `git diff --check`；Swift Testing 14/14。
Warnings: 全量 staged diff 在 `patches/0002`、`0003`、`0004`、`0005`、`0006`、`0007`、`0009`、`0010` 中报告补丁文本尾随空格/空行；这些文件不是本次 README/.gitignore 修改目标，保持原样以避免改变上游补丁语义。
Tests not rerun: 固定 core/App/GStreamer/DMG 完整构建顺序和 clean-environment restart loop；沿用上一条 Phase 3H 记录，未新增其通过声明。
Tests pending: 真实 iPhone 15 Pro Max / iOS 26.5 的“手动断开后重新选择投屏”黑屏回归、手机播放/暂停、锁屏唤醒、至少 30 分钟音频连续性和完整 Douyin Window Capture；尚未把本地结果当作真实设备通过。
Known blocker: 没有新的本地构建阻塞；真实设备断连重连仍需现场验证 `disconnect-reset` 后是否出现新的 AVLayer format transition 和视频画面。v0.1 仍未完成。
Next exact action: 基于已读取的 `origin/main`（远程初始提交仅含 MIT `LICENSE`）检查最终暂存差异，创建当前项目提交并推送 `main`；随后核对远程分支和工作区状态。
Log path: ~/Library/Logs/FrameRelay/FrameRelay.log
App SHA-256: 1b0e011cfc8f11aa95336b421e47c2ad2bd28ccf88aa6e9dd5fe01472b3a41ee
Core SHA-256: 293987f02da3139dc1b60b1666db94871085b9ea011b88fadca10b6e6f05f36b
DMG SHA-256: 328f5ce27e7f95cc8f51b3a08546035be4f02f661b4f003977ed094324f24a15
