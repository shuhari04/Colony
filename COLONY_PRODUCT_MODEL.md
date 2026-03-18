# Colony Product Model

## Purpose

Colony is a multi-agent and multi-task orchestration product presented as a game-like village in a 2.5D visual style inspired by Clash of Clans.

The game metaphor is the interface layer, not the core product goal. The real goal is to schedule, observe, and control multiple agents, subagents, and task threads across local and remote environments in a way that feels spatial, legible, and operationally intuitive.

## Product Vision

### Core Idea

Colony turns agent orchestration into a village simulation:

- A village represents a working environment.
- Buildings represent capability nodes, project areas, or connection mechanisms.
- Workers represent active agents or subagents.
- Construction represents task execution and progress.
- Spatial grouping represents project boundaries and coordination structure.

The user should feel like they are assigning builders and managing a living operational settlement, while the system is actually managing sessions, prompts, execution backends, and remote connectivity.

### Target Experience

The product should feel like:

- a strategy game for software work
- a spatial control plane for multi-agent systems
- a persistent village where tasks, agents, and environments have visible physical form

It should not feel like:

- a plain chat client
- a terminal multiplexer with icons
- a dashboard made of lists and tabs only

## World Setting

### Local Village

The initial state is a local village.

At the beginning, the user only has a Town Hall style building. The Town Hall is used to configure which local agent providers are available to Colony.

Once an agent provider is configured, the corresponding worker hut appears in the village. Examples:

- Claude Code hut
- Codex hut
- OpenClaw hut

These huts are the source points from which workers can be summoned.

### Projects as Buildings and Zones

A building represents a project, or a meaningful part of a project.

Examples:

- one building for an entire repository
- one building for a frontend refactor
- one building for a backend migration
- one building for a testing pass

Different projects or subprojects can be separated spatially by fences. A fence is not just decorative; it defines a project boundary or area of responsibility.

### Workers

Clicking an agent hut can summon workers. A worker is an operational unit backed by an agent or subagent.

Workers can be assigned to buildings. Once assigned, they begin work on that building's task context. That context is fundamentally a conversation or execution thread, but in the product it should read as "construction", "repair", "upgrade", or "active work".

Clicking either:

- a worker
- a building under construction

should open the corresponding session, letting the user:

- send prompts
- inspect progress
- view logs, feedback, and results

### Cross-Device Portal

There is a special portal building used to connect the desktop Colony to a phone.

The iOS app should present the same world view and allow the user to remotely control the agents running on the computer. The phone experience is therefore a remote control surface for the same world state, not a separate standalone world.

### Remote Worlds Over SSH

Colony can connect to other computers, Raspberry Pis, or servers via SSH.

When connected, the remote environment should appear as a new village area rather than just another item in a list. The local and remote village areas are separated by a river. A bridge can be placed and configured to establish a visible operational connection between the two environments.

This metaphor encodes real system properties:

- the river represents environment isolation
- the bridge represents connectivity and trust configuration
- the new village represents a new execution world

## Product Principles

- Spatial first: tasks and agents should have stable positions in the world.
- Operational clarity: the user should always know who is working, on what, and where.
- Game metaphor with real semantics: visuals should map cleanly to actual system behavior.
- Multi-world by design: local, remote, and mobile experiences should share one conceptual model.
- Session visibility: every meaningful worker action should be inspectable through a live session view.

## Domain Model

The following model is the recommended foundation for the product.

### 1. World

A `World` represents a distinct execution environment or spatial region.

Examples:

- local desktop village
- SSH-connected remote village
- mobile mirror view of an existing world

Suggested fields:

```text
World {
  id: String
  kind: local | ssh | mobileMirror
  name: String
  connectionState: disconnected | connecting | connected | degraded
  layoutRegion: WorldRegion
  metadata: Map
}
```

Notes:

- A world is not just a host alias.
- A world owns buildings, workers, and zones.
- Multiple worlds can coexist on the same screen.

### 2. Zone

A `Zone` represents a bounded project area within a world.

This is the model behind the "fence" concept.

Suggested fields:

```text
Zone {
  id: String
  worldId: String
  projectId: String?
  label: String
  bounds: Polygon | Rect
  status: idle | active | blocked | complete
}
```

Notes:

- A zone groups buildings and activity.
- A zone can represent a full project or a subproject.
- Zones make project boundaries visible and persistent.

### 3. Building

A `Building` is a fixed world object with gameplay and operational meaning.

Recommended building types:

- `townHall`
- `agentHut`
- `projectSite`
- `portal`
- `bridge`
- `utility`

Suggested fields:

```text
Building {
  id: String
  worldId: String
  zoneId: String?
  type: BuildingType
  name: String
  position: WorldPosition
  level: Int
  status: locked | available | active | blocked | offline
  agentProvider: codex | claude | openclaw | none
  metadata: Map
}
```

Notes:

