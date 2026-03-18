# Colony Phase 1 Implementation Plan

## Goal

Phase 1 establishes the minimum product architecture needed to turn the current prototype into a stable foundation for the full Colony vision.

This phase does not attempt to complete the entire game metaphor. Its goal is to make the local village loop real, coherent, and extensible:

- Town Hall
- agent huts
- workers
- project sites
- session inspector

## Scope

Phase 1 should include:

- canonical domain entities in the app layer
- a state model built around those entities
- a complete local village interaction loop
- compatibility with the existing `colony` CLI backend
- an upgrade path for SSH worlds later

Phase 1 should not yet fully implement:

- multi-world river and bridge visuals
- iOS portal sync
- complex animation systems
- task dependency graphs
- long-term persistence and save/load beyond simple local state if not required

## Product Slice

### User Story

A user opens Colony on macOS and can:

1. inspect the Town Hall
2. enable a local agent provider
3. see the corresponding hut appear
4. summon a worker from the hut
5. assign the worker to a project site
6. open the session inspector
7. send prompts and observe progress

If this loop is not solid, later world expansion will be unstable.

## Architecture

### Existing Backend Boundary

The existing backend contract is already useful:

- `colony start`
- `colony stop`
- `colony send`
- `colony recv`
- `colony watch`
- `colony list`
- `colony codex-rate-limit`

Phase 1 should preserve this backend and avoid premature backend redesign.

The current Swift CLI should remain the execution plane while Flutter evolves into the proper world model.

### Recommended Frontend Layers

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

## Domain Entities for Phase 1

Phase 1 only needs a subset of the full model to be fully live.

### World

Only one fully supported world is required in Phase 1:

- `local`

Suggested fields:

```text
World {
  id
  kind
  name
  connectionState
}
```

### Building

Phase 1 building types:

- `townHall`
- `agentHut`
- `projectSite`

Suggested fields:

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

Suggested fields:

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

Suggested fields:

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

Phase 1 can support only simple rectangular project zones or even defer explicit drawing if needed. But the data model should exist.

## State Model

The current `AppState` is too UI-centric. Phase 1 should reshape it into a domain-driven store.

### Recommended Store Shape

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

### Selection

Suggested selection union:

```text
none
world(worldId)
building(buildingId)
worker(workerId)
sessionTask(sessionTaskId)
```

This is more future-proof than selecting only project or session.

### Runtime State

Suggested runtime-only state:

- active log subscriptions by `sessionTaskId`
- pending command flags
- last backend errors
- rate limit snapshot

## Migration from Current Models

### Current `Project`

Current `Project` should be split conceptually:

- local base node becomes `World`
- building-like objects become `Building`
- project grouping later becomes `Zone`

Do not keep the current `Project` abstraction long-term.

### Current `Session`

Current `Session` should be split into:

- `Worker`
- `SessionTask`

Rule:

- if it moves around the world, it is probably a `Worker`
- if it stores address, logs, prompts, backend lifecycle, it is probably a `SessionTask`

### Current `AppState`

Current `AppState` should become either:

- `ColonyStore`, or
- a root store plus small controllers

It should stop owning ad hoc derived world geometry directly where possible.

## UI Mapping

### Town Hall

Maps to a `Building(type: townHall)`.

Phase 1 responsibilities:

- show configured local providers
- show unavailable providers
- allow enabling provider huts

### Agent Hut

Maps to `Building(type: agentHut)`.

Phase 1 responsibilities:

- spawn worker
- show provider type
- show ready/locked/active state

### Worker Unit

Maps to `Worker`.

Phase 1 responsibilities:

- render near its home hut or assigned project site
- support selection
- support assignment flow

### Project Site

Maps to `Building(type: projectSite)`.

Phase 1 responsibilities:

- represent a project or task area
- accept worker assignment
- show active work count

### Session Inspector

Maps to `SessionTask`.

Phase 1 responsibilities:

- log view
- prompt input
- model switching where relevant
- task status display

## Files and Directory Direction

Suggested Flutter restructuring:

```text
apps/colony_flutter/lib/src/
  domain/
    world.dart
    building.dart
    worker.dart
    session_task.dart
    zone.dart
    link.dart
  application/
    colony_store.dart
    commands/
    selectors/
  infrastructure/
    colony_cli.dart
    log_streams.dart
  ui/
    world/
    inspector/
    dialogs/
    widgets/
```

This can be done incrementally. It does not need to be a single refactor.

## Incremental Execution Plan

### Step 1

Add domain entities without deleting the old models yet.

Deliverable:

- compile-safe new model layer
- no UI changes required yet

### Step 2

Introduce a new store shape and adapters from old state to new state.

Deliverable:

- existing world view still works
- new store becomes source of truth

### Step 3

Replace current local base and hut logic with real `Building` entities.

Deliverable:

- Town Hall building
- agent hut buildings driven by provider state

### Step 4

Split session behavior into `Worker` plus `SessionTask`.

Deliverable:

- workers rendered independently
- session inspector resolves through `worker -> sessionTask`

### Step 5

Add project sites and assignment flow.

Deliverable:

- a worker can be assigned to a project site
- assignment creates or binds a session task

### Step 6

Tighten UI semantics.

Deliverable:

- selection model upgraded
- drawer content keyed by actual domain entity
- status labels aligned with the product metaphor

## Backend Compatibility Strategy

The CLI backend can remain mostly unchanged in Phase 1.

Suggested mapping:

- worker assignment creates a `SessionTask`
- `SessionTask.address` maps to existing tmux session addressing
- session logs still come from `watch`
- prompt sending still goes through `send`

This keeps the refactor focused on the product model rather than rewriting the execution stack.

## Risks

### Risk 1: UI Metaphor Outruns Data Model

If more visuals are added before the entity model is stabilized, the app will become harder to change.

### Risk 2: Worker and Session Stay Coupled

If these remain the same object, later assignment, rerouting, and queueing features will be awkward.

### Risk 3: Remote Worlds Are Added Too Early

If SSH world rendering is added before local semantics are clean, the model will fork into exceptions and special cases.

## Phase 1 Success Criteria

Phase 1 is successful when:

- the local world is represented by real domain entities
- Town Hall and huts are real buildings, not placeholder UI tiles
- workers are distinct from sessions
- project sites exist as assignable task targets
- the session inspector works through the new model
- the existing CLI backend still drives live sessions successfully

## Immediate Next Implementation Task

The best next engineering step is:

1. add the domain model files under `lib/src/domain/`
2. create a new root store under `lib/src/application/`
3. adapt the current world screen to read from the new store with compatibility shims

That gives the project a correct backbone before larger visual or interaction upgrades.
