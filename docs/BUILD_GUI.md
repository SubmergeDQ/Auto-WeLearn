# GUI 构建说明（Flutter）

产物：
- `release/gui-windows/` —— Windows 桌面版（`welearn_app.exe` + 依赖 dll + data/）
- `release/welearn-app-release.apk` —— Android 安装包（50 MB，含 arm64 / armv7 / x64）

## 一、本机环境（已配好）

| 项 | 位置 / 版本 |
| --- | --- |
| Flutter SDK | `D:\dev\flutter`（3.47.9 stable，国内镜像） |
| JDK | `C:\Program Files\Java\jdk-24`（已 `flutter config --jdk-dir`） |
| Android SDK | `D:\Android\SDK`（platforms 33–37，build-tools 37.0.0） |
| VS Build Tools | `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools`（VC Tools 工作负载） |

## 二、本机特有的五个坑（已绕过，重装环境时注意）

1. **`flutter.bat` 在本机不可用**
   原生脚本会调用 `pwsh` 做引擎版本校验，本机 `call pwsh` 直接报「系统找不到指定的路径」。
   已把 `bin\flutter.bat` 换成一个直接调用 `flutter_tools.snapshot` 的代理脚本
   （原文件备份为 `flutter.bat.orig`）。等价于官方脚本在检查通过后做的事。

2. **中文路径会让 Windows / Release APK 构建失败**
   MSBuild、CMake 与 AOT snapshotter 都会把 `D:\黄译\桌面\…` 读成乱码。
   所以构建必须放在纯英文目录进行：把 `app/` 同步到 `D:\dev\wbuild` 再构建，产物再拷回 `release/`。

   > **同步必须是整目录，不能只同步 `lib/`。** 曾经只同步了 `lib test tool`，
   > `wbuild/android/` 还是旧副本，结果打出的 release APK **没有 `INTERNET` 权限**
   > （debug 包因为 `src/debug/AndroidManifest.xml` 自带该权限所以正常），
   > 表现为「登录时 Failed host lookup / 连不上服务器」。改完清单或 gradle 后务必：

   ```bash
   cd app && tar -cf - --exclude=build --exclude=.dart_tool --exclude=.idea . | (cd /d/dev/wbuild && tar -xf -)
   ```

   > 出包后建议核一次权限：`aapt dump permissions app-release.apk | grep INTERNET`。

3. **桌面托盘依赖两个插件**（只在 Windows 生效，Android 不受影响）
   - `window_manager 0.4.3`：拦截关闭按钮、隐藏/显示窗口。**不能升到 0.6.x**——那是基于
     nativeapi 的重写，旧 API 移到了 `window_manager/legacy.dart`，直接升会编译不过
   - `system_tray 2.0.3`：托盘图标与右键菜单。国内镜像里 `tray_manager` 的归档地址是坏的（404），
     所以选 `system_tray`（依赖只有 flutter/path/uuid）
   - 托盘图标：`app/assets/tray.ico`（`windows/runner/resources/app_icon.ico` 的副本），
     运行时按「exe 目录/data/flutter_assets/assets/tray.ico」读取
   - 排查关闭行为：`%TEMP%\welearn_close.log` 会记录 `preventClose` / `tray ready` / `onWindowClose`

4. **NuGet 不在 PATH 里**
   `flutter_inappwebview_windows` 的 Windows 构建会在 CMake DEPS 阶段调用 `nuget.exe`。
   本机没有全局 NuGet 时构建会报 `Nuget is not installed!` / `NUGET-NOTFOUND`。
   构建前下载一份临时 NuGet 并加到 PATH（不要提交进仓库）：

   ```powershell
   curl.exe -L -o "$env:TEMP\nuget.exe" https://dist.nuget.org/win-x86-commandline/latest/nuget.exe
   $env:PATH = "$env:TEMP;$env:PATH"
   ```

5. **代理环境变量会污染 `flutter test`**
   环境里同时存在 `HTTP_PROXY` 与 `http_proxy`，会让 flutter_tester 的本地 WebSocket 走代理而失败。
   跑测试前先删掉这些变量：

   ```powershell
   Remove-Item Env:http_proxy,Env:https_proxy,Env:HTTP_PROXY,Env:HTTPS_PROXY -ErrorAction SilentlyContinue
   ```

## 三、构建命令
```powershell
# 1. 同步到英文路径
cd D:\黄译\桌面\Project\Github\Myself\Auto-WeLearn\app
$tar = Join-Path $env:TEMP 'wbuild-sync.tar'
tar -cf $tar --exclude=build --exclude=.dart_tool --exclude=.idea .
tar -xf $tar -C D:\dev\wbuild

# 2. 在副本目录里构建（不要停留在中文 app 目录，否则 CMake 会继续引用旧路径）
cd D:\dev\wbuild
& D:\dev\fl.cmd clean
$env:PATH = "$env:TEMP;$env:PATH"   # 提供 nuget.exe
& D:\dev\fl.cmd build windows --release
# 产物：build\windows\x64\runner\Release\

# 3. Android 正式版（需要 JAVA_HOME）
$env:JAVA_HOME="C:\Program Files\Java\jdk-24"
& D:\dev\fl.cmd build apk --release
# 产物：build\app\outputs\flutter-apk\app-release.apk
```

## 四、国内镜像（已内置）

- `D:\dev\fl.cmd` 里设置了 `FLUTTER_STORAGE_BASE_URL` / `PUB_HOSTED_URL`（flutter-io.cn）
- `android/gradle/wrapper/gradle-wrapper.properties` 指向腾讯 Gradle 镜像
- `android/settings.gradle.kts` / `build.gradle.kts` 加了阿里云 Maven 镜像

## 五、验证

```powershell
& D:\dev\fl.cmd analyze          # 0 issue
& D:\dev\fl.cmd test             # 15 passed（含 1440/1100/390 三视口布局冒烟）
```

三个视口都断言了 `takeException()` 为空 —— 布局溢出会让测试直接失败。

## 六、Windows 安装程序

Flutter Release 不能只拷一个 exe；分发用 NSIS 安装包：

```powershell
& .\scripts\build-gui-installer.ps1
# 产物：release\WeLearn-Setup-1.0.2.exe
```

- NSIS 便携版放在 `D:\dev\nsis\nsis-3.11`；脚本找不到时会自动下载 zip 到 `%TEMP%`
- 安装到 `%LOCALAPPDATA%\Programs\WeLearn 助手`，`RequestExecutionLevel user`，不弹 UAC
- 创建桌面、开始菜单快捷方式和卸载项；卸载不删除 `%APPDATA%` 里的登录态与设置
- 已用 `/S /D=<临时目录>` 做过安装、启动、卸载三项实测；安装包约 10 MB
