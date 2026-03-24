# Colony

Colony 是一个以 2.5D 村庄为核心界面的多智能体调度系统。它把本地 agent、SSH 远端 agent、子任务和跨设备控制映射成“大本营、小屋、工人、建筑、桥、传送门”等世界对象，用游戏化但语义明确的方式管理复杂工作流。

当前仓库同时包含三部分：

- `colony` Swift CLI / Core：负责本地与 SSH 环境下的 tmux 会话、agent 启动、消息发送、日志拉取和 provider 探测。
- `apps/colony_flutter`：当前主要的桌面前端，负责世界视图、会话面板、远端节点、Bridge 配对和 iOS 端桥接入口。
- Xcode 原生壳工程：保留了后续原生端扩展入口，但当前主产品形态仍以 Flutter 桌面端为主。

## 项目定位

Colony 不是普通聊天客户端，也不是给终端加一层图标。它的目标是：

- 以空间化方式调度多个 agent / subagent
- 在一个“村庄”里管理本地和远端执行环境
- 让任务状态、会话线程、工作分配和连接边界都可视化
- 支持 macOS 主控、iOS 远程控制和 SSH 扩展世界

## 当前能力

当前仓库已经具备这些基础能力：

- 本地 `codex` / `claude` / `openclaw` agent 会话管理
- 基于 `tmux` 的启动、发送、接收、watch、attach、stop
- SSH 远端 provider 探测与远端 session 启动
- Flutter 桌面端世界视图与会话抽屉
- Bridge 配对页、二维码配对、iPhone 桥接客户端
- Bonjour 发布与“附近 Mac”发现链路

## 仓库结构

```text
.
├── Sources/
│   ├── ColonyCore/        # tmux / SSH / provider probe / backend orchestration
│   └── ColonyCLI/         # colony 命令行入口
├── apps/
│   └── colony_flutter/    # Flutter macOS + iOS app
├── design-system/         # 视觉与页面设计文档
├── COLONY_PRODUCT_MODEL.md
├── COLONY_PHASE1_IMPLEMENTATION.md
└── COLONY_PHASE1_IMPLEMENTATION.zh-CN.md
```

## 快速开始

### 1. 环境依赖

建议本机具备：

- macOS
- Xcode / Command Line Tools
- Flutter
- Swift
- `tmux`
- 至少一个 agent CLI，如 `codex`、`claude`、`openclaw`

### 2. 构建 Swift CLI

```bash
cd /Users/leitong/Downloads/Colony
swift build -c release
```

构建完成后，主二进制位于：

```text
/Users/leitong/Downloads/Colony/.build/release/colony
```

### 3. 启动 Flutter 桌面端

```bash
cd /Users/leitong/Downloads/Colony/apps/colony_flutter
flutter run -d macos --dart-define=COLONY_BIN=/Users/leitong/Downloads/Colony/.build/release/colony
```

或者直接打开已构建的应用：

```bash
open /Users/leitong/Downloads/Colony/apps/colony_flutter/build/macos/Build/Products/Debug/colony_flutter.app
```

### 4. 启动 iOS 端

```bash
cd /Users/leitong/Downloads/Colony/apps/colony_flutter
flutter build ios --simulator
```

然后把产物安装到模拟器或真机：

```text
/Users/leitong/Downloads/Colony/apps/colony_flutter/build/ios/iphonesimulator/Runner.app
```

## 常用命令

### 查看本地 provider

```bash
cd /Users/leitong/Downloads/Colony
./.build/release/colony providers local --json
```

### 查看 SSH 远端 provider

```bash
COLONY_SSH_PASSWORD=你的密码 ./.build/release/colony providers 用户名@远端IP --json
```

### 查看会话

```bash
./.build/release/colony list local
```

### 启动 Bridge 服务

当前 mac 端已内置 Bridge 页面。进入桌面应用后，点击顶部的手机图标即可打开配对面板，完成：

- 启动本地 Bridge
- 生成 token
- 展示二维码
- 向 iPhone 发布 Bonjour 服务

## 文档

- 产品模型：[COLONY_PRODUCT_MODEL.md](./COLONY_PRODUCT_MODEL.md)
- 第一阶段实施方案（英文）：[COLONY_PHASE1_IMPLEMENTATION.md](./COLONY_PHASE1_IMPLEMENTATION.md)
- 第一阶段实施方案（中文）：[COLONY_PHASE1_IMPLEMENTATION.zh-CN.md](./COLONY_PHASE1_IMPLEMENTATION.zh-CN.md)

## 当前状态

当前项目仍处于“从原型向产品结构迁移”的阶段。

已经打通的方向：

- 领域模型骨架
- 本地世界与 SSH 远端世界的基本后端能力
- Bridge / iOS 遥控第一版

仍需继续推进的方向：

- 更完整的村庄视觉语义
- 建筑、围栏、桥、河流等世界对象的正式建模
- 工人移动与施工状态表达
- iOS 与桌面同一世界状态的更深同步
