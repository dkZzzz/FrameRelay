Current phase: Phase 3H 正常断连后视频 renderer 重建；README/.gitignore 文档整理、项目提交和远程推送完成，等待真实设备回归
Current status: 已应用并接入 `patches/0011-uxplay-rebuild-video-on-disconnect.patch`。最后一个 AirPlay 客户端正常断开时，运行中的 UxPlay core 会先停止旧视频 renderer，再设置既有 main-loop 重建标志；HTTP/Bonjour 服务保持运行，下一次投屏使用全新的 AVSampleBufferDisplayLayer。这样 Swift 清理旧 host layer 后，重新选择 FrameRelay 不再把视频帧送入已脱离窗口的旧 layer。没有重启整个 App，也没有从 HTTP worker 回调中停止/加入 HTTP server。
Last completed action: 完成 README 和 `.gitignore` 整理；运行文档检查和 Swift Testing 14/14；以 `59a52ba` 提交当前项目并推送到 `origin/main`；远程指针已核对一致。
Last command: `git push -u origin main`; `git status --short --branch`; `git log --oneline --decorate --max-count=3`; `git ls-remote --heads origin main`
Last command result: 推送成功，远程 `main` 已指向 `59a52bacb3d51fd75156cf38fd1ff2a3e191f90e`，与本地 `HEAD` 一致。根目录仅保留 `third_party/uxplay` 子模块的预期补丁应用状态，未把子模块工作树改动误提交。
Files changed: README.md; .gitignore; docs/STATUS.md; docs/TESTLOG.md; project implementation files included in commit `59a52ba`
Tests passed: README/.gitignore 文档检查；README、`.gitignore`、`docs/STATUS.md` 和 `docs/TESTLOG.md` 的 `git diff --check`；Swift Testing 14/14；上一条 Phase 3H 记录的 core/App/GStreamer/DMG、静态 bundle、restart loop 20/20 和 0011 reverse-check。
Warnings: 全量 staged diff 在 `patches/0002`、`0003`、`0004`、`0005`、`0006`、`0007`、`0009`、`0010` 中报告补丁文本尾随空格/空行；这些文件不是本次 README/.gitignore 修改目标，保持原样以避免改变上游补丁语义。`third_party/uxplay` 当前由构建脚本应用了文档列出的补丁，根仓库状态因此显示子模块 worktree modified。
Tests pending: 真实 iPhone 15 Pro Max / iOS 26.5 的“手动断开后重新选择投屏”黑屏回归、手机播放/暂停、锁屏唤醒、至少 30 分钟音频连续性和完整 Douyin Window Capture；尚未把本地结果当作真实设备通过。
Known blocker: 没有新的本地构建阻塞；真实设备断连重连仍需现场验证 `disconnect-reset` 后是否出现新的 AVLayer format transition 和视频画面。v0.1 仍未完成。
Next exact action: 启动 `/Users/danko/workspace/FrameRelay/dist/FrameRelay.app`，用真实 iPhone 15 Pro Max / iOS 26.5 投屏，手动断开后不退出 App，立即再次选择 FrameRelay；检查 `disconnect-reset`、新的 AVLayer format transition 和连续入队，至少重复 3 次，然后完成音频连续性和 Douyin Window Capture 回归。
Log path: ~/Library/Logs/FrameRelay/FrameRelay.log
App SHA-256: 1b0e011cfc8f11aa95336b421e47c2ad2bd28ccf88aa6e9dd5fe01472b3a41ee
Core SHA-256: 293987f02da3139dc1b60b1666db94871085b9ea011b88fadca10b6e6f05f36b
DMG SHA-256: 328f5ce27e7f95cc8f51b3a08546035be4f02f661b4f003977ed094324f24a15
