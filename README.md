# Auto-WeLearn

WE Learn 平台的命令行自动化工具（Node.js / TypeScript 重写版）。

> **免责声明**
> 本项目仅用于个人学习研究与接口自动化练习。使用前请自行确认你的行为符合所在学校与平台的服务条款，
> 由此产生的一切后果由使用者承担。项目不包含验证码识别、UA 轮换、代理池、设备指纹伪造等风控规避功能。

## 当前状态

批次 A（M0–M3）已交付：**登录 / 扫描 / 解析 / dry-run** 全链路可用，所有网络请求只读。

真实提交（startsco / setscoinfo / savescoinfo）与心跳保活在批次 B 交付，详见
[`docs/NODE_CLI_SPEC.md`](docs/NODE_CLI_SPEC.md) 附录 F。

## 环境要求

- Node.js ≥ 22（使用内置 `fetch` / `AbortSignal.any`）
- Windows / macOS / Linux

## 安装

```bash
npm install
npm run build      # 产物在 dist/，可直接 node dist/index.js 运行
# 或开发模式
npm run dev -- --help
```

## 快速开始

### 1. 登录（用浏览器 Cookie）

```bash
# 方式一：直接粘贴（用单引号包住，避免 shell 解释 $ 和 ;）
welearn-cli login --cookie 'acw_tc=...; area=dbC; .AspNet.Cookies=...'

# 方式二：从文件读取
welearn-cli login --cookie-file ./cookies.txt

# 方式三：环境变量
WELEARN_COOKIE='...' welearn-cli login
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

## 命令参考

| 命令 | 作用 |
| --- | --- |
| `login` | 校验登录态并列出课程 |
| `scan --course <cid>` | 扫描单元/小节与完成进度 |
| `inspect --course <cid> --sco <id>` | 只读解析单节题目与答案 |
| `run --course <cid> --dry-run` | 预演队列，只解析不提交 |

全局选项：`--cookie`、`--cookie-file`、`--json`、`-v/--verbose`。

退出码：`0` 成功 / `1` 有失败 / `2` 配置错误 / `3` 登录失效 / `4` 用户中断 / `5` 接口契约变更。

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
