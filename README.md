# SingFor10 — iOS 唱歌 10 分钟整人 App

一个零依赖的 iOS 整人应用：启动后持续"唱歌"（实时合成旋律，无需音频文件），
倒计时满 10 分钟才自动停止。期间静音键无效、音量被调低会自动拉满、切到后台继续唱。

---

## 一、项目结构

```
SingFor10/
├── SingFor10.xcodeproj/
│   ├── project.pbxproj          # Xcode 工程文件
│   └── xcshareddata/xcschemes/
│       └── SingFor10.xcscheme   # 共享 Scheme，供命令行/CI 归档
├── SingFor10/
│   ├── AppDelegate.swift        # 应用入口 + Scene 配置
│   ├── SceneDelegate.swift      # 场景生命周期，创建根控制器
│   ├── ViewController.swift     # 倒计时 UI、进度条、防误触退出按钮
│   ├── AudioEngine.swift        # 音频合成引擎（AVAudioSourceNode）
│   ├── VolumeGuard.swift        # 音量守卫（KVO + MPVolumeView）
│   ├── Info.plist               # 含 UIBackgroundModes = audio
│   └── Assets.xcassets/         # 图标资源
├── .github/workflows/
│   └── build-ipa.yml            # GitHub Actions 云端构建 IPA
├── scripts/
│   └── build-ipa.sh             # Mac 本地一键构建 IPA
├── exportOptions.plist          # 导出配置（未签名）
└── README.md
```

---

## 二、获取 IPA 安装包（三条路径）

> **编译环境硬约束**：iOS 应用的编译产物只能由 Apple 的 `xcodebuild` 工具链生成，
> 该工具链仅运行在 macOS 上。Windows / Linux 本机无法直接编译出 IPA。
> 因此下面提供「云端构建」（无需 Mac）和「本地构建」（需 Mac）两种可行路径。

### 路径 A：GitHub Actions 云端构建（无需 Mac，推荐）

1. 在 GitHub 新建一个**公开**仓库（公开仓库的 Actions 分钟数免费）。
2. 把本目录 `SingFor10/` 下的**全部内容**（含隐藏的 `.github` 目录）上传到仓库根目录：
   ```bash
   git init
   git add .
   git commit -m "SingFor10"
   git branch -M main
   git remote add origin https://github.com/<你的用户名>/<仓库名>.git
   git push -u origin main
   ```
   > Windows 上若 `.github` 目录未被 `git add .` 纳入，用 `git add -f .github` 强制添加。
3. 推送后进入仓库 **Actions** 页，等待 `Build SingFor10 IPA` 工作流跑完（约 3–6 分钟）。
4. 在本次运行的 **Artifacts** 区下载 `SingFor10-IPA`，解压得到：
   - `SingFor10-unsigned.ipa`
   - `SingFor10.ipa`（同一文件副本）
   - `SHA256SUMS.txt`
5. 也可在 Actions 页点 **Run workflow** 手动重新构建。

### 路径 B：Mac 本地一键构建

在 Mac 终端进入工程目录执行：

```bash
cd /path/to/SingFor10
bash scripts/build-ipa.sh
```

脚本自动归档并打包，产物在 `./build/output/SingFor10-unsigned.ipa`。

### 路径 C：Xcode 图形界面直接安装（有 Mac 时最省事）

1. 打开 `SingFor10.xcodeproj`。
2. Target `SingFor10` → Signing & Capabilities → Team 选你的 Apple ID（免费账号即可）。
3. 按需改 `PRODUCT_BUNDLE_IDENTIFIER`（默认 `com.example.SingFor10`）。
4. iPhone 用 USB 连接，选设备后 `⌘R` 直接安装运行。

### 把 IPA 装进 iPhone（Windows 也可）

云端/本地产出的 IPA 是**未签名**包，需要用侧载工具用你自己的免费 Apple ID 签名后安装：

1. 下载 **Sideloadly**（官网 `https://sideloadly.io/`，提供 Windows 与 macOS 版）。
2. Windows 上安装并打开，USB 连接 iPhone（首次需在 iPhone 上点「信任此电脑」）。
3. IPA 栏选择 `SingFor10-unsigned.ipa`。
4. 输入你的 Apple ID 与**应用专用密码**（在 Apple ID 管理页生成，格式类似 `abcd-efgh-ijkl-mnop`）。
5. 点 **Start**，等待签名与安装完成。
6. iPhone 上进入 **设置 → 通用 → VPN与设备管理 → 你的 Apple ID → 信任**。
7. 如果不幸出现「未受信任的企业级开发者」，重复第 6 步即可。

> 免费 Apple ID 签名的 App 有效期 7 天，到期需重新侧载；保持 Sideloadly 的 AltServer 类后台刷新可续期。

**模拟器限制**：`MPVolumeView` 的滑块在模拟器上无法真正改变系统音量，
音量守卫功能请在真机上验证；音频合成、倒计时、后台播放在模拟器上正常。

---

## 三、功能实现要点

| 需求 | 实现方式 |
|------|----------|
| 唱歌 10 分钟 | `AVAudioSourceNode` 实时合成"小星星"旋律（加性合成 + 颤音 + 共振峰谐波），循环播放；`Timer` 每 0.25s 刷新倒计时，满 600s 自动停止 |
| 静音键无效 | `AVAudioSession.Category.playback` —— 该类别在静音拨键开启时仍输出声音 |
| 调小声音无效 | KVO 监听 `AVAudioSession.outputVolume`，一旦低于 0.99 立即通过隐藏的 `MPVolumeView.slider` 把系统音量拉回 1.0 |
| 切后台继续 | `Info.plist` 声明 `UIBackgroundModes = audio`，音频会话在后台保持活跃 |
| 来电打断恢复 | 监听 `AVAudioSession.interruptionNotification`，中断结束后自动 `restartIfNeeded()` |
| 路由变化恢复 | 监听 `routeChangeNotification`，插拔耳机后自动恢复播放 |
| 防误触退出 | 界面上"退出"按钮点击只弹提示，10 分钟内不提供任何停止入口 |

---

## 四、iOS 系统能力边界（客观事实）

App 运行在 iOS 沙盒内，以下操作属于**系统级行为**，任何第三方 App 都无法拦截：

- **上架后从多任务界面上滑强制退出 App** —— 由 SpringBoard 直接杀死进程，App 无法阻止。
- **按电源键关机 / 重启** —— 硬件层行为，不经过任何 App。
- **系统级勿扰/通话接管** —— 来电时音频会被系统中断，App 只能在通话结束后自动恢复（已实现）。

在当前实现中，除了上述系统级手段外，常规操作（静音键、音量键、切后台、锁屏、点"退出"）
均无法在 10 分钟结束前停止播放。

---

## 五、可调参数

- `ViewController.swift` 中 `totalDuration` 修改时长（默认 600 秒）。
- `AudioEngine.swift` 中 `melody` 数组可替换为任意频率序列，`noteDuration` 控制节奏，`sampleRate` 控制采样率。
- `AudioEngine.swift` 中谐波系数可调整音色。