- Town Hall configures provider availability.
- Agent huts spawn workers for a specific provider.
- Project sites represent task containers.
- Portals and bridges represent cross-device and cross-world connectivity.

### 4. Worker

A `Worker` is a movable operational unit backed by an agent or subagent.

Suggested fields:

```text
Worker {
  id: String
  worldId: String
  provider: codex | claude | openclaw | other
  homeBuildingId: String
  assignedBuildingId: String?
  status: idle | routing | working | blocked | done
  sessionId: String?
  metadata: Map
}
```

Notes:

- A worker is not the same thing as a session.
- A worker may exist before being assigned work.
- A worker can be visually attached to a hut, moving, or stationed at a task site.

### 5. SessionTask

A `SessionTask` is the actual execution thread behind an active job.

This is the object most closely related to tmux sessions and prompt history.

Suggested fields:

```text
SessionTask {
  id: String
  workerId: String
  address: String
  backend: localTmux | sshTmux | relay | other
  title: String
  promptThreadId: String?
  progress: SessionProgress
  status: queued | running | waiting | blocked | done | failed
  artifacts: [Artifact]
  startedAt: DateTime?
  endedAt: DateTime?
  metadata: Map
}
```

Notes:

- This is where execution, logs, prompts, and outputs live.
- The user reaches this object by clicking a worker or an active building.
- A session task should be inspectable at all times.

### 6. Link

A `Link` represents a connection between worlds.

Examples:

- SSH bridge to another machine
- phone relay connection
- future peer-to-peer sync path

Suggested fields:

```text
Link {
  id: String
  fromWorldId: String
  toWorldId: String
  type: ssh | relay | mobile
  status: disconnected | connecting | connected | degraded
  configSummary: String
  metadata: Map
}
```

Notes:

- A bridge in the UI should map to a real `Link`.
- A link is a first-class domain object, not just configuration hidden in a dialog.

## Interaction Model

### Town Hall

The Town Hall is the control center for enabling and configuring local providers.

User actions:

- inspect local runtime setup
- enable or disable agent providers
- verify local tools and credentials
- unlock corresponding huts

### Agent Hut

An agent hut is the source of workers for a given provider.

User actions:

- summon a new worker
- inspect available models or provider settings
- see hut occupancy and worker capacity

### Project Site

A project site is a task container rendered as a building or construction area.

User actions:

- assign one or more workers
- inspect the project's active threads
- see construction progress as a proxy for task progress

### Worker

A worker is the interactive embodiment of an active or idle agent.

User actions:

- inspect current assignment
- reassign to a different building
- open the current session
- stop, pause, or reroute work

### Session Inspector

The session inspector is the operational drawer or panel.

It should support:

- live logs
- prompt sending
- progress display
- feedback and result history
- task state and routing context

### Portal

The portal configures and visualizes phone connectivity.

User actions:

- pair or connect to mobile
- see remote control availability
- enter a mirrored control mode

### Bridge

The bridge configures and visualizes remote world connectivity.

User actions:

- create SSH links
- inspect connection health
- establish access between separated worlds

## Mapping to the Current Codebase

The current repository already contains useful execution primitives, but the domain model is still much flatter than the intended product.

### What Exists Today

- a Swift core library for local and SSH tmux control
- a CLI for session start, stop, send, receive, watch, attach, and agent bootstrap
- a Flutter macOS app with an isometric world view
- basic concepts for local and remote targets
- session logs streamed into a drawer

### Current Approximate Mapping

```text
Current Project      -> temporary stand-in for a building or world anchor
Current Session      -> blended stand-in for Worker + SessionTask
Current local/ssh    -> partial stand-in for World
Current Hut button   -> early stand-in for agent hut spawning
```

### What Is Missing

- a real `World` entity
- a real `Zone` or fence model
- a true `Building` type system
- a separate `Worker` lifecycle
- a separate `SessionTask` lifecycle
- first-class `Link` objects
- mobile mirror semantics
- spatial representation of bridges, rivers, and portals

## Engineering Guidance

Before major UI iteration, the product should adopt the domain model above as the source of truth.

### Recommended Sequence

1. Define the canonical entities:
   `World`, `Zone`, `Building`, `Worker`, `SessionTask`, `Link`
2. Refactor state management so UI reads from domain objects instead of ad hoc display models.
3. Decouple workers from sessions.
4. Make local village flow complete first:
   Town Hall -> hut -> worker -> project site -> session inspector
5. Add SSH remote worlds and bridge mechanics next.
6. Add iOS portal and mirrored control after the world model is stable.

### Important Constraint

The UI should not drive the data model by metaphor alone. The metaphor must be grounded in stable system semantics, or the project will drift into a visually interesting but architecturally weak state.

## Summary

Colony should be treated as a spatial operating system for multi-agent work.

Its game-like world is not decoration. It is the primary interface for:

- provisioning agents
- assigning work
- observing execution
- traversing environments
- coordinating local and remote compute worlds

The domain model in this document should serve as the baseline for future architecture, state management, and UI planning.
