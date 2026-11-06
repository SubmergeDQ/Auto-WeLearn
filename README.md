# Auto-WeLearn

WE Learn 平台的命令行自动化工具（Node.js / TypeScript 重写版）。

> **免责声明**
> 本项目仅用于个人学习研究与接口自动化练习。使用前请自行确认你的行为符合所在学校与平台的服务条款，
> 由此产生的一切后果由使用者承担。项目不包含验证码识别、UA 轮换、代理池、设备指纹伪造等风控规避功能。

## 当前状态

全部里程碑（M0–M7）已交付：**登录 / 扫描 / 解析 / 等待保活 / 真实提交 / 断点续跑 / 报告** 全链路可用。

- 已在真实账号上验证：单节提交 `startsco → 心跳 ×2 → setscoinfo → savescoinfo` 全部 `ret:0`，
  提交后平台立即显示该节已完成，CMI 中正确率与答题记录完整。
- 账号密码 SSO 登录**未实现**（依赖服务端 PKCE state，易失效），请用 Cookie 或 `--browser`。
- 进度与实测结论见 [`docs/NODE_CLI_SPEC.md`](docs/NODE_CLI_SPEC.md) 附录 F / G。

## 安装与运行

### 方式 A：直接用 exe（不需要装 Node）

把 `release/welearn-cli.exe` 复制到任意目录，在该目录打开 cmd / PowerShell：

```bat
welearn-cli.exe login --cookie "..."
welearn-cli.exe scan --course 566
welearn-cli.exe run --course 566 --unit 3 --wait 300-420
```

单文件 86 MB，内嵌 Node 运行时与全部依赖，不依赖 `node_modules`。
想在任何目录直接调用，把这个目录加进系统 `PATH` 即可。

### 方式 B：npm 包

```bash
npm i -g ./welearn-cli-0.1.0.tgz   # 装完直接 welearn-cli
```

### 方式 C：源码运行

```bash
npm install
npm run dev -- --help     # 开发模式
npm run build             # 生成 dist/index.js
```

> 要求 Node.js ≥ 22（用到内置 `fetch` / `AbortSignal.any`）。exe 方式无此要求。

## 快速开始

### 1. 登录（用浏览器 Cookie）

```bash
# 方式一：直接粘贴（用单引号包住，避免 shell 解释 $ 和 ;）
welearn-cli login --cookie 'acw_tc=...; area=dbC; .AspNet.Cookies=...'

# 方式二：从文件读取
welearn-cli login --cookie-file ./cookies.txt

# 方式三：环境变量
WELEARN_COOKIE='...' welearn-cli login

# 方式四：用本机 Chrome/Edge 登录（需要 npm i -D playwright-core）
welearn-cli login --browser
```

成功后会把会话缓存到 `~/.welearn-cli/session.json`（权限 0600），后续命令无需重复粘贴。

### 2. 扫描课程

```bash
welearn-cli scan --course 566
welearn-cli scan --course 566 --json        # 机器可读，含每节 scoid
```

输出会区分「已完成 / 未完成 / 隐藏（未解锁）」，并给出待处理队列。

### 3. 核对解析结果（只读）

```bash
welearn-cli inspect --course 566 --sco m-1-3-5
```

打印该小节解析出的题型与答案，用于确认解析器是否正确。**不会**产生任何写请求。

### 4. 预演全流程（零写入）

```bash
welearn-cli run --course 566 --dry-run --max-lessons 5
```

### 5. 真实执行

```bash
welearn-cli run --course 566 --unit 3 --wait 300-480 --rate 90-100
```

每节流程：解析题目 → `startsco` → 等待（30–40s 心跳保活）→ `setscoinfo` → `savescoinfo`。
Ctrl+C 可中断，当前节不会提交半截数据；加 `--resume` 下次跳过已完成小节。

每处理 5 节（或满 10 分钟）会重新拉一次服务端状态：若某节本地记为完成但平台仍显示未完成，
会自动重入队（每节最多 2 次）。

> `--concurrency 2/3` 可用，但平台按单元顺序解锁，并发没有收益且更容易被判异常，默认保持串行。

## 命令参考

| 命令 | 作用 |
| --- | --- |
| `login` | 校验登录态并列出课程 |
| `scan --course <cid>` | 扫描单元/小节与完成进度 |
| `inspect --course <cid> --sco <id>` | 只读解析单节题目与答案 |
| `run --course <cid> --dry-run` | 预演队列，只解析不提交 |

全局选项：`--cookie`、`--cookie-file`、`--config <path>`、`--json`、`-v/--verbose`。

退出码：`0` 成功 / `1` 有失败 / `2` 配置错误 / `3` 登录失效 / `4` 用户中断 / `5` 接口契约变更。

## 打包与分发

```bash
npm run build                # 生成 dist/index.js（单文件 ESM，约 89KB）
npm pack                     # 生成 welearn-cli-0.1.0.tgz
npm i -g ./welearn-cli-0.1.0.tgz   # 全局安装后可直接用 welearn-cli

npm run build:exe            # 生成 release/welearn-cli.exe（内嵌 Node，约 86MB）
```

exe 走 Node 官方的 SEA（Single Executable Application）：
先把代码打成单个 CJS 文件（`build/sea/index.cjs`），再生成 SEA blob，
最后用 `postject` 注入到 `node.exe` 的副本里。产物放在 `release/` 而不是 `dist/`，
因为 `npm run build` 会清空 `dist/`。

> Windows 上注入时会提示 `The signature seems corrupted!`，这是把 blob 写进已签名的
> `node.exe` 的正常现象，不影响运行；分发前如需签名，请自行用 `signtool` 重新签。

配置文件（可选）示例，命令行的优先级高于它：

```json
{
  "baseUrl": "https://welearn.sflep.com",
  "timeoutMs": 15000,
  "retry": { "max": 3, "baseDelayMs": 2000 },
  "statePath": "~/.welearn-cli/state.json"
}
```

## 工程结构

```
src/
├── cli/            命令定义与参数解析
├── config/         配置 schema 与路径
├── core/
│   ├── http/       Session（唯一网络出口）、重定向、重试
│   ├── api/        平台接口封装
│   ├── auth/       Cookie 解析、会话缓存
│   ├── parse/      双解析器（courseware / legacy）、interactions
│   ├── plan/       扫描与时间计划
│   ├── run/        单节准备与执行
│   └── state/      断点续跑状态
└── logging/        脱敏日志
```

## 测试

```bash
npm run typecheck
npm test
```

测试覆盖：日志脱敏、Cookie 解析、两种课件解析、interactions 生成、jsEscape 边界，
以及基于本地 mock 平台的端到端契约测试（断言 dry-run 不产生写请求）。

## 已知限制

- `--unit` 只能按平台返回的单元顺序处理，平台是顺序解锁的。
- `match` / `order` 题型的答案格式未在真实课件中验证，当前原样透传。
- 账号密码登录（SSO）与浏览器取 Cookie 在 M7 交付，当前只支持 Cookie 登录。
- 平台改版会导致解析失效，请对照 `docs/NODE_CLI_SPEC.md` 附录 C 排查。

## 文档

- [开发规格与实施计划](docs/NODE_CLI_SPEC.md)（含附录 C 实测契约差异、附录 E 实现决策）
