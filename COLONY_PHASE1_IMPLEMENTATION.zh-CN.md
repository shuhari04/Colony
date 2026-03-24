# Colony 第一阶段实施方案

## 目标

第一阶段的目标，是为 Colony 从原型走向完整产品建立最小但稳定的工程基础。

这一阶段不会试图一次性实现完整的“部落冲突式”游戏隐喻，而是先把本地村庄这条核心闭环做实、做顺：

- 大本营
- Agent 小屋
- 工人
- 项目建筑
- 会话检查器

## 范围

第一阶段应当包含：

- 在应用层建立规范的领域实体
- 围绕这些实体搭建状态模型
- 打通完整的本地村庄交互闭环
- 保持与现有 `colony` CLI 后端兼容
- 为后续 SSH 世界扩展预留清晰升级路径

第一阶段暂不完整实现：

- 多世界的河流与桥梁视觉系统
- iOS 传送门实时同步
- 复杂动画系统
- 任务依赖图
- 除简单本地状态外的长期持久化与存档能力

## 产品切片

### 用户故事

用户在 macOS 上打开 Colony 后，应当可以：

1. 查看大本营
2. 启用一个本地 agent provider
3. 看到对应的小屋出现在村庄中
4. 从小屋召唤工人
5. 将工人分配到某个项目建筑
6. 打开会话检查器
7. 发送 prompt 并观察进度

如果这条闭环不稳定，后续多世界、跨设备和远程扩展都会建立在脆弱基础上。

## 架构

### 现有后端边界

当前后端接口已经足够有用，第一阶段应该保留并复用：

- `colony start`
- `colony stop`
- `colony send`
- `colony recv`
- `colony watch`
- `colony list`
- `colony codex-rate-limit`

第一阶段不应过早重做后端，而应保持 Swift CLI 作为执行平面，让 Flutter 前端逐步演进为真正的世界模型。

### 推荐的前端分层

```text
UI Layer
  screens, drawers, world rendering, inspector panels

Application Layer
  app store, use cases, selection state, commands

Domain Layer
  World, Zone, Building, Worker, SessionTask, Link

Infrastructure Layer
  colony CLI adapter, process spawning, log streams
```

## 第一阶段的领域实体

第一阶段只需要让完整模型中的一部分先真正“活起来”。

### World

第一阶段只要求一个完整支持的世界：

- `local`

建议字段：

```text
World {
  id
  kind
  name
  connectionState
}
```

### Building

第一阶段的建筑类型：

- `townHall`
- `agentHut`
- `projectSite`

建议字段：

```text
Building {
  id
  worldId
  type
  name
  position
  status
  provider?
}
```

### Worker

建议字段：

```text
Worker {
  id
  worldId
  provider
  homeBuildingId
  assignedBuildingId?
  sessionTaskId?
  status
}
```

### SessionTask

建议字段：

```text
SessionTask {
  id
  workerId
  address
  backend
  title
  status
  latestOutputPreview
}
```

### Zone

第一阶段可以只支持简单的矩形项目区域，甚至在 UI 上暂时不完整绘制，但数据模型应当先存在。

## 状态模型

当前 `AppState` 过于面向 UI。第一阶段应把它重塑为由领域模型驱动的 store。

### 推荐的 Store 结构

```text
ColonyStore
  worldsById
  buildingsById
  workersById
  sessionTasksById
  zonesById
  selection
  uiState
  runtimeState
```

### 选择态

建议的选择联合类型：

```text
none
world(worldId)
building(buildingId)
worker(workerId)
sessionTask(sessionTaskId)
```

它比当前只选择 project 或 session 更适合后续扩展。

### 运行态

建议纳入运行时状态的数据：

- 按 `sessionTaskId` 管理的日志订阅
- 正在进行中的命令标记
- 最近一次后端错误
- rate limit 快照

## 从当前模型迁移

### 当前的 `Project`

当前 `Project` 在概念上应拆开：

- 本地基础节点应归为 `World`
- 类建筑对象应归为 `Building`
- 未来的项目分组应归为 `Zone`

长期来看，不应继续保留当前的 `Project` 抽象。

### 当前的 `Session`

当前 `Session` 应拆成两部分：

- `Worker`
- `SessionTask`

经验规则：

- 会在世界中移动的，通常是 `Worker`
- 保存 address、日志、prompt、后端生命周期的，通常是 `SessionTask`

### 当前的 `AppState`

当前 `AppState` 最终应演进为：

- `ColonyStore`

或者：

- 一个根 store 加若干小型 controller

它应尽量停止直接持有大量临时几何状态和临时派生逻辑。

## UI 映射

### 大本营

对应 `Building(type: townHall)`。

第一阶段职责：

- 展示本地 provider 配置状态
- 显示可用与不可用的 provider
- 允许启用相应 provider 小屋

### Agent 小屋

对应 `Building(type: agentHut)`。

第一阶段职责：

- 生成工人
- 展示 provider 类型
- 显示 ready / locked / active 状态

### 工人单位

对应 `Worker`。

第一阶段职责：

- 在世界中可见
- 体现 idle / working / blocked 等状态
- 被点击后进入对应会话

### 项目建筑

对应 `Building(type: projectSite)`。

第一阶段职责：

- 承载任务上下文
- 成为工人被分配的目标
- 成为打开会话的入口之一

### 会话检查器

对应 `SessionTask`。

第一阶段职责：

- 显示 prompt 历史
- 显示输出与日志
- 提供发送消息入口
- 显示运行状态

## 第一阶段推荐实施顺序

### 1. 先固定领域模型

先在 Flutter 代码中正式定义：

- `World`
- `Building`
- `Worker`
- `SessionTask`
- `Zone`

在完成这一步之前，不建议继续扩张 UI 复杂度。

### 2. 搭建新的 Store

建立一个围绕领域实体的根 store，并把兼容层限制在边缘，而不是继续让 UI 直接依赖旧结构。

### 3. 建立兼容映射

短期内可以把旧的：

- `Project`
- `Session`

映射到新模型上，保证现有界面仍可运行。

### 4. 打通本地村庄闭环

先把这条链路做实：

- 大本营
- 小屋
- 工人
- 项目建筑
- 会话检查器

### 5. 再扩 SSH 世界

在本地闭环稳定后，再加入：

- 远程世界
- 河流
- 桥梁
- 跨世界派工

### 6. 最后做 iOS 传送门

iOS 应建立在稳定的世界模型之上，而不是单独再拼一套会话 UI。

## 第一阶段完成标准

如果满足以下条件，可以认为第一阶段完成：

- 本地世界模型稳定存在
- 大本营、小屋、工人、项目建筑都有明确数据对象
- 用户能从建筑交互走到真实会话
- 日志、输出、状态能被稳定观察
- `Project` / `Session` 旧抽象已经被兼容层隔离
- 后续 SSH 与 iOS 扩展不需要推倒重来

## 结论

第一阶段的关键不是把 Colony 立刻做成完整游戏，而是让“村庄式 agent 调度”第一次在工程上站住。

这一阶段只要把本地闭环做扎实，后续的 SSH 世界、桥、传送门、围栏和多工人协作，都会自然建立在同一套模型上，而不是继续堆积临时 UI 逻辑。
