# Auto-WeLearn

WE Learn 学习助手 —— 桌面（Windows）与安卓（APK）**图形界面**，另附一套命令行版本。

> **免责声明**
> 本项目仅用于个人学习研究与接口自动化练习。使用前请自行确认你的行为符合所在学校与平台的服务条款，
> 由此产生的一切后果由使用者承担。项目不包含验证码识别、UA 轮换、代理池、设备指纹伪造等风控规避功能。

## 产物

| 产物 | 位置 | 说明 |
| --- | --- | --- |
| Windows 桌面版 | `release/gui-windows/welearn_app.exe` | 免安装，双击运行（同目录的 dll 与 data 不能删） |
| 安卓安装包 | `release/welearn-app-release.apk` | 50 MB，含 arm64 / armv7 / x64 |
| 命令行版（旧） | `release/welearn-cli.exe` | TypeScript 版，功能等价 |

## 界面

三栏工作区：左边课程与单元，中间小节队列，右边运行面板与日志；顶部一条状态栏，底部进度与统计。
移动端收成单列，日志改为底部抽屉。

- 设计说明：[docs/GUI_DESIGN.md](docs/GUI_DESIGN.md)
- 构建说明（含本机三个坑）：[docs/BUILD_GUI.md](docs/BUILD_GUI.md)
- 平台接口契约与实测结论：[docs/NODE_CLI_SPEC.md](docs/NODE_CLI_SPEC.md)

## 怎么用

1. 打开 `welearn_app.exe`（或安装 APK）
2. 点右上角「登录」，把浏览器里复制的 Cookie 粘进去
3. 自动扫描出单元与小节后，点「开始运行」
4. 运行中可以在右栏看当前节倒计时、心跳次数和每节日志；随时「停止」，当前节不会提交

Cookie 只存在本机应用数据目录，不会上传到任何地方。

### 桌面版：关闭到托盘

点窗口右上角关闭时，会问一次「关闭应用 / 最小化到托盘」：

- **最小化到托盘**：窗口隐藏，任务继续跑；托盘图标（右下角）左键单击重新打开，右键菜单有「打开主界面 / 重新扫描 / 退出」
- **关闭应用**：真正退出进程
- 勾选「下次不再询问」会记住这次选择，之后不再弹窗；想改回来，删掉应用数据里的 `closeAction` 字段或改回 `"ask"`

## 已实现 / 未实现

已实现：
- Cookie 登录（会话持久化，下次打开免登录）
- 课程 → 单元 → 小节扫描，区分已完成 / 未完成 / 未解锁
- 题目解析（填空 / 判断 / 选择 / 匹配 / 排序，两套课件都支持）
- 等待期 30–40s 心跳保活，长等待不会被判无效
- 提交失败可单节重试；运行中可随时中断
- 口语/录音题自动跳过（默认）

未实现：
- **账号密码登录**：平台用 PKCE 流程，改版风险高，故不实现；请用 Cookie
- 断点续跑、失败自动重排（CLI 版有，GUI 版后续补）

## 命令行版（保留）

```bash
npm install
npm run dev -- login --cookie "..."
npm run dev -- scan --course 566
npm run dev -- run --course 566 --unit 3 --wait 300-420
```

CLI 的接口契约、字段坑位、实测验证结论都沉淀在 [docs/NODE_CLI_SPEC.md](docs/NODE_CLI_SPEC.md) 附录 C/E/G，
GUI 的 Dart 引擎是照着它移植的。

## 目录

```
app/                Flutter 工程（GUI）
  lib/core/         引擎：session / api / parser / scorm / runner
  lib/ui/           工作区界面
release/            构建产物
src/                CLI 的 TypeScript 实现
docs/               设计说明、构建说明、接口契约
```
