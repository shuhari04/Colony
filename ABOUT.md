# About Colony

Colony 是一个把多智能体调度系统做成“村庄经营界面”的项目。

它的核心思路不是把 agent 平铺成列表，而是把真实的执行对象映射成空间中的实体：

- 大本营：配置本地可用 agent provider
- 小屋：代表不同 agent 类型的入口
- 工人：代表正在工作的 agent / subagent
- 建筑：代表项目、子任务或施工目标
- 河流与桥：代表环境隔离与跨世界连接
- 传送门：代表跨设备遥控

在工程上，Colony 当前由三部分组成：

- Swift Core / CLI：负责本地和 SSH 下的 tmux 会话编排与后端执行
- Flutter macOS App：负责桌面世界视图、会话抽屉和交互
- Flutter iOS App：负责 Bridge 配对、扫码连接和远程控制入口

项目当前的产品方向是：

1. 把本地村庄闭环做扎实
2. 让 SSH 远端世界以“河对岸村庄”的方式出现
3. 让 iPhone 成为同一世界的遥控视图
4. 逐步把 agent 调度、任务拆分和进度反馈做成稳定的空间系统

一句话版本：

```text
Colony is a game-like 2.5D control plane for orchestrating local and remote AI agents across macOS, iPhone, and SSH worlds.
```
