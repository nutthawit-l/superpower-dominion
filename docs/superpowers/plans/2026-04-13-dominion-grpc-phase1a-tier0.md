# dominion-grpc Phase 1a Tier 0 — Walking Skeleton + Basics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the dominion-grpc monorepo with a minimal but complete backend stack — proto contract, pure-Go engine, in-memory store, Connect server, bot library, and BigMoney strategy — such that a bot-vs-bot BigMoney game plays end-to-end via real Connect HTTP on loopback.

**Architecture:** Server-authoritative turn-based game on Connect-Go. Engine is pure Go with zero transport awareness; service layer translates protobuf ↔ engine; bot is a first-class Connect client sharing the same surface any future UI will consume. Game state is in-memory (`map[GameID]*GameState` behind a mutex) — persistence arrives in Phase 2.

**Tech Stack:** Go 1.22+, protobuf (proto3), buf CLI, `connectrpc.com/connect`, `github.com/stretchr/testify`, `golang.org/x/sync/errgroup`, `golangci-lint`, GitHub Actions.

**Source spec:** `docs/superpowers/specs/2026-04-12-dominion-grpc-design.md` (in dev-env repo).

---

## Conventions

- **Working directory for Task 1 only:** `/home/tie/superpower-dominion/` (the dev-env repo).
- **Working directory for Tasks 2 onward:** `/home/tie/superpower-dominion/dominion-grpc/` (the new project repo, created in Task 2).
- **Go module path:** `github.com/tie/dominion-grpc`. If your real GitHub path differs, substitute in `go.mod` (Task 2) and in every `import` statement below.
- **Commit style:** Conventional Commits — `feat(scope): …`, `chore(scope): …`, `test(scope): …`. Scope is one of `engine`, `proto`, `server`, `bot`, `store`, `ci`, `docs`, or omitted for cross-cutting chores.
- **TDD discipline:** every logic task writes the failing test first, runs it to see it fail, implements the minimum to pass, runs it again to see it pass, **then** commits. Skipping the "run to see fail" step silently ships broken tests. Never skip it.
- **Tooling prerequisites** (install before Task 3): `go` ≥1.22, `buf` ≥1.34 (https://buf.build/docs/installation), `golangci-lint` ≥1.58, `git`.

## Task list summary

1. Exclude `dominion-grpc/` from dev-env `.gitignore`
2. Initialize dominion-grpc repo (git + go module + README + Makefile skeleton)
3. Add buf configuration
4. Write proto contract (`common.proto`, `card.proto`, `game.proto`)
5. Generate and commit Go protobuf stubs
6. Add golangci-lint config
7. Add GitHub Actions CI workflow
8. Add GitHub issue templates
9. Engine: core types + card struct
10. Engine: state, player, supply
11. Engine: action types
12. Engine: RNG wrapper
13. Engine primitive: `DrawCards` + `DiscardFromHand`
14. Engine primitive: `AddCoins` / `AddBuys` / `AddActions`
15. Engine primitive: `GainCard`
16. Engine: card registry
17. Engine cards: Copper / Silver / Gold
18. Engine cards: Estate / Duchy / Province / Curse
19. Engine: initial-state builder + 2-player supply setup
20. Engine: phase state machine + cleanup + endTurn
21. Engine: scoring + game-end detection
22. Engine: `Apply` entry point (PlayCard / BuyCard / EndPhase)
23. Engine: card-conservation property test (500 seeds)
24. Store: in-memory game registry
25. Service: translation helpers (engine ↔ proto)
26. Service: `CreateGame` + `SubmitAction` handlers
27. Service: `StreamGameEvents` handler
28. `cmd/server/main.go` wiring
29. Bot: Connect client wrapper
30. Bot: `ClientState` reducer
31. Bot: `Strategy` interface + `safeRefusal` helper
32. Bot: BigMoney strategy
33. Bot: `Run` loop
34. `cmd/bot/main.go` CLI
35. Integration test: BigMoney vs BigMoney fixed-seed bot-vs-bot game
36. Replay test scaffolding
37. README + Makefile finishing touches

---

## Task 1: Exclude dominion-grpc/ from dev-env .gitignore

Runs in the **dev-env** repo (`/home/tie/superpower-dominion/`). This is the only commit in that repo — everything after this lands in the new project repo.

**Files:**
- Modify: `/home/tie/superpower-dominion/.gitignore`

- [ ] **Step 1: Append exclusion**

Edit `/home/tie/superpower-dominion/.gitignore`, append at end:

```
# Project repo (separate, independent git repo — never tracked from dev-env)
/dominion-grpc/
```

- [ ] **Step 2: Create the empty directory and verify it is ignored**

Run:
```bash
cd /home/tie/superpower-dominion/
mkdir -p dominion-grpc
git status --short
```
Expected output includes `M .gitignore` and does NOT include any `dominion-grpc/` entry.

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: exclude dominion-grpc project repo from dev-env"
```

---

## Task 2: Initialize dominion-grpc repo

All subsequent tasks run inside `/home/tie/superpower-dominion/dominion-grpc/`.

**Files (all new):**
- Create: `.gitignore`
- Create: `README.md`
- Create: `go.mod` (via `go mod init`)
- Create: `Makefile`

- [ ] **Step 1: Initialize git repo and Go module**

```bash
cd /home/tie/superpower-dominion/dominion-grpc
git init -b main
go mod init github.com/tie/dominion-grpc
```

Expected: `go.mod` created with `module github.com/tie/dominion-grpc` and a Go directive matching your installed toolchain.

- [ ] **Step 2: Write .gitignore**

Create `.gitignore`:
```
# Build artifacts
/bin/
/dist/

# Go
*.test
*.out
/coverage.out

# Editor noise
.vscode/settings.json
.idea/
*.swp
```

- [ ] **Step 3: Write initial README**

Create `README.md`:
```markdown
# dominion-grpc

A server-authoritative Dominion implementation in Go. Uses Connect-Go over
HTTP for the RPC layer; protobuf is the single source of truth for the
contract between server and any client.

**Status:** Phase 1a / Tier 0 — basics + BigMoney. See `docs/` for design
and plans (in the dev-env repo).

## Build

    make generate    # regenerate gen/go/ from proto/
    make test        # run full test suite
    make test-short  # skip the 1000-game integration sweep
    make server      # run Connect server on :8080
    make bot         # run the standalone bot CLI

## Layout

    proto/               source of truth — protobuf contract
    gen/go/              generated Go stubs (committed; never hand-edit)
    cmd/server/          Connect-Go HTTP server entry point
    cmd/bot/             bot CLI entry point
    internal/engine/     pure Go game engine (no network, no protobuf)
    internal/service/    Connect handlers (translation layer)
    internal/store/      in-memory game registry
    internal/bot/        bot library: state reducer, strategies, run loop
```

- [ ] **Step 4: Write skeleton Makefile**

Create `Makefile`:
```makefile
.PHONY: generate test test-short lint server bot install-tools

generate:
	buf generate

test:
	go test ./...

test-short:
	go test -short ./...

lint:
	buf lint
	buf breaking --against .git#branch=main,subdir=.
	golangci-lint run ./...

server:
	go run ./cmd/server

bot:
	go run ./cmd/bot

install-tools:
	@echo "Install buf: https://buf.build/docs/installation"
	@echo "Install golangci-lint: https://golangci-lint.run/usage/install/"
```

(The `buf breaking --against` invocation will fail on the very first run because `main` has no prior proto version; Task 7's CI workflow handles this by skipping breaking checks until `main` exists. Keep the local target as-is — after the first push it will work.)

- [ ] **Step 5: First commit**

```bash
git add .gitignore README.md go.mod Makefile
git commit -m "chore: initialize dominion-grpc repo"
```

---

## Task 3: Add buf configuration

**Files:**
- Create: `buf.yaml`
- Create: `buf.gen.yaml`

- [ ] **Step 1: Write `buf.yaml`**

Create `buf.yaml`:
```yaml
version: v2
modules:
  - path: proto
lint:
  use:
    - STANDARD
  except:
    - PACKAGE_VERSION_SUFFIX
breaking:
  use:
    - FILE
```

- [ ] **Step 2: Write `buf.gen.yaml`**

Create `buf.gen.yaml`:
```yaml
version: v2
managed:
  enabled: true
  override:
    - file_option: go_package_prefix
      value: github.com/tie/dominion-grpc/gen/go
plugins:
  - remote: buf.build/protocolbuffers/go
    out: gen/go
    opt: paths=source_relative
  - remote: buf.build/connectrpc/go
    out: gen/go
    opt: paths=source_relative
```

- [ ] **Step 3: Verify buf accepts the config**

Run:
```bash
buf lint
```
Expected: exit 0 with no output (nothing to lint yet — no `.proto` files — but config must parse).

- [ ] **Step 4: Commit**

```bash
git add buf.yaml buf.gen.yaml
git commit -m "chore(proto): add buf configuration"
```

---

## Task 4: Write proto contract

All three proto files land in one task because they cross-reference each other and together form the minimum viable contract for Tier 0. Post-Tier-0 changes are additive.

**Files (all new):**
- Create: `proto/dominion/v1/common.proto`
- Create: `proto/dominion/v1/card.proto`
- Create: `proto/dominion/v1/game.proto`

- [ ] **Step 1: Write `proto/dominion/v1/common.proto`**

```protobuf
syntax = "proto3";

package dominion.v1;

// Phase of the current player's turn.
enum Phase {
  PHASE_UNSPECIFIED = 0;
  PHASE_ACTION = 1;
  PHASE_BUY = 2;
  PHASE_CLEANUP = 3;
}

// CardType is a set of tags on a card. A single card can have multiple
// (e.g., a hypothetical Action-Reaction).
enum CardType {
  CARD_TYPE_UNSPECIFIED = 0;
  CARD_TYPE_TREASURE = 1;
  CARD_TYPE_VICTORY = 2;
  CARD_TYPE_CURSE = 3;
  CARD_TYPE_ACTION = 4;
  CARD_TYPE_ATTACK = 5;
  CARD_TYPE_REACTION = 6;
}
```

- [ ] **Step 2: Write `proto/dominion/v1/card.proto`**

```protobuf
syntax = "proto3";

package dominion.v1;

import "dominion/v1/common.proto";

// A card instance is identified by its card_id string (e.g., "copper",
// "smithy"). Full card data lives server-side in the engine registry.
// Clients resolve ids to display data via a lookup table or the snapshot.
message CardRef {
  string card_id = 1;
}

// Supply pile state: how many of each card remain in the central supply.
message SupplyPile {
  string card_id = 1;
  int32 count = 2;
}
```

- [ ] **Step 3: Write `proto/dominion/v1/game.proto`**

```protobuf
syntax = "proto3";

package dominion.v1;

import "dominion/v1/common.proto";
import "dominion/v1/card.proto";
import "google/protobuf/timestamp.proto";

// =====================================================================
// Service
// =====================================================================

service GameService {
  rpc CreateGame(CreateGameRequest) returns (CreateGameResponse);
  rpc StreamGameEvents(StreamGameEventsRequest) returns (stream GameEvent);
  rpc SubmitAction(SubmitActionRequest) returns (SubmitActionResponse);
}

// =====================================================================
// Player view — per-player snapshot of their own visible state
// =====================================================================

message PlayerView {
  int32 player_idx = 1;
  string name = 2;
  int32 hand_size = 3;
  int32 deck_size = 4;
  int32 discard_size = 5;
  int32 in_play_size = 6;
  int32 actions = 7;
  int32 buys = 8;
  int32 coins = 9;
  // Only filled in for "me" — server scrubs opponents' hand contents.
  repeated string hand = 10;
  repeated string in_play = 11;
}

// =====================================================================
// Game state snapshot
// =====================================================================

message GameStateSnapshot {
  string game_id = 1;
  int64 seed = 2;
  int32 turn = 3;
  int32 current_player = 4;
  Phase phase = 5;
  repeated PlayerView players = 6;
  repeated SupplyPile supply = 7;
  int32 trash_size = 8;
  Decision pending_decision = 9; // nil when no decision pending
  bool ended = 10;
  repeated int32 winners = 11;
}

// =====================================================================
// Actions
// =====================================================================

message Action {
  oneof kind {
    PlayCardAction play_card = 1;
    BuyCardAction buy_card = 2;
    EndPhaseAction end_phase = 3;
    ResolveDecision resolve = 4;
  }
}

message PlayCardAction {
  int32 player_idx = 1;
  string card_id = 2;
}

message BuyCardAction {
  int32 player_idx = 1;
  string card_id = 2;
}

message EndPhaseAction {
  int32 player_idx = 1;
}

// =====================================================================
// Decisions (plumbing is present from Tier 0 even though no basic card
// uses it — Tier 2 will populate the prompts)
// =====================================================================

message Decision {
  string id = 1;
  int32 player_idx = 2;
  // Prompt variants will be added in Tier 2. For Tier 0, no card sets a
  // pending decision, so the prompt oneof is empty on the wire.
}

message ResolveDecision {
  string decision_id = 1;
  int32 player_idx = 2;
  // Answer variants will be added in Tier 2.
}

// =====================================================================
// RPC requests and responses
// =====================================================================

message CreateGameRequest {
  // Each entry is a strategy identifier: "human", "bigmoney", "smithy_bm".
  repeated string players = 1;
  int64 seed = 2;
  // If empty, Tier 0 default supply (basics only) is used.
  repeated string kingdom = 3;
}

message CreateGameResponse {
  string game_id = 1;
  GameStateSnapshot snapshot = 2;
}

message StreamGameEventsRequest {
  string game_id = 1;
  int32 player_idx = 2; // which player's view the stream is scrubbed for
}

message SubmitActionRequest {
  string game_id = 1;
  Action action = 2;
}

message SubmitActionResponse {
  // Empty — real results arrive on the event stream.
}

// =====================================================================
// Events (server-streamed)
// =====================================================================

message GameEvent {
  uint64 sequence = 1;
  google.protobuf.Timestamp at = 2;
  oneof kind {
    GameStateSnapshot snapshot = 3;
    PlayerActionApplied action_applied = 4;
    PhaseChanged phase_changed = 5;
    TurnStarted turn_started = 6;
    DecisionRequested decision = 7;
    GameEnded ended = 8;
  }
}

message PlayerActionApplied {
  int32 player_idx = 1;
  Action action = 2;
  GameStateSnapshot state_after = 3;
}

message PhaseChanged {
  Phase new_phase = 1;
  int32 player_idx = 2;
}

message TurnStarted {
  int32 turn = 1;
  int32 player_idx = 2;
}

message DecisionRequested {
  int32 player_idx = 1;
  Decision decision = 2;
}

message GameEnded {
  repeated int32 winners = 1;
  map<int32, int32> final_scores = 2;
}
```

- [ ] **Step 4: Lint the proto**

Run:
```bash
buf lint
```
Expected: exit 0, no output.

- [ ] **Step 5: Commit**

```bash
git add proto/
git commit -m "feat(proto): add Tier 0 contract (GameService + basics)"
```

---

## Task 5: Generate and commit Go protobuf stubs

**Files (all new, generated):**
- Create: `gen/go/dominion/v1/common.pb.go`
- Create: `gen/go/dominion/v1/card.pb.go`
- Create: `gen/go/dominion/v1/game.pb.go`
- Create: `gen/go/dominion/v1/dominionv1connect/game.connect.go`

- [ ] **Step 1: Run buf generate**

```bash
buf generate
```
Expected: files appear under `gen/go/dominion/v1/` and `gen/go/dominion/v1/dominionv1connect/`. Verify with:
```bash
ls gen/go/dominion/v1/
ls gen/go/dominion/v1/dominionv1connect/
```

- [ ] **Step 2: Add required dependencies**

```bash
go get google.golang.org/protobuf@latest
go get connectrpc.com/connect@latest
go mod tidy
```

- [ ] **Step 3: Verify the generated code compiles**

```bash
go build ./gen/...
```
Expected: exit 0, no output.

- [ ] **Step 4: Commit generated code + go.sum**

```bash
git add gen/ go.mod go.sum
git commit -m "chore(proto): commit generated Go stubs for Tier 0 contract"
```

---

## Task 6: Add golangci-lint config

**Files:**
- Create: `.golangci.yml`

- [ ] **Step 1: Write config**

Create `.golangci.yml`:
```yaml
run:
  timeout: 5m
  skip-dirs:
    - gen

linters:
  disable-all: true
  enable:
    - errcheck
    - gofmt
    - govet
    - ineffassign
    - staticcheck
    - unused

issues:
  exclude-dirs:
    - gen
```

- [ ] **Step 2: Verify it runs clean**

```bash
golangci-lint run ./...
```
Expected: exit 0. (There is no code yet — clean by definition.)

- [ ] **Step 3: Commit**

```bash
git add .golangci.yml
git commit -m "chore(ci): add golangci-lint config"
```

---

## Task 7: Add GitHub Actions CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Write workflow**

Create `.github/workflows/ci.yml`:
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint-proto:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: bufbuild/buf-setup-action@v1
      - run: buf lint
      - name: Breaking check
        continue-on-error: true
        run: buf breaking --against '.git#branch=main,subdir=.'

  verify-generated:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: bufbuild/buf-setup-action@v1
      - uses: actions/setup-go@v5
        with:
          go-version: '1.22'
      - run: buf generate
      - name: Fail if generated code is stale
        run: |
          if ! git diff --exit-code -- gen/; then
            echo "gen/ is out of date — run 'buf generate' and commit"
            exit 1
          fi

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.22'
      - run: go test ./...

  lint-go:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.22'
      - uses: golangci/golangci-lint-action@v6
        with:
          version: v1.58
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "chore(ci): add GitHub Actions workflow"
```

---

## Task 8: Add GitHub issue templates

**Files:**
- Create: `.github/ISSUE_TEMPLATE/new-card.md`
- Create: `.github/ISSUE_TEMPLATE/new-primitive.md`
- Create: `.github/ISSUE_TEMPLATE/epic.md`

- [ ] **Step 1: Write `new-card.md`**

Create `.github/ISSUE_TEMPLATE/new-card.md`:
```markdown
---
name: New card
about: Implement a single Dominion card
title: "card: <Name>"
labels: area:engine, kind:card
---

## Card: <Name>

**Tier:** <0-5>
**Cost:** <int>
**Types:** <Action/Treasure/Victory/Attack/Reaction>

### Rulebook text
> <verbatim from 2nd edition rulebook>

### Primitives used
- [ ] DrawCards
- [ ] AddActions
- [ ]

### Prompts used (if any)
- [ ] DiscardFromHandPrompt
- [ ]

### Unit tests required
- [ ] Happy path
- [ ] Empty deck / empty discard
- [ ] Decision-pending guard (if applicable)
- [ ] Resource guards (Actions/Buys/Coins)
- [ ] Game-ended guard

### Definition of done
- [ ] Card file in `internal/engine/cards/`
- [ ] Registered via `init()` → `cards.Register()`
- [ ] Unit tests pass
- [ ] Included in the Tier N integration sweep
- [ ] No new engine primitives needed (or: new primitive issue linked)
```

- [ ] **Step 2: Write `new-primitive.md`**

Create `.github/ISSUE_TEMPLATE/new-primitive.md`:
```markdown
---
name: New engine primitive
about: Add or modify a pure-engine helper
title: "primitive: <Name>"
labels: area:engine, kind:primitive
---

## Primitive: <Name>

**Signature:** `func <Name>(...) ...`
**Used by:** <list of cards that will need this>

### Semantics
<one paragraph — what it does to state>

### Edge cases
<empty input? player with 0 cards? interaction with pending decision?>

### Unit tests required
- [ ] Happy path
- [ ] Empty / degenerate inputs
- [ ] Interaction with decisions (if applicable)
```

- [ ] **Step 3: Write `epic.md`**

Create `.github/ISSUE_TEMPLATE/epic.md`:
```markdown
---
name: Epic
about: Cross-cutting tracking issue
title: "epic: <Title>"
labels: kind:epic
---

## Epic: <Title>

**Phase/Tier:**
**Area:**

### Goal
<one paragraph>

### Scope (in)
-

### Scope (out)
-

### Child issues
- [ ] #

### Exit criteria
-
```

- [ ] **Step 4: Commit**

```bash
git add .github/ISSUE_TEMPLATE/
git commit -m "chore: add GitHub issue templates"
```

---

## Task 9: Engine — core types and `Card` struct

**Files:**
- Create: `internal/engine/types.go`
- Create: `internal/engine/card.go`

- [ ] **Step 1: Write `types.go`**

Create `internal/engine/types.go`:
```go
package engine

// CardID is the stable string identifier for a card definition.
type CardID string

// CardType tags a card with one or more categorical roles.
type CardType int

const (
	TypeUnknown CardType = iota
	TypeTreasure
	TypeVictory
	TypeCurse
	TypeAction
	TypeAttack
	TypeReaction
)

// Phase is the phase of the current player's turn.
type Phase int

const (
	PhaseAction Phase = iota + 1
	PhaseBuy
	PhaseCleanup
)

// GainDest says where a gained card should land.
type GainDest int

const (
	GainToDiscard GainDest = iota
	GainToHand
	GainToDeck
)
```

- [ ] **Step 2: Write `card.go`**

Create `internal/engine/card.go`:
```go
package engine

// Card is the unified definition of every card in the game. Treasures,
// victories, curses, kingdom cards all share this struct.
type Card struct {
	ID    CardID
	Name  string
	Cost  int
	Types []CardType

	// OnPlay runs when a player plays the card. Nil-safe.
	OnPlay func(s *GameState, playerIdx int) []Event

	// VictoryPoints is called at game end. Returns 0 for non-victory cards.
	VictoryPoints func(p PlayerState) int
}

// HasType reports whether c is tagged with t.
func (c *Card) HasType(t CardType) bool {
	for _, x := range c.Types {
		if x == t {
			return true
		}
	}
	return false
}
```

- [ ] **Step 3: Verify compile (types referenced below are added in Task 10 — allow this step to fail with `undefined: GameState` etc. for now, it is expected)**

```bash
go build ./internal/engine/ 2>&1 | grep -E "(GameState|PlayerState|Event)" || true
```

No assertion on exit code — this file depends on types not yet defined. They're added in the next task.

- [ ] **Step 4: Commit**

```bash
git add internal/engine/types.go internal/engine/card.go
git commit -m "feat(engine): add core types and Card struct"
```

---

## Task 10: Engine — `state.go` (GameState, PlayerState, Supply, Event)

**Files:**
- Create: `internal/engine/state.go`

- [ ] **Step 1: Write `state.go`**

Create `internal/engine/state.go`:
```go
package engine

import (
	"math/rand"
)

// GameState is the complete authoritative game state. It is the only
// input/output of the engine.
type GameState struct {
	GameID        string
	Seed          int64
	rng           *rand.Rand
	Players       []PlayerState
	CurrentPlayer int
	Phase         Phase
	Supply        Supply
	Trash         []CardID
	Turn          int
	Ended         bool
	Winners       []int

	// Tier 0 never sets this, but the plumbing exists so Tier 2 can
	// drop prompts in without restructuring state.
	PendingDecision *Decision
}

// PlayerState tracks one player's zones and resources.
type PlayerState struct {
	Name    string
	Hand    []CardID
	Deck    []CardID // top of deck = end of slice
	Discard []CardID
	InPlay  []CardID
	Actions int
	Buys    int
	Coins   int
}

// Supply tracks pile counts by card ID.
type Supply struct {
	Piles map[CardID]int
}

// Decision is a server-generated prompt. Tier 0 never sets this; the
// type exists so engine code compiles with the field declared.
type Decision struct {
	ID        string
	PlayerIdx int
}

// Event is an engine-level notification of something that happened.
// The service layer translates these into protobuf GameEvents.
type Event struct {
	Kind      EventKind
	PlayerIdx int
	CardID    CardID
	Count     int
	Phase     Phase
}

type EventKind int

const (
	EventUnknown EventKind = iota
	EventCardDrawn
	EventCardDiscarded
	EventCardPlayed
	EventCardGained
	EventCardTrashed
	EventCoinsAdded
	EventBuysAdded
	EventActionsAdded
	EventPhaseChanged
	EventTurnStarted
	EventGameEnded
)

// RNG exposes the per-game random source for code inside the engine
// package. External code must never reach the underlying field.
func (s *GameState) RNG() *rand.Rand { return s.rng }
```

- [ ] **Step 2: Verify compile**

```bash
go build ./internal/engine/
```
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add internal/engine/state.go
git commit -m "feat(engine): add GameState, PlayerState, Supply, Event"
```

---

## Task 11: Engine — action types

**Files:**
- Create: `internal/engine/action.go`

- [ ] **Step 1: Write `action.go`**

Create `internal/engine/action.go`:
```go
package engine

// Action is the engine's internal action union. The service layer
// translates protobuf actions into these before calling Apply.
type Action interface {
	isAction()
	Player() int
}

// PlayCard plays a specific card from hand.
type PlayCard struct {
	PlayerIdx int
	Card      CardID
}

func (PlayCard) isAction()    {}
func (a PlayCard) Player() int { return a.PlayerIdx }

// BuyCard buys a specific card from the supply.
type BuyCard struct {
	PlayerIdx int
	Card      CardID
}

func (BuyCard) isAction()    {}
func (a BuyCard) Player() int { return a.PlayerIdx }

// EndPhase ends the current phase (Action → Buy, or Buy → Cleanup).
// Cleanup auto-advances to the next player; EndPhase cannot be called
// during Cleanup.
type EndPhase struct {
	PlayerIdx int
}

func (EndPhase) isAction()    {}
func (a EndPhase) Player() int { return a.PlayerIdx }

// ResolveDecision answers a pending Decision. Tier 0 never uses this
// but it is in the union for shape parity with the proto Action.
type ResolveDecision struct {
	PlayerIdx  int
	DecisionID string
}

func (ResolveDecision) isAction()    {}
func (a ResolveDecision) Player() int { return a.PlayerIdx }
```

- [ ] **Step 2: Verify compile**

```bash
go build ./internal/engine/
```
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add internal/engine/action.go
git commit -m "feat(engine): add Action union"
```

---

## Task 12: Engine — RNG wrapper

**Files:**
- Create: `internal/engine/rng.go`

- [ ] **Step 1: Write `rng.go`**

Create `internal/engine/rng.go`:
```go
package engine

import "math/rand"

// shuffleCards shuffles a slice of CardID in place using the given
// per-game RNG. All shuffles in the engine must go through this
// function so game state is reproducible from seed + action log.
func shuffleCards(r *rand.Rand, cards []CardID) {
	r.Shuffle(len(cards), func(i, j int) {
		cards[i], cards[j] = cards[j], cards[i]
	})
}
```

- [ ] **Step 2: Verify compile**

```bash
go build ./internal/engine/
```
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add internal/engine/rng.go
git commit -m "feat(engine): add deterministic shuffle helper"
```

---

## Task 13: Engine primitive — `DrawCards` + `DiscardFromHand`

**Files:**
- Create: `internal/engine/primitives.go`
- Create: `internal/engine/primitives_test.go`
- Create: `internal/engine/testutil_test.go`

- [ ] **Step 1: Add testify dependency**

```bash
go get github.com/stretchr/testify@latest
go mod tidy
```

- [ ] **Step 2: Write `testutil_test.go` helpers**

Create `internal/engine/testutil_test.go`:
```go
package engine

import (
	"math/rand"
)

// newTestState builds a minimal GameState with the given per-player
// deck/discard/hand sizes. All cards are "copper" for simplicity;
// tests can overwrite fields after construction if they need more.
func newTestState(numPlayers int) *GameState {
	players := make([]PlayerState, numPlayers)
	for i := range players {
		players[i] = PlayerState{Name: "p" + string(rune('0'+i))}
	}
	return &GameState{
		GameID:        "test",
		Seed:          1,
		rng:           rand.New(rand.NewSource(1)),
		Players:       players,
		CurrentPlayer: 0,
		Phase:         PhaseAction,
		Supply:        Supply{Piles: map[CardID]int{}},
	}
}

// fillDeck pushes n copies of card onto player p's deck.
func fillDeck(s *GameState, p int, card CardID, n int) {
	for i := 0; i < n; i++ {
		s.Players[p].Deck = append(s.Players[p].Deck, card)
	}
}

// fillHand pushes n copies of card onto player p's hand.
func fillHand(s *GameState, p int, card CardID, n int) {
	for i := 0; i < n; i++ {
		s.Players[p].Hand = append(s.Players[p].Hand, card)
	}
}
```

- [ ] **Step 3: Write failing tests for DrawCards**

Create `internal/engine/primitives_test.go`:
```go
package engine

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestDrawCards_FromDeck(t *testing.T) {
	s := newTestState(1)
	fillDeck(s, 0, "copper", 5)

	events := DrawCards(s, 0, 3)

	require.Len(t, s.Players[0].Hand, 3)
	require.Len(t, s.Players[0].Deck, 2)
	require.Len(t, events, 3)
	require.Equal(t, EventCardDrawn, events[0].Kind)
}

func TestDrawCards_ReshufflesDiscardWhenDeckEmpty(t *testing.T) {
	s := newTestState(1)
	s.Players[0].Discard = []CardID{"copper", "estate", "silver"}

	events := DrawCards(s, 0, 2)

	require.Len(t, s.Players[0].Hand, 2)
	require.Len(t, s.Players[0].Discard, 0)
	require.Len(t, s.Players[0].Deck, 1)
	require.Len(t, events, 2)
}

func TestDrawCards_StopsWhenBothEmpty(t *testing.T) {
	s := newTestState(1)
	s.Players[0].Deck = []CardID{"copper"}

	events := DrawCards(s, 0, 5)

	require.Len(t, s.Players[0].Hand, 1)
	require.Len(t, events, 1)
}

func TestDiscardFromHand_MovesCardsToDiscard(t *testing.T) {
	s := newTestState(1)
	s.Players[0].Hand = []CardID{"copper", "estate", "silver"}

	events := DiscardFromHand(s, 0, []CardID{"estate", "copper"})

	require.ElementsMatch(t, []CardID{"silver"}, s.Players[0].Hand)
	require.ElementsMatch(t, []CardID{"estate", "copper"}, s.Players[0].Discard)
	require.Len(t, events, 2)
	require.Equal(t, EventCardDiscarded, events[0].Kind)
}

func TestDiscardFromHand_IgnoresCardsNotInHand(t *testing.T) {
	s := newTestState(1)
	s.Players[0].Hand = []CardID{"copper"}

	events := DiscardFromHand(s, 0, []CardID{"silver"})

	require.ElementsMatch(t, []CardID{"copper"}, s.Players[0].Hand)
	require.Len(t, s.Players[0].Discard, 0)
	require.Len(t, events, 0)
}
```

- [ ] **Step 4: Run tests to confirm they fail**

```bash
go test ./internal/engine/ -run 'TestDrawCards|TestDiscardFromHand' -v
```
Expected: FAIL with `undefined: DrawCards` / `undefined: DiscardFromHand`.

- [ ] **Step 5: Implement `primitives.go`**

Create `internal/engine/primitives.go`:
```go
package engine

// DrawCards draws up to n cards from player p's deck into their hand.
// If the deck runs out, the discard pile is shuffled and becomes the
// new deck. If both are empty, the draw stops short.
func DrawCards(s *GameState, p int, n int) []Event {
	events := make([]Event, 0, n)
	ps := &s.Players[p]
	for i := 0; i < n; i++ {
		if len(ps.Deck) == 0 {
			if len(ps.Discard) == 0 {
				return events
			}
			ps.Deck = ps.Discard
			ps.Discard = nil
			shuffleCards(s.rng, ps.Deck)
		}
		top := len(ps.Deck) - 1
		card := ps.Deck[top]
		ps.Deck = ps.Deck[:top]
		ps.Hand = append(ps.Hand, card)
		events = append(events, Event{Kind: EventCardDrawn, PlayerIdx: p, CardID: card})
	}
	return events
}

// DiscardFromHand moves the named cards from hand to discard. Cards
// not present in hand are silently skipped; the returned events reflect
// only cards that were actually moved.
func DiscardFromHand(s *GameState, p int, cards []CardID) []Event {
	ps := &s.Players[p]
	var events []Event
	for _, c := range cards {
		idx := indexOf(ps.Hand, c)
		if idx < 0 {
			continue
		}
		ps.Hand = append(ps.Hand[:idx], ps.Hand[idx+1:]...)
		ps.Discard = append(ps.Discard, c)
		events = append(events, Event{Kind: EventCardDiscarded, PlayerIdx: p, CardID: c})
	}
	return events
}

// indexOf returns the index of the first occurrence of c in cards, or
// -1 if not present.
func indexOf(cards []CardID, c CardID) int {
	for i, x := range cards {
		if x == c {
			return i
		}
	}
	return -1
}
```

- [ ] **Step 6: Run tests to confirm they pass**

```bash
go test ./internal/engine/ -run 'TestDrawCards|TestDiscardFromHand' -v
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add internal/engine/primitives.go internal/engine/primitives_test.go internal/engine/testutil_test.go go.mod go.sum
git commit -m "feat(engine): add DrawCards and DiscardFromHand primitives"
```

---

## Task 14: Engine primitive — `AddCoins` / `AddBuys` / `AddActions`

**Files:**
- Modify: `internal/engine/primitives.go`
- Modify: `internal/engine/primitives_test.go`

- [ ] **Step 1: Append failing tests**

Append to `internal/engine/primitives_test.go`:
```go
func TestAddCoins(t *testing.T) {
	s := newTestState(1)
	events := AddCoins(s, 0, 3)
	require.Equal(t, 3, s.Players[0].Coins)
	require.Len(t, events, 1)
	require.Equal(t, EventCoinsAdded, events[0].Kind)
	require.Equal(t, 3, events[0].Count)
}

func TestAddBuys(t *testing.T) {
	s := newTestState(1)
	s.Players[0].Buys = 1
	events := AddBuys(s, 0, 2)
	require.Equal(t, 3, s.Players[0].Buys)
	require.Len(t, events, 1)
	require.Equal(t, EventBuysAdded, events[0].Kind)
}

func TestAddActions(t *testing.T) {
	s := newTestState(1)
	events := AddActions(s, 0, 2)
	require.Equal(t, 2, s.Players[0].Actions)
	require.Len(t, events, 1)
	require.Equal(t, EventActionsAdded, events[0].Kind)
}
```

- [ ] **Step 2: Run tests to see failure**

```bash
go test ./internal/engine/ -run 'TestAdd' -v
```
Expected: FAIL with `undefined: AddCoins` etc.

- [ ] **Step 3: Append implementations to `primitives.go`**

Append to `internal/engine/primitives.go`:
```go

// AddCoins adds n to the player's Coins total and emits one event.
func AddCoins(s *GameState, p int, n int) []Event {
	s.Players[p].Coins += n
	return []Event{{Kind: EventCoinsAdded, PlayerIdx: p, Count: n}}
}

// AddBuys adds n to the player's Buys total and emits one event.
func AddBuys(s *GameState, p int, n int) []Event {
	s.Players[p].Buys += n
	return []Event{{Kind: EventBuysAdded, PlayerIdx: p, Count: n}}
}

// AddActions adds n to the player's Actions total and emits one event.
func AddActions(s *GameState, p int, n int) []Event {
	s.Players[p].Actions += n
	return []Event{{Kind: EventActionsAdded, PlayerIdx: p, Count: n}}
}
```

- [ ] **Step 4: Run tests to confirm green**

```bash
go test ./internal/engine/ -run 'TestAdd' -v
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/engine/primitives.go internal/engine/primitives_test.go
git commit -m "feat(engine): add AddCoins, AddBuys, AddActions primitives"
```

---

## Task 15: Engine primitive — `GainCard`

**Files:**
- Modify: `internal/engine/primitives.go`
- Modify: `internal/engine/primitives_test.go`

- [ ] **Step 1: Append failing tests**

Append to `internal/engine/primitives_test.go`:
```go
func TestGainCard_ToDiscard(t *testing.T) {
	s := newTestState(1)
	s.Supply.Piles["silver"] = 40

	events := GainCard(s, 0, "silver", GainToDiscard)

	require.Equal(t, 39, s.Supply.Piles["silver"])
	require.Equal(t, []CardID{"silver"}, s.Players[0].Discard)
	require.Len(t, events, 1)
	require.Equal(t, EventCardGained, events[0].Kind)
}

func TestGainCard_EmptyPileReturnsNoEvent(t *testing.T) {
	s := newTestState(1)
	s.Supply.Piles["province"] = 0

	events := GainCard(s, 0, "province", GainToDiscard)

	require.Empty(t, s.Players[0].Discard)
	require.Empty(t, events)
	require.Equal(t, 0, s.Supply.Piles["province"])
}

func TestGainCard_ToHand(t *testing.T) {
	s := newTestState(1)
	s.Supply.Piles["gold"] = 30

	events := GainCard(s, 0, "gold", GainToHand)

	require.Equal(t, []CardID{"gold"}, s.Players[0].Hand)
	require.Len(t, events, 1)
}
```

- [ ] **Step 2: Run tests to see failure**

```bash
go test ./internal/engine/ -run 'TestGainCard' -v
```
Expected: FAIL with `undefined: GainCard`.

- [ ] **Step 3: Append implementation**

Append to `internal/engine/primitives.go`:
```go

// GainCard gains one copy of card from the supply to the given destination
// for player p. If the supply pile is empty, nothing happens and no event
// is emitted.
func GainCard(s *GameState, p int, card CardID, dest GainDest) []Event {
	if s.Supply.Piles[card] <= 0 {
		return nil
	}
	s.Supply.Piles[card]--
	ps := &s.Players[p]
	switch dest {
	case GainToHand:
		ps.Hand = append(ps.Hand, card)
	case GainToDeck:
		ps.Deck = append(ps.Deck, card)
	default:
		ps.Discard = append(ps.Discard, card)
	}
	return []Event{{Kind: EventCardGained, PlayerIdx: p, CardID: card}}
}
```

- [ ] **Step 4: Run to confirm green**

```bash
go test ./internal/engine/ -run 'TestGainCard' -v
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/engine/primitives.go internal/engine/primitives_test.go
git commit -m "feat(engine): add GainCard primitive"
```

---

## Task 16: Engine — card registry

**Files:**
- Create: `internal/engine/cards/registry.go`
- Create: `internal/engine/cards/registry_test.go`

- [ ] **Step 1: Write failing test**

Create `internal/engine/cards/registry_test.go`:
```go
package cards

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/tie/dominion-grpc/internal/engine"
)

func TestRegister_And_Lookup(t *testing.T) {
	reg := NewRegistry()
	c := &engine.Card{ID: "smithy", Name: "Smithy", Cost: 4}
	reg.Register(c)

	got, ok := reg.Lookup("smithy")
	require.True(t, ok)
	require.Same(t, c, got)
}

func TestRegister_DuplicatePanics(t *testing.T) {
	reg := NewRegistry()
	reg.Register(&engine.Card{ID: "copper"})
	require.Panics(t, func() {
		reg.Register(&engine.Card{ID: "copper"})
	})
}

func TestLookup_MissingReturnsFalse(t *testing.T) {
	reg := NewRegistry()
	_, ok := reg.Lookup("nope")
	require.False(t, ok)
}

func TestAll_ReturnsAllRegisteredCards(t *testing.T) {
	reg := NewRegistry()
	reg.Register(&engine.Card{ID: "copper"})
	reg.Register(&engine.Card{ID: "silver"})
	require.Len(t, reg.All(), 2)
}
```

- [ ] **Step 2: Run to see failure**

```bash
go test ./internal/engine/cards/ -v
```
Expected: FAIL with `undefined: NewRegistry`.

- [ ] **Step 3: Implement registry**

Create `internal/engine/cards/registry.go`:
```go
package cards

import (
	"fmt"

	"github.com/tie/dominion-grpc/internal/engine"
)

// Registry holds card definitions by ID. It is not safe for concurrent
// registration — all cards should be registered at package init time
// from a single goroutine.
type Registry struct {
	byID map[engine.CardID]*engine.Card
}

// NewRegistry returns an empty Registry.
func NewRegistry() *Registry {
	return &Registry{byID: map[engine.CardID]*engine.Card{}}
}

// Register adds c to the registry. Panics if c.ID is already present.
func (r *Registry) Register(c *engine.Card) {
	if _, exists := r.byID[c.ID]; exists {
		panic(fmt.Sprintf("dominion: duplicate card ID %q", c.ID))
	}
	r.byID[c.ID] = c
}

// Lookup returns the card for the given ID, if any.
func (r *Registry) Lookup(id engine.CardID) (*engine.Card, bool) {
	c, ok := r.byID[id]
	return c, ok
}

// All returns every registered card in an unspecified order.
func (r *Registry) All() []*engine.Card {
	out := make([]*engine.Card, 0, len(r.byID))
	for _, c := range r.byID {
		out = append(out, c)
	}
	return out
}
```

- [ ] **Step 4: Run to confirm green**

```bash
go test ./internal/engine/cards/ -v
```
Expected: PASS (all 4 tests).

- [ ] **Step 5: Commit**

```bash
git add internal/engine/cards/
git commit -m "feat(engine): add card registry"
```

---

## Task 17: Engine cards — Copper / Silver / Gold (treasures)

**Files:**
- Create: `internal/engine/cards/basics_treasure.go`
- Create: `internal/engine/cards/basics_treasure_test.go`

- [ ] **Step 1: Write failing test**

Create `internal/engine/cards/basics_treasure_test.go`:
```go
package cards

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/tie/dominion-grpc/internal/engine"
)

func TestCopper_OnPlay_AddsOneCoin(t *testing.T) {
	s := newTestStateForCards(1)
	events := Copper.OnPlay(s, 0)
	require.Equal(t, 1, s.Players[0].Coins)
	require.Len(t, events, 1)
}

func TestSilver_OnPlay_AddsTwoCoins(t *testing.T) {
	s := newTestStateForCards(1)
	events := Silver.OnPlay(s, 0)
	require.Equal(t, 2, s.Players[0].Coins)
	require.Len(t, events, 1)
}

func TestGold_OnPlay_AddsThreeCoins(t *testing.T) {
	s := newTestStateForCards(1)
	events := Gold.OnPlay(s, 0)
	require.Equal(t, 3, s.Players[0].Coins)
	require.Len(t, events, 1)
}

func TestTreasures_HaveCorrectMetadata(t *testing.T) {
	cases := []struct {
		card     *engine.Card
		wantName string
		wantCost int
	}{
		{Copper, "Copper", 0},
		{Silver, "Silver", 3},
		{Gold, "Gold", 6},
	}
	for _, tc := range cases {
		require.Equal(t, tc.wantName, tc.card.Name)
		require.Equal(t, tc.wantCost, tc.card.Cost)
		require.True(t, tc.card.HasType(engine.TypeTreasure))
	}
}
```

Also create a `cards`-package test helper. Append to `internal/engine/cards/registry_test.go`... wait, we need this helper in a non-`_test.go` accessible spot. Use a shared `_test.go` helper file:

Create `internal/engine/cards/testutil_test.go`:
```go
package cards

import (
	"math/rand"

	"github.com/tie/dominion-grpc/internal/engine"
)

func newTestStateForCards(numPlayers int) *engine.GameState {
	players := make([]engine.PlayerState, numPlayers)
	return &engine.GameState{
		GameID:        "test",
		Seed:          1,
		Players:       players,
		CurrentPlayer: 0,
		Phase:         engine.PhaseBuy,
		Supply:        engine.Supply{Piles: map[engine.CardID]int{}},
		// rng is not used by treasure OnPlays so we leave it nil; if a
		// card ever needs it, give it rand.New(rand.NewSource(1)).
		_testRNG: rand.New(rand.NewSource(1)),
	}
}
```

Wait — `GameState` has unexported `rng` which we can't set from outside `engine`. Amend the helper to instead use a constructor in `engine` that tests can call.

Replace the above `testutil_test.go` with:
```go
package cards

import (
	"github.com/tie/dominion-grpc/internal/engine"
)

func newTestStateForCards(numPlayers int) *engine.GameState {
	players := make([]engine.PlayerState, numPlayers)
	return &engine.GameState{
		GameID:        "test",
		Seed:          1,
		Players:       players,
		CurrentPlayer: 0,
		Phase:         engine.PhaseBuy,
		Supply:        engine.Supply{Piles: map[engine.CardID]int{}},
	}
}
```

(Treasure `OnPlay` only calls `AddCoins`, which does not touch the RNG, so leaving `rng` nil is fine for these tests.)

- [ ] **Step 2: Run to see failure**

```bash
go test ./internal/engine/cards/ -v -run 'TestCopper|TestSilver|TestGold|TestTreasures'
```
Expected: FAIL with `undefined: Copper`.

- [ ] **Step 3: Implement treasures**

Create `internal/engine/cards/basics_treasure.go`:
```go
package cards

import "github.com/tie/dominion-grpc/internal/engine"

var Copper = &engine.Card{
	ID:    "copper",
	Name:  "Copper",
	Cost:  0,
	Types: []engine.CardType{engine.TypeTreasure},
	OnPlay: func(s *engine.GameState, p int) []engine.Event {
		return engine.AddCoins(s, p, 1)
	},
}

var Silver = &engine.Card{
	ID:    "silver",
	Name:  "Silver",
	Cost:  3,
	Types: []engine.CardType{engine.TypeTreasure},
	OnPlay: func(s *engine.GameState, p int) []engine.Event {
		return engine.AddCoins(s, p, 2)
	},
}

var Gold = &engine.Card{
	ID:    "gold",
	Name:  "Gold",
	Cost:  6,
	Types: []engine.CardType{engine.TypeTreasure},
	OnPlay: func(s *engine.GameState, p int) []engine.Event {
		return engine.AddCoins(s, p, 3)
	},
}

func init() {
	DefaultRegistry.Register(Copper)
	DefaultRegistry.Register(Silver)
	DefaultRegistry.Register(Gold)
}
```

And add `DefaultRegistry` to `registry.go`. Modify `internal/engine/cards/registry.go` to append at bottom:
```go

// DefaultRegistry is the package-global registry populated via init()
// by each card file. Tests that need a fresh registry should call
// NewRegistry() directly.
var DefaultRegistry = NewRegistry()
```

- [ ] **Step 4: Run to confirm green**

```bash
go test ./internal/engine/cards/ -v
```
Expected: PASS (all card tests + registry tests).

- [ ] **Step 5: Commit**

```bash
git add internal/engine/cards/
git commit -m "feat(engine): add Copper, Silver, Gold"
```

---

## Task 18: Engine cards — Estate / Duchy / Province / Curse

**Files:**
- Create: `internal/engine/cards/basics_victory.go`
- Create: `internal/engine/cards/basics_victory_test.go`

- [ ] **Step 1: Write failing tests**

Create `internal/engine/cards/basics_victory_test.go`:
```go
package cards

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/tie/dominion-grpc/internal/engine"
)

func TestEstate_VictoryPoints(t *testing.T) {
	require.Equal(t, 1, Estate.VictoryPoints(engine.PlayerState{}))
	require.Equal(t, 2, Estate.Cost)
	require.True(t, Estate.HasType(engine.TypeVictory))
}

func TestDuchy_VictoryPoints(t *testing.T) {
	require.Equal(t, 3, Duchy.VictoryPoints(engine.PlayerState{}))
	require.Equal(t, 5, Duchy.Cost)
}

func TestProvince_VictoryPoints(t *testing.T) {
	require.Equal(t, 6, Province.VictoryPoints(engine.PlayerState{}))
	require.Equal(t, 8, Province.Cost)
}

func TestCurse_NegativeVP(t *testing.T) {
	require.Equal(t, -1, Curse.VictoryPoints(engine.PlayerState{}))
	require.Equal(t, 0, Curse.Cost)
	require.True(t, Curse.HasType(engine.TypeCurse))
}

func TestVictories_HaveNoOnPlay(t *testing.T) {
	// Victories cannot be played during any phase.
	require.Nil(t, Estate.OnPlay)
	require.Nil(t, Duchy.OnPlay)
	require.Nil(t, Province.OnPlay)
	require.Nil(t, Curse.OnPlay)
}
```

- [ ] **Step 2: Run to see failure**

```bash
go test ./internal/engine/cards/ -v -run 'TestEstate|TestDuchy|TestProvince|TestCurse|TestVictories'
```
Expected: FAIL.

- [ ] **Step 3: Implement victories and curse**

Create `internal/engine/cards/basics_victory.go`:
```go
package cards

import "github.com/tie/dominion-grpc/internal/engine"

var Estate = &engine.Card{
	ID:            "estate",
	Name:          "Estate",
	Cost:          2,
	Types:         []engine.CardType{engine.TypeVictory},
	VictoryPoints: func(engine.PlayerState) int { return 1 },
}

var Duchy = &engine.Card{
	ID:            "duchy",
	Name:          "Duchy",
	Cost:          5,
	Types:         []engine.CardType{engine.TypeVictory},
	VictoryPoints: func(engine.PlayerState) int { return 3 },
}

var Province = &engine.Card{
	ID:            "province",
	Name:          "Province",
	Cost:          8,
	Types:         []engine.CardType{engine.TypeVictory},
	VictoryPoints: func(engine.PlayerState) int { return 6 },
}

var Curse = &engine.Card{
	ID:            "curse",
	Name:          "Curse",
	Cost:          0,
	Types:         []engine.CardType{engine.TypeCurse},
	VictoryPoints: func(engine.PlayerState) int { return -1 },
}

func init() {
	DefaultRegistry.Register(Estate)
	DefaultRegistry.Register(Duchy)
	DefaultRegistry.Register(Province)
	DefaultRegistry.Register(Curse)
}
```

- [ ] **Step 4: Run to confirm green**

```bash
go test ./internal/engine/cards/ -v
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/engine/cards/
git commit -m "feat(engine): add Estate, Duchy, Province, Curse"
```

---

## Task 19: Engine — initial-state builder + 2-player supply setup

**Files:**
- Create: `internal/engine/newgame.go`
- Create: `internal/engine/newgame_test.go`

- [ ] **Step 1: Write failing test**

Create `internal/engine/newgame_test.go`:
```go
package engine

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewGame_TwoPlayer_InitialDeckAndHand(t *testing.T) {
	names := []string{"Alice", "Bob"}
	lookup := func(id CardID) (*Card, bool) { return basicsLookup[id], true }

	s, err := NewGame("game-1", names, 42, lookup)
	require.NoError(t, err)

	require.Len(t, s.Players, 2)
	for i, p := range s.Players {
		require.Equalf(t, 5, len(p.Hand), "player %d should start with hand of 5", i)
		require.Equalf(t, 5, len(p.Deck), "player %d should have 5 left in deck", i)
		// 7 Coppers + 3 Estates = 10 total.
		require.Equal(t, 10, len(p.Hand)+len(p.Deck))
		countIn := func(zone []CardID, id CardID) int {
			n := 0
			for _, c := range zone {
				if c == id {
					n++
				}
			}
			return n
		}
		total := func(id CardID) int {
			return countIn(p.Hand, id) + countIn(p.Deck, id)
		}
		require.Equal(t, 7, total("copper"))
		require.Equal(t, 3, total("estate"))
	}
	require.Equal(t, PhaseAction, s.Phase)
	require.Equal(t, 0, s.CurrentPlayer)
	require.Equal(t, 1, s.Turn)
	require.Equal(t, 1, s.Players[0].Actions)
	require.Equal(t, 1, s.Players[0].Buys)
}

func TestNewGame_TwoPlayer_SupplyCounts(t *testing.T) {
	lookup := func(id CardID) (*Card, bool) { return basicsLookup[id], true }
	s, err := NewGame("game-2", []string{"A", "B"}, 1, lookup)
	require.NoError(t, err)

	// 2-player Base set counts:
	require.Equal(t, 46, s.Supply.Piles["copper"]) // 60 - 7*2
	require.Equal(t, 40, s.Supply.Piles["silver"])
	require.Equal(t, 30, s.Supply.Piles["gold"])
	require.Equal(t, 8, s.Supply.Piles["estate"]) // 14 - 3*2 = 8
	require.Equal(t, 8, s.Supply.Piles["duchy"])
	require.Equal(t, 8, s.Supply.Piles["province"])
	require.Equal(t, 10, s.Supply.Piles["curse"])
}

// Minimal card table used only for these tests. The cards package
// registry is used in integration tests; here we want a dep-free table.
var basicsLookup = map[CardID]*Card{
	"copper":   {ID: "copper", Name: "Copper", Cost: 0, Types: []CardType{TypeTreasure}},
	"silver":   {ID: "silver", Name: "Silver", Cost: 3, Types: []CardType{TypeTreasure}},
	"gold":     {ID: "gold", Name: "Gold", Cost: 6, Types: []CardType{TypeTreasure}},
	"estate":   {ID: "estate", Name: "Estate", Cost: 2, Types: []CardType{TypeVictory}},
	"duchy":    {ID: "duchy", Name: "Duchy", Cost: 5, Types: []CardType{TypeVictory}},
	"province": {ID: "province", Name: "Province", Cost: 8, Types: []CardType{TypeVictory}},
	"curse":    {ID: "curse", Name: "Curse", Cost: 0, Types: []CardType{TypeCurse}},
}
```

- [ ] **Step 2: Run to see failure**

```bash
go test ./internal/engine/ -run TestNewGame -v
```
Expected: FAIL (`undefined: NewGame`).

- [ ] **Step 3: Implement `newgame.go`**

Create `internal/engine/newgame.go`:
```go
package engine

import (
	"fmt"
	"math/rand"
)

// CardLookup is how engine code fetches card definitions without
// importing the cards package (which would create an import cycle).
type CardLookup func(CardID) (*Card, bool)

// NewGame builds the initial state for a 2-player Tier 0 Base game.
// Each player gets 7 Coppers + 3 Estates shuffled into deck+hand,
// draws 5, and the supply is filled to Base-set 2-player counts.
func NewGame(gameID string, playerNames []string, seed int64, lookup CardLookup) (*GameState, error) {
	if len(playerNames) != 2 {
		return nil, fmt.Errorf("newgame: expected 2 players, got %d", len(playerNames))
	}
	s := &GameState{
		GameID:        gameID,
		Seed:          seed,
		rng:           rand.New(rand.NewSource(seed)),
		CurrentPlayer: 0,
		Phase:         PhaseAction,
		Turn:          1,
		Supply:        Supply{Piles: map[CardID]int{}},
	}
	s.Players = make([]PlayerState, len(playerNames))
	for i, name := range playerNames {
		s.Players[i] = PlayerState{Name: name}
		// 7 coppers + 3 estates into deck, shuffle, draw 5.
		for k := 0; k < 7; k++ {
			s.Players[i].Deck = append(s.Players[i].Deck, "copper")
		}
		for k := 0; k < 3; k++ {
			s.Players[i].Deck = append(s.Players[i].Deck, "estate")
		}
		shuffleCards(s.rng, s.Players[i].Deck)
	}

	// 2-player supply counts (Base 2nd edition).
	s.Supply.Piles = map[CardID]int{
		"copper":   60 - 7*2,
		"silver":   40,
		"gold":     30,
		"estate":   14 - 3*2,
		"duchy":    8,
		"province": 8,
		"curse":    10,
	}

	// Draw each player's opening hand.
	for i := range s.Players {
		DrawCards(s, i, 5)
	}

	// First player's Action phase resources.
	s.Players[0].Actions = 1
	s.Players[0].Buys = 1
	s.Players[0].Coins = 0

	// lookup is unused in Tier 0's initial setup but is threaded through
	// so Tier 1+ card-selection logic can use it later.
	_ = lookup
	return s, nil
}
```

- [ ] **Step 4: Run to confirm green**

```bash
go test ./internal/engine/ -run TestNewGame -v
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/engine/newgame.go internal/engine/newgame_test.go
git commit -m "feat(engine): add NewGame builder for 2-player Base"
```

---

## Task 20: Engine — phase state machine (cleanup + endTurn)

**Files:**
- Create: `internal/engine/phases.go`
- Create: `internal/engine/phases_test.go`

- [ ] **Step 1: Write failing tests**

Create `internal/engine/phases_test.go`:
```go
package engine

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestCleanupAndEndTurn_MovesInPlayAndHandToDiscard(t *testing.T) {
	s := newTestState(2)
	s.CurrentPlayer = 0
	s.Phase = PhaseCleanup
	s.Players[0].Hand = []CardID{"copper", "estate"}
	s.Players[0].InPlay = []CardID{"silver"}
	// give the next player a drawable deck so DrawCards does not panic
	fillDeck(s, 1, "copper", 10)
	fillDeck(s, 0, "copper", 10)

	events := cleanupAndEndTurn(s)

	require.Len(t, s.Players[0].Hand, 5)
	require.Len(t, s.Players[0].InPlay, 0)
	require.Contains(t, s.Players[0].Discard, CardID("estate"))
	require.Contains(t, s.Players[0].Discard, CardID("silver"))
	require.Equal(t, 1, s.CurrentPlayer)
	require.Equal(t, PhaseAction, s.Phase)
	require.Equal(t, 1, s.Players[1].Actions)
	require.Equal(t, 1, s.Players[1].Buys)
	require.Equal(t, 0, s.Players[1].Coins)
	require.NotEmpty(t, events)
}

func TestCleanupAndEndTurn_WrapsToFirstPlayerAndIncrementsTurn(t *testing.T) {
	s := newTestState(2)
	s.CurrentPlayer = 1
	s.Phase = PhaseCleanup
	s.Turn = 1
	fillDeck(s, 0, "copper", 10)
	fillDeck(s, 1, "copper", 10)

	cleanupAndEndTurn(s)

	require.Equal(t, 0, s.CurrentPlayer)
	require.Equal(t, 2, s.Turn)
}
```

- [ ] **Step 2: Run to see failure**

```bash
go test ./internal/engine/ -run TestCleanupAndEndTurn -v
```
Expected: FAIL.

- [ ] **Step 3: Implement `phases.go`**

Create `internal/engine/phases.go`:
```go
package engine

// cleanupAndEndTurn performs the cleanup phase for the current player,
// then advances to the next player's Action phase. Cleanup:
//   - discards all cards in InPlay
//   - discards all cards in Hand
//   - draws 5 new cards
// Next player's resources are reset to 1 action, 1 buy, 0 coins.
func cleanupAndEndTurn(s *GameState) []Event {
	p := s.CurrentPlayer
	var events []Event

	// Discard in-play.
	for _, c := range s.Players[p].InPlay {
		s.Players[p].Discard = append(s.Players[p].Discard, c)
		events = append(events, Event{Kind: EventCardDiscarded, PlayerIdx: p, CardID: c})
	}
	s.Players[p].InPlay = nil

	// Discard hand.
	for _, c := range s.Players[p].Hand {
		s.Players[p].Discard = append(s.Players[p].Discard, c)
		events = append(events, Event{Kind: EventCardDiscarded, PlayerIdx: p, CardID: c})
	}
	s.Players[p].Hand = nil

	// Draw 5.
	events = append(events, DrawCards(s, p, 5)...)

	// Reset resources — they only apply to the current player's turn
	// and are re-set below for the NEXT player.
	s.Players[p].Actions = 0
	s.Players[p].Buys = 0
	s.Players[p].Coins = 0

	// Advance to next player.
	next := (p + 1) % len(s.Players)
	s.CurrentPlayer = next
	if next == 0 {
		s.Turn++
	}
	s.Phase = PhaseAction
	s.Players[next].Actions = 1
	s.Players[next].Buys = 1
	s.Players[next].Coins = 0

	events = append(events,
		Event{Kind: EventPhaseChanged, PlayerIdx: next, Phase: PhaseAction},
		Event{Kind: EventTurnStarted, PlayerIdx: next, Count: s.Turn},
	)
	return events
}
```

- [ ] **Step 4: Run to confirm green**

```bash
go test ./internal/engine/ -run TestCleanupAndEndTurn -v
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/engine/phases.go internal/engine/phases_test.go
git commit -m "feat(engine): add cleanup and turn-advance logic"
```

---

## Task 21: Engine — scoring + game-end detection

**Files:**
- Create: `internal/engine/scoring.go`
- Create: `internal/engine/scoring_test.go`

- [ ] **Step 1: Write failing tests**

Create `internal/engine/scoring_test.go`:
```go
package engine

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestIsGameOver_ProvinceEmpty(t *testing.T) {
	s := newTestState(2)
	s.Supply.Piles = map[CardID]int{"province": 0, "copper": 10}
	require.True(t, IsGameOver(s))
}

func TestIsGameOver_ThreePilesEmpty(t *testing.T) {
	s := newTestState(2)
	s.Supply.Piles = map[CardID]int{
		"province": 5,
		"a":        0,
		"b":        0,
		"c":        0,
	}
	require.True(t, IsGameOver(s))
}

func TestIsGameOver_NotYet(t *testing.T) {
	s := newTestState(2)
	s.Supply.Piles = map[CardID]int{
		"province": 5,
		"a":        0,
		"b":        0,
		"c":        1,
	}
	require.False(t, IsGameOver(s))
}

func TestComputeScore_SumsVictoryCardsAcrossAllZones(t *testing.T) {
	lookup := func(id CardID) (*Card, bool) {
		switch id {
		case "estate":
			return &Card{VictoryPoints: func(PlayerState) int { return 1 }}, true
		case "province":
			return &Card{VictoryPoints: func(PlayerState) int { return 6 }}, true
		case "curse":
			return &Card{VictoryPoints: func(PlayerState) int { return -1 }}, true
		}
		return &Card{}, true
	}
	ps := PlayerState{
		Hand:    []CardID{"estate", "estate"},
		Deck:    []CardID{"province"},
		Discard: []CardID{"curse"},
		InPlay:  []CardID{"estate"},
	}
	require.Equal(t, 1+1+6-1+1, ComputeScore(ps, lookup))
}

func TestDetermineWinners_Ties(t *testing.T) {
	scores := []int{10, 10, 5}
	require.Equal(t, []int{0, 1}, DetermineWinners(scores))
}

func TestDetermineWinners_SoloWinner(t *testing.T) {
	scores := []int{5, 10, 5}
	require.Equal(t, []int{1}, DetermineWinners(scores))
}
```

- [ ] **Step 2: Run to see failure**

```bash
go test ./internal/engine/ -run 'TestIsGameOver|TestComputeScore|TestDetermineWinners' -v
```
Expected: FAIL.

- [ ] **Step 3: Implement `scoring.go`**

Create `internal/engine/scoring.go`:
```go
package engine

// IsGameOver returns true if the Province pile is empty or any three
// supply piles are empty.
func IsGameOver(s *GameState) bool {
	if s.Supply.Piles["province"] <= 0 {
		return true
	}
	empty := 0
	for _, n := range s.Supply.Piles {
		if n <= 0 {
			empty++
		}
	}
	return empty >= 3
}

// ComputeScore totals a player's victory points across every zone.
// Uses the supplied lookup to resolve VP values.
func ComputeScore(ps PlayerState, lookup CardLookup) int {
	total := 0
	add := func(zone []CardID) {
		for _, id := range zone {
			c, ok := lookup(id)
			if !ok || c.VictoryPoints == nil {
				continue
			}
			total += c.VictoryPoints(ps)
		}
	}
	add(ps.Hand)
	add(ps.Deck)
	add(ps.Discard)
	add(ps.InPlay)
	return total
}

// DetermineWinners returns the indices of all players tied for the
// highest score.
func DetermineWinners(scores []int) []int {
	best := scores[0]
	for _, s := range scores[1:] {
		if s > best {
			best = s
		}
	}
	var winners []int
	for i, s := range scores {
		if s == best {
			winners = append(winners, i)
		}
	}
	return winners
}
```

- [ ] **Step 4: Run to confirm green**

```bash
go test ./internal/engine/ -run 'TestIsGameOver|TestComputeScore|TestDetermineWinners' -v
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/engine/scoring.go internal/engine/scoring_test.go
git commit -m "feat(engine): add scoring and game-end detection"
```

---

## Task 22: Engine — `Apply` entry point

**Files:**
- Create: `internal/engine/apply.go`
- Create: `internal/engine/apply_test.go`

- [ ] **Step 1: Write failing tests**

Create `internal/engine/apply_test.go`:
```go
package engine

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func applyTestLookup(id CardID) (*Card, bool) {
	c, ok := basicsLookup[id]
	if !ok {
		return nil, false
	}
	// Treasures need an OnPlay that adds coins for Apply tests.
	switch id {
	case "copper":
		cc := *c
		cc.OnPlay = func(s *GameState, p int) []Event { return AddCoins(s, p, 1) }
		return &cc, true
	case "silver":
		cc := *c
		cc.OnPlay = func(s *GameState, p int) []Event { return AddCoins(s, p, 2) }
		return &cc, true
	case "gold":
		cc := *c
		cc.OnPlay = func(s *GameState, p int) []Event { return AddCoins(s, p, 3) }
		return &cc, true
	}
	return c, true
}

func TestApply_PlayCard_TreasureInBuyPhase(t *testing.T) {
	s, _ := NewGame("g", []string{"A", "B"}, 1, basicsLookup2)
	// Force a Copper into the current player's hand and go to Buy phase.
	s.Players[0].Hand = []CardID{"copper"}
	s.Phase = PhaseBuy

	_, events, err := Apply(s, PlayCard{PlayerIdx: 0, Card: "copper"}, applyTestLookup)
	require.NoError(t, err)
	require.Equal(t, 1, s.Players[0].Coins)
	require.Contains(t, s.Players[0].InPlay, CardID("copper"))
	require.NotContains(t, s.Players[0].Hand, CardID("copper"))
	require.NotEmpty(t, events)
}

func TestApply_PlayCard_NotMyTurnErrors(t *testing.T) {
	s, _ := NewGame("g", []string{"A", "B"}, 1, basicsLookup2)
	s.Players[1].Hand = []CardID{"copper"}
	s.Phase = PhaseBuy

	_, _, err := Apply(s, PlayCard{PlayerIdx: 1, Card: "copper"}, applyTestLookup)
	require.ErrorIs(t, err, ErrNotYourTurn)
}

func TestApply_PlayCard_WrongPhaseErrors(t *testing.T) {
	s, _ := NewGame("g", []string{"A", "B"}, 1, basicsLookup2)
	s.Players[0].Hand = []CardID{"copper"}
	// still in Action phase

	_, _, err := Apply(s, PlayCard{PlayerIdx: 0, Card: "copper"}, applyTestLookup)
	require.ErrorIs(t, err, ErrWrongPhase)
}

func TestApply_BuyCard_DeductsCoinsAndGainsToDiscard(t *testing.T) {
	s, _ := NewGame("g", []string{"A", "B"}, 1, basicsLookup2)
	s.Phase = PhaseBuy
	s.Players[0].Coins = 3
	s.Players[0].Buys = 1

	_, _, err := Apply(s, BuyCard{PlayerIdx: 0, Card: "silver"}, applyTestLookup)
	require.NoError(t, err)
	require.Equal(t, 0, s.Players[0].Coins)
	require.Equal(t, 0, s.Players[0].Buys)
	require.Contains(t, s.Players[0].Discard, CardID("silver"))
}

func TestApply_BuyCard_NotEnoughCoinsErrors(t *testing.T) {
	s, _ := NewGame("g", []string{"A", "B"}, 1, basicsLookup2)
	s.Phase = PhaseBuy
	s.Players[0].Coins = 2
	s.Players[0].Buys = 1

	_, _, err := Apply(s, BuyCard{PlayerIdx: 0, Card: "silver"}, applyTestLookup)
	require.ErrorIs(t, err, ErrInsufficientCoins)
}

func TestApply_EndPhase_ActionToBuy(t *testing.T) {
	s, _ := NewGame("g", []string{"A", "B"}, 1, basicsLookup2)

	_, _, err := Apply(s, EndPhase{PlayerIdx: 0}, applyTestLookup)
	require.NoError(t, err)
	require.Equal(t, PhaseBuy, s.Phase)
	require.Equal(t, 0, s.CurrentPlayer) // still player 0
}

func TestApply_EndPhase_BuyToNextPlayer(t *testing.T) {
	s, _ := NewGame("g", []string{"A", "B"}, 1, basicsLookup2)
	s.Phase = PhaseBuy

	_, _, err := Apply(s, EndPhase{PlayerIdx: 0}, applyTestLookup)
	require.NoError(t, err)
	require.Equal(t, PhaseAction, s.Phase)
	require.Equal(t, 1, s.CurrentPlayer)
}

func TestApply_EndPhase_GameEndsAfterBuyIfProvinceGone(t *testing.T) {
	s, _ := NewGame("g", []string{"A", "B"}, 1, basicsLookup2)
	s.Phase = PhaseBuy
	s.Supply.Piles["province"] = 0

	_, _, err := Apply(s, EndPhase{PlayerIdx: 0}, applyTestLookup)
	require.NoError(t, err)
	require.True(t, s.Ended)
}

// basicsLookup2 returns cards with OnPlay attached so Apply works.
func basicsLookup2(id CardID) (*Card, bool) { return applyTestLookup(id) }
```

- [ ] **Step 2: Run to see failure**

```bash
go test ./internal/engine/ -run TestApply -v
```
Expected: FAIL.

- [ ] **Step 3: Implement `apply.go`**

Create `internal/engine/apply.go`:
```go
package engine

import "errors"

var (
	ErrNotYourTurn       = errors.New("engine: not your turn")
	ErrWrongPhase        = errors.New("engine: wrong phase for this action")
	ErrCardNotInHand     = errors.New("engine: card not in hand")
	ErrCardNotInSupply   = errors.New("engine: card not in supply")
	ErrInsufficientCoins = errors.New("engine: insufficient coins")
	ErrNoBuys            = errors.New("engine: no buys remaining")
	ErrNoActions         = errors.New("engine: no actions remaining")
	ErrUnknownCard       = errors.New("engine: unknown card")
	ErrGameEnded         = errors.New("engine: game has ended")
	ErrUnknownAction     = errors.New("engine: unknown action type")
)

// Apply is the engine's only entry point. It mutates s in place and
// returns the events that resulted. On an illegal action it returns an
// error and leaves s in a consistent pre-action state (because the
// handlers validate before mutating).
func Apply(s *GameState, a Action, lookup CardLookup) (*GameState, []Event, error) {
	if s.Ended {
		return s, nil, ErrGameEnded
	}
	if a.Player() != s.CurrentPlayer {
		return s, nil, ErrNotYourTurn
	}
	switch act := a.(type) {
	case PlayCard:
		ev, err := applyPlayCard(s, act, lookup)
		return s, ev, err
	case BuyCard:
		ev, err := applyBuyCard(s, act, lookup)
		return s, ev, err
	case EndPhase:
		ev, err := applyEndPhase(s, lookup)
		return s, ev, err
	case ResolveDecision:
		return s, nil, ErrUnknownAction // Tier 2 adds this path
	default:
		return s, nil, ErrUnknownAction
	}
}

func applyPlayCard(s *GameState, a PlayCard, lookup CardLookup) ([]Event, error) {
	card, ok := lookup(a.Card)
	if !ok {
		return nil, ErrUnknownCard
	}
	if indexOf(s.Players[a.PlayerIdx].Hand, a.Card) < 0 {
		return nil, ErrCardNotInHand
	}
	// In the Action phase, only action cards may be played, and only
	// if the player has actions available. In the Buy phase, only
	// treasures may be played.
	switch s.Phase {
	case PhaseAction:
		if !card.HasType(TypeAction) {
			return nil, ErrWrongPhase
		}
		if s.Players[a.PlayerIdx].Actions <= 0 {
			return nil, ErrNoActions
		}
		s.Players[a.PlayerIdx].Actions--
	case PhaseBuy:
		if !card.HasType(TypeTreasure) {
			return nil, ErrWrongPhase
		}
	default:
		return nil, ErrWrongPhase
	}
	// Move the card from hand to in-play.
	idx := indexOf(s.Players[a.PlayerIdx].Hand, a.Card)
	s.Players[a.PlayerIdx].Hand = append(s.Players[a.PlayerIdx].Hand[:idx], s.Players[a.PlayerIdx].Hand[idx+1:]...)
	s.Players[a.PlayerIdx].InPlay = append(s.Players[a.PlayerIdx].InPlay, a.Card)
	events := []Event{{Kind: EventCardPlayed, PlayerIdx: a.PlayerIdx, CardID: a.Card}}
	if card.OnPlay != nil {
		events = append(events, card.OnPlay(s, a.PlayerIdx)...)
	}
	return events, nil
}

func applyBuyCard(s *GameState, a BuyCard, lookup CardLookup) ([]Event, error) {
	if s.Phase != PhaseBuy {
		return nil, ErrWrongPhase
	}
	card, ok := lookup(a.Card)
	if !ok {
		return nil, ErrUnknownCard
	}
	if s.Supply.Piles[a.Card] <= 0 {
		return nil, ErrCardNotInSupply
	}
	if s.Players[a.PlayerIdx].Buys <= 0 {
		return nil, ErrNoBuys
	}
	if s.Players[a.PlayerIdx].Coins < card.Cost {
		return nil, ErrInsufficientCoins
	}
	s.Players[a.PlayerIdx].Coins -= card.Cost
	s.Players[a.PlayerIdx].Buys--
	events := GainCard(s, a.PlayerIdx, a.Card, GainToDiscard)
	return events, nil
}

func applyEndPhase(s *GameState, lookup CardLookup) ([]Event, error) {
	switch s.Phase {
	case PhaseAction:
		s.Phase = PhaseBuy
		return []Event{{Kind: EventPhaseChanged, PlayerIdx: s.CurrentPlayer, Phase: PhaseBuy}}, nil
	case PhaseBuy:
		// Cleanup + advance turn.
		s.Phase = PhaseCleanup
		events := cleanupAndEndTurn(s)
		// Check game-over AFTER the buy concluded (which is where piles
		// actually emptied) and BEFORE the new player starts acting.
		if IsGameOver(s) {
			s.Ended = true
			scores := make([]int, len(s.Players))
			for i, p := range s.Players {
				scores[i] = ComputeScore(p, lookup)
			}
			s.Winners = DetermineWinners(scores)
			events = append(events, Event{Kind: EventGameEnded})
		}
		return events, nil
	default:
		return nil, ErrWrongPhase
	}
}
```

- [ ] **Step 4: Run to confirm green**

```bash
go test ./internal/engine/ -run TestApply -v
```
Expected: PASS (all 8 tests).

- [ ] **Step 5: Run full engine test suite**

```bash
go test ./internal/engine/... -v
```
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add internal/engine/apply.go internal/engine/apply_test.go
git commit -m "feat(engine): add Apply entry point with PlayCard/BuyCard/EndPhase"
```

---

## Task 23: Engine — card-conservation property test (500 seeds)

**Files:**
- Create: `internal/engine/properties_test.go`

- [ ] **Step 1: Write the property test**

Create `internal/engine/properties_test.go`:
```go
package engine

import (
	"testing"

	"github.com/stretchr/testify/require"
)

// totalCards returns the sum of all cards in the game across every
// zone. It should be invariant under any legal action.
func totalCards(s *GameState) int {
	total := len(s.Trash)
	for _, p := range s.Players {
		total += len(p.Hand) + len(p.Deck) + len(p.Discard) + len(p.InPlay)
	}
	for _, n := range s.Supply.Piles {
		total += n
	}
	return total
}

// randomLegalAction picks a simple legal action for the current player.
// It prefers playing treasures in buy phase, buying a silver if possible,
// and otherwise ending the phase.
func randomLegalAction(s *GameState) Action {
	me := s.CurrentPlayer
	switch s.Phase {
	case PhaseAction:
		return EndPhase{PlayerIdx: me}
	case PhaseBuy:
		for _, c := range s.Players[me].Hand {
			if c == "copper" || c == "silver" || c == "gold" {
				return PlayCard{PlayerIdx: me, Card: c}
			}
		}
		if s.Players[me].Coins >= 8 && s.Supply.Piles["province"] > 0 {
			return BuyCard{PlayerIdx: me, Card: "province"}
		}
		if s.Players[me].Coins >= 6 && s.Supply.Piles["gold"] > 0 {
			return BuyCard{PlayerIdx: me, Card: "gold"}
		}
		if s.Players[me].Coins >= 3 && s.Supply.Piles["silver"] > 0 {
			return BuyCard{PlayerIdx: me, Card: "silver"}
		}
		return EndPhase{PlayerIdx: me}
	}
	return EndPhase{PlayerIdx: me}
}

func TestProperty_CardConservation(t *testing.T) {
	if testing.Short() {
		t.Skip("property sweep is skipped in short mode")
	}
	const seeds = 500
	const maxSteps = 5000
	for i := int64(0); i < seeds; i++ {
		s, err := NewGame("prop", []string{"A", "B"}, i, basicsLookup2)
		require.NoError(t, err)
		start := totalCards(s)

		for step := 0; step < maxSteps && !s.Ended; step++ {
			_, _, err := Apply(s, randomLegalAction(s), basicsLookup2)
			require.NoErrorf(t, err, "seed=%d step=%d", i, step)
		}
		require.Truef(t, s.Ended, "seed=%d did not terminate within %d steps", i, maxSteps)
		require.Equalf(t, start, totalCards(s), "seed=%d card count drifted", i)
	}
}
```

- [ ] **Step 2: Run it**

```bash
go test ./internal/engine/ -run TestProperty_CardConservation -v
```
Expected: PASS. If any seed fails, the test message identifies it — fix the underlying bug before proceeding.

- [ ] **Step 3: Commit**

```bash
git add internal/engine/properties_test.go
git commit -m "test(engine): add card-conservation property test across 500 seeds"
```

---

## Task 24: Store — in-memory game registry

**Files:**
- Create: `internal/store/memory.go`
- Create: `internal/store/memory_test.go`

- [ ] **Step 1: Write failing tests**

Create `internal/store/memory_test.go`:
```go
package store

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/tie/dominion-grpc/internal/engine"
)

func TestMemory_PutAndGet(t *testing.T) {
	m := NewMemory()
	s := &engine.GameState{GameID: "g1"}
	m.Put(s)

	got, ok := m.Get("g1")
	require.True(t, ok)
	require.Same(t, s, got)
}

func TestMemory_GetMissing(t *testing.T) {
	m := NewMemory()
	_, ok := m.Get("nope")
	require.False(t, ok)
}

func TestMemory_WithLock(t *testing.T) {
	m := NewMemory()
	m.Put(&engine.GameState{GameID: "g", Turn: 0})

	err := m.WithLock("g", func(s *engine.GameState) error {
		s.Turn = 5
		return nil
	})
	require.NoError(t, err)

	got, _ := m.Get("g")
	require.Equal(t, 5, got.Turn)
}

func TestMemory_WithLock_Missing(t *testing.T) {
	m := NewMemory()
	err := m.WithLock("nope", func(*engine.GameState) error { return nil })
	require.Error(t, err)
}
```

- [ ] **Step 2: Run to see failure**

```bash
go test ./internal/store/ -v
```
Expected: FAIL.

- [ ] **Step 3: Implement `memory.go`**

Create `internal/store/memory.go`:
```go
package store

import (
	"errors"
	"sync"

	"github.com/tie/dominion-grpc/internal/engine"
)

var ErrGameNotFound = errors.New("store: game not found")

// Memory is a goroutine-safe in-memory game registry. Every mutation
// via WithLock holds a per-store mutex; reads via Get are lock-free
// (but callers must not mutate the returned state without going through
// WithLock).
type Memory struct {
	mu    sync.Mutex
	games map[string]*engine.GameState
}

// NewMemory returns an empty registry.
func NewMemory() *Memory {
	return &Memory{games: map[string]*engine.GameState{}}
}

// Put stores a new game.
func (m *Memory) Put(s *engine.GameState) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.games[s.GameID] = s
}

// Get returns the state for a game id. Callers must not mutate it.
func (m *Memory) Get(id string) (*engine.GameState, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	s, ok := m.games[id]
	return s, ok
}

// WithLock calls fn with the state for a game id, holding the registry
// mutex for the duration. fn may mutate the state.
func (m *Memory) WithLock(id string, fn func(*engine.GameState) error) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	s, ok := m.games[id]
	if !ok {
		return ErrGameNotFound
	}
	return fn(s)
}
```

- [ ] **Step 4: Run to confirm green**

```bash
go test ./internal/store/ -v
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/store/
git commit -m "feat(store): add in-memory game registry"
```

---

## Task 25: Service — translation helpers (engine ↔ proto)

**Files:**
- Create: `internal/service/translate.go`
- Create: `internal/service/translate_test.go`

- [ ] **Step 1: Write failing tests**

Create `internal/service/translate_test.go`:
```go
package service

import (
	"testing"

	"github.com/stretchr/testify/require"
	pb "github.com/tie/dominion-grpc/gen/go/dominion/v1"
	"github.com/tie/dominion-grpc/internal/engine"
)

func TestActionFromProto_PlayCard(t *testing.T) {
	pa := &pb.Action{Kind: &pb.Action_PlayCard{PlayCard: &pb.PlayCardAction{
		PlayerIdx: 0, CardId: "copper",
	}}}
	got, err := ActionFromProto(pa)
	require.NoError(t, err)
	require.Equal(t, engine.PlayCard{PlayerIdx: 0, Card: "copper"}, got)
}

func TestActionFromProto_BuyCard(t *testing.T) {
	pa := &pb.Action{Kind: &pb.Action_BuyCard{BuyCard: &pb.BuyCardAction{
		PlayerIdx: 1, CardId: "silver",
	}}}
	got, err := ActionFromProto(pa)
	require.NoError(t, err)
	require.Equal(t, engine.BuyCard{PlayerIdx: 1, Card: "silver"}, got)
}

func TestActionFromProto_EndPhase(t *testing.T) {
	pa := &pb.Action{Kind: &pb.Action_EndPhase{EndPhase: &pb.EndPhaseAction{
		PlayerIdx: 0,
	}}}
	got, err := ActionFromProto(pa)
	require.NoError(t, err)
	require.Equal(t, engine.EndPhase{PlayerIdx: 0}, got)
}

func TestSnapshotFromState_ScrubsOpponentHand(t *testing.T) {
	s := &engine.GameState{
		GameID:        "g",
		Seed:          42,
		Turn:          3,
		CurrentPlayer: 1,
		Phase:         engine.PhaseBuy,
		Players: []engine.PlayerState{
			{Name: "A", Hand: []engine.CardID{"copper", "estate"}},
			{Name: "B", Hand: []engine.CardID{"silver"}},
		},
		Supply: engine.Supply{Piles: map[engine.CardID]int{"copper": 10}},
	}
	snap := SnapshotFromState(s, /*viewer*/ 0)
	require.Equal(t, "g", snap.GameId)
	require.Equal(t, int32(3), snap.Turn)
	// viewer=0 sees their own hand contents...
	require.Equal(t, []string{"copper", "estate"}, snap.Players[0].Hand)
	// ...but opponent hand contents are scrubbed.
	require.Empty(t, snap.Players[1].Hand)
	require.Equal(t, int32(1), snap.Players[1].HandSize)
}
```

- [ ] **Step 2: Run to see failure**

```bash
go test ./internal/service/ -v
```
Expected: FAIL.

- [ ] **Step 3: Implement translate**

Create `internal/service/translate.go`:
```go
package service

import (
	"fmt"

	pb "github.com/tie/dominion-grpc/gen/go/dominion/v1"
	"github.com/tie/dominion-grpc/internal/engine"
)

// ActionFromProto converts a proto Action union into the engine's
// internal Action type.
func ActionFromProto(a *pb.Action) (engine.Action, error) {
	if a == nil {
		return nil, fmt.Errorf("service: nil action")
	}
	switch k := a.Kind.(type) {
	case *pb.Action_PlayCard:
		return engine.PlayCard{
			PlayerIdx: int(k.PlayCard.PlayerIdx),
			Card:      engine.CardID(k.PlayCard.CardId),
		}, nil
	case *pb.Action_BuyCard:
		return engine.BuyCard{
			PlayerIdx: int(k.BuyCard.PlayerIdx),
			Card:      engine.CardID(k.BuyCard.CardId),
		}, nil
	case *pb.Action_EndPhase:
		return engine.EndPhase{PlayerIdx: int(k.EndPhase.PlayerIdx)}, nil
	case *pb.Action_Resolve:
		return engine.ResolveDecision{
			PlayerIdx:  int(k.Resolve.PlayerIdx),
			DecisionID: k.Resolve.DecisionId,
		}, nil
	default:
		return nil, fmt.Errorf("service: unknown action kind %T", k)
	}
}

// SnapshotFromState produces a proto snapshot scrubbed to the given
// viewer. The viewer sees their own hand contents; opponents' hand
// contents are omitted (but HandSize is still reported).
func SnapshotFromState(s *engine.GameState, viewer int) *pb.GameStateSnapshot {
	snap := &pb.GameStateSnapshot{
		GameId:        s.GameID,
		Seed:          s.Seed,
		Turn:          int32(s.Turn),
		CurrentPlayer: int32(s.CurrentPlayer),
		Phase:         phaseToProto(s.Phase),
		TrashSize:     int32(len(s.Trash)),
		Ended:         s.Ended,
	}
	for i, p := range s.Players {
		pv := &pb.PlayerView{
			PlayerIdx:   int32(i),
			Name:        p.Name,
			HandSize:    int32(len(p.Hand)),
			DeckSize:    int32(len(p.Deck)),
			DiscardSize: int32(len(p.Discard)),
			InPlaySize:  int32(len(p.InPlay)),
			Actions:     int32(p.Actions),
			Buys:        int32(p.Buys),
			Coins:       int32(p.Coins),
		}
		if i == viewer {
			for _, c := range p.Hand {
				pv.Hand = append(pv.Hand, string(c))
			}
		}
		for _, c := range p.InPlay {
			pv.InPlay = append(pv.InPlay, string(c))
		}
		snap.Players = append(snap.Players, pv)
	}
	for id, n := range s.Supply.Piles {
		snap.Supply = append(snap.Supply, &pb.SupplyPile{
			CardId: string(id),
			Count:  int32(n),
		})
	}
	for _, w := range s.Winners {
		snap.Winners = append(snap.Winners, int32(w))
	}
	return snap
}

func phaseToProto(p engine.Phase) pb.Phase {
	switch p {
	case engine.PhaseAction:
		return pb.Phase_PHASE_ACTION
	case engine.PhaseBuy:
		return pb.Phase_PHASE_BUY
	case engine.PhaseCleanup:
		return pb.Phase_PHASE_CLEANUP
	}
	return pb.Phase_PHASE_UNSPECIFIED
}
```

- [ ] **Step 4: Run to confirm green**

```bash
go test ./internal/service/ -v
```
Expected: PASS (all 4 tests).

- [ ] **Step 5: Commit**

```bash
git add internal/service/translate.go internal/service/translate_test.go
git commit -m "feat(service): add engine↔proto translation helpers"
```

---

## Task 26: Service — `CreateGame` + `SubmitAction` handlers

**Files:**
- Create: `internal/service/game_service.go`
- Create: `internal/service/game_service_test.go`

- [ ] **Step 1: Write failing tests**

Create `internal/service/game_service_test.go`:
```go
package service

import (
	"context"
	"testing"

	"connectrpc.com/connect"
	"github.com/stretchr/testify/require"
	pb "github.com/tie/dominion-grpc/gen/go/dominion/v1"
	"github.com/tie/dominion-grpc/internal/engine"
	"github.com/tie/dominion-grpc/internal/engine/cards"
	"github.com/tie/dominion-grpc/internal/store"
)

func newTestService() *GameService {
	return NewGameService(
		store.NewMemory(),
		func(id engine.CardID) (*engine.Card, bool) {
			return cards.DefaultRegistry.Lookup(id)
		},
	)
}

func TestGameService_CreateGame(t *testing.T) {
	svc := newTestService()
	ctx := context.Background()

	resp, err := svc.CreateGame(ctx, connect.NewRequest(&pb.CreateGameRequest{
		Players: []string{"alice", "bob"},
		Seed:    42,
	}))
	require.NoError(t, err)
	require.NotEmpty(t, resp.Msg.GameId)
	require.NotNil(t, resp.Msg.Snapshot)
	require.Equal(t, pb.Phase_PHASE_ACTION, resp.Msg.Snapshot.Phase)
}

func TestGameService_SubmitAction_EndPhaseActionToBuy(t *testing.T) {
	svc := newTestService()
	ctx := context.Background()

	create, _ := svc.CreateGame(ctx, connect.NewRequest(&pb.CreateGameRequest{
		Players: []string{"a", "b"}, Seed: 1,
	}))

	_, err := svc.SubmitAction(ctx, connect.NewRequest(&pb.SubmitActionRequest{
		GameId: create.Msg.GameId,
		Action: &pb.Action{Kind: &pb.Action_EndPhase{EndPhase: &pb.EndPhaseAction{PlayerIdx: 0}}},
	}))
	require.NoError(t, err)

	// Verify state advanced.
	s, ok := svc.store.Get(create.Msg.GameId)
	require.True(t, ok)
	require.Equal(t, engine.PhaseBuy, s.Phase)
}

func TestGameService_SubmitAction_UnknownGameReturnsNotFound(t *testing.T) {
	svc := newTestService()
	_, err := svc.SubmitAction(context.Background(), connect.NewRequest(&pb.SubmitActionRequest{
		GameId: "nope",
		Action: &pb.Action{Kind: &pb.Action_EndPhase{EndPhase: &pb.EndPhaseAction{PlayerIdx: 0}}},
	}))
	require.Error(t, err)
	var ce *connect.Error
	require.ErrorAs(t, err, &ce)
	require.Equal(t, connect.CodeNotFound, ce.Code())
}
```

- [ ] **Step 2: Run to see failure**

```bash
go test ./internal/service/ -run TestGameService -v
```
Expected: FAIL.

- [ ] **Step 3: Implement `game_service.go`**

Create `internal/service/game_service.go`:
```go
package service

import (
	"context"
	"errors"
	"sync"

	"connectrpc.com/connect"
	"github.com/google/uuid"
	pb "github.com/tie/dominion-grpc/gen/go/dominion/v1"
	"github.com/tie/dominion-grpc/internal/engine"
	"github.com/tie/dominion-grpc/internal/store"
)

// GameService implements the Connect GameServiceHandler interface.
type GameService struct {
	store  *store.Memory
	lookup engine.CardLookup

	subsMu sync.Mutex
	// subs maps game id -> slice of subscriber channels. Each
	// StreamGameEvents call appends one channel; SubmitAction fans out
	// events to every channel for that game.
	subs map[string][]chan *pb.GameEvent
	// seq is the per-game monotonic event sequence counter.
	seq map[string]uint64
}

// NewGameService constructs a service backed by the given store and
// card lookup.
func NewGameService(s *store.Memory, lookup engine.CardLookup) *GameService {
	return &GameService{
		store:  s,
		lookup: lookup,
		subs:   map[string][]chan *pb.GameEvent{},
		seq:    map[string]uint64{},
	}
}

// CreateGame handles the CreateGame RPC.
func (g *GameService) CreateGame(ctx context.Context, req *connect.Request[pb.CreateGameRequest]) (*connect.Response[pb.CreateGameResponse], error) {
	names := req.Msg.Players
	if len(names) != 2 {
		return nil, connect.NewError(connect.CodeInvalidArgument, errors.New("expected exactly 2 players in Tier 0"))
	}
	id := uuid.NewString()
	s, err := engine.NewGame(id, names, req.Msg.Seed, g.lookup)
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}
	g.store.Put(s)
	return connect.NewResponse(&pb.CreateGameResponse{
		GameId:   id,
		Snapshot: SnapshotFromState(s, 0),
	}), nil
}

// SubmitAction handles the SubmitAction RPC.
func (g *GameService) SubmitAction(ctx context.Context, req *connect.Request[pb.SubmitActionRequest]) (*connect.Response[pb.SubmitActionResponse], error) {
	act, err := ActionFromProto(req.Msg.Action)
	if err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err)
	}
	err = g.store.WithLock(req.Msg.GameId, func(s *engine.GameState) error {
		_, events, applyErr := engine.Apply(s, act, g.lookup)
		if applyErr != nil {
			return applyErr
		}
		g.fanOut(req.Msg.GameId, s, events)
		return nil
	})
	if errors.Is(err, store.ErrGameNotFound) {
		return nil, connect.NewError(connect.CodeNotFound, err)
	}
	if err != nil {
		return nil, connect.NewError(connect.CodeFailedPrecondition, err)
	}
	return connect.NewResponse(&pb.SubmitActionResponse{}), nil
}

// fanOut translates engine events to proto events and sends them to
// every subscriber of the game. Must be called with the store mutex
// held (which it already is from WithLock).
func (g *GameService) fanOut(gameID string, s *engine.GameState, events []engine.Event) {
	g.subsMu.Lock()
	defer g.subsMu.Unlock()
	for _, ev := range events {
		g.seq[gameID]++
		pbEv := &pb.GameEvent{Sequence: g.seq[gameID]}
		switch ev.Kind {
		case engine.EventPhaseChanged:
			pbEv.Kind = &pb.GameEvent_PhaseChanged{PhaseChanged: &pb.PhaseChanged{
				NewPhase:  phaseToProto(ev.Phase),
				PlayerIdx: int32(ev.PlayerIdx),
			}}
		case engine.EventTurnStarted:
			pbEv.Kind = &pb.GameEvent_TurnStarted{TurnStarted: &pb.TurnStarted{
				Turn:      int32(ev.Count),
				PlayerIdx: int32(ev.PlayerIdx),
			}}
		case engine.EventGameEnded:
			pbEv.Kind = &pb.GameEvent_Ended{Ended: &pb.GameEnded{}}
		default:
			// For Tier 0 we use a snapshot-per-action fan-out for any
			// other event; simpler than modelling every engine event
			// type and sufficient for bot-vs-bot correctness.
			pbEv.Kind = &pb.GameEvent_Snapshot{Snapshot: SnapshotFromState(s, 0)}
		}
		for _, ch := range g.subs[gameID] {
			select {
			case ch <- pbEv:
			default:
				// Drop on slow consumer. The consumer will detect the
				// sequence gap and resubscribe, receiving a fresh
				// snapshot.
			}
		}
	}
}
```

- [ ] **Step 4: Add uuid dependency**

```bash
go get github.com/google/uuid@latest
go mod tidy
```

- [ ] **Step 5: Run tests to confirm green**

```bash
go test ./internal/service/ -v
```
Expected: PASS. `TestGameService_SubmitAction_EndPhaseActionToBuy` will pass even though the stream side is incomplete — fan-out is covered in Task 27.

- [ ] **Step 6: Commit**

```bash
git add internal/service/ go.mod go.sum
git commit -m "feat(service): add CreateGame and SubmitAction handlers"
```

---

## Task 27: Service — `StreamGameEvents` handler

**Files:**
- Modify: `internal/service/game_service.go`
- Modify: `internal/service/game_service_test.go`

- [ ] **Step 1: Append failing streaming test**

Append to `internal/service/game_service_test.go`:
```go
func TestGameService_StreamGameEvents_FirstEventIsSnapshot(t *testing.T) {
	svc := newTestService()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	create, _ := svc.CreateGame(ctx, connect.NewRequest(&pb.CreateGameRequest{
		Players: []string{"a", "b"}, Seed: 1,
	}))

	stream := &fakeServerStream{ch: make(chan *pb.GameEvent, 16)}
	go func() {
		_ = svc.StreamGameEvents(ctx, connect.NewRequest(&pb.StreamGameEventsRequest{
			GameId: create.Msg.GameId, PlayerIdx: 0,
		}), stream)
	}()

	// First event should be a snapshot.
	ev := <-stream.ch
	require.NotNil(t, ev.GetSnapshot())
	require.Equal(t, uint64(0), ev.Sequence)
}

// fakeServerStream is a minimal stand-in for connect.ServerStream[...]
// that captures sent messages onto a channel.
type fakeServerStream struct {
	ch chan *pb.GameEvent
}

func (f *fakeServerStream) Send(ev *pb.GameEvent) error {
	f.ch <- ev
	return nil
}
```

- [ ] **Step 2: Add the StreamGameEvents method**

Append to `internal/service/game_service.go`:
```go

// eventSink is the minimal interface StreamGameEvents depends on, so
// tests can inject a fake without constructing a real connect stream.
type eventSink interface {
	Send(*pb.GameEvent) error
}

// StreamGameEvents subscribes the caller to all events for a game and
// blocks until the stream ends (game ends or context cancels).
// It accepts an eventSink so tests can inject a fake; in production the
// Connect handler wraps the real server stream to satisfy it.
func (g *GameService) StreamGameEvents(ctx context.Context, req *connect.Request[pb.StreamGameEventsRequest], sink eventSink) error {
	s, ok := g.store.Get(req.Msg.GameId)
	if !ok {
		return connect.NewError(connect.CodeNotFound, errors.New("game not found"))
	}

	// Send initial snapshot as the first event with sequence 0.
	initial := &pb.GameEvent{
		Sequence: 0,
		Kind: &pb.GameEvent_Snapshot{
			Snapshot: SnapshotFromState(s, int(req.Msg.PlayerIdx)),
		},
	}
	if err := sink.Send(initial); err != nil {
		return err
	}

	// Subscribe.
	ch := make(chan *pb.GameEvent, 64)
	g.subsMu.Lock()
	g.subs[req.Msg.GameId] = append(g.subs[req.Msg.GameId], ch)
	g.subsMu.Unlock()

	defer func() {
		g.subsMu.Lock()
		defer g.subsMu.Unlock()
		subs := g.subs[req.Msg.GameId]
		for i, c := range subs {
			if c == ch {
				g.subs[req.Msg.GameId] = append(subs[:i], subs[i+1:]...)
				break
			}
		}
	}()

	for {
		select {
		case <-ctx.Done():
			return nil
		case ev := <-ch:
			if err := sink.Send(ev); err != nil {
				return err
			}
			if _, ok := ev.Kind.(*pb.GameEvent_Ended); ok {
				return nil
			}
		}
	}
}
```

- [ ] **Step 3: Wrap the eventSink for the real Connect handler**

Create `internal/service/connect_adapter.go`:
```go
package service

import (
	"context"

	"connectrpc.com/connect"
	pb "github.com/tie/dominion-grpc/gen/go/dominion/v1"
	"github.com/tie/dominion-grpc/gen/go/dominion/v1/dominionv1connect"
)

// ConnectHandler adapts GameService to the generated Connect interface.
type ConnectHandler struct {
	*GameService
}

// NewConnectHandler constructs the Connect-facing wrapper.
func NewConnectHandler(svc *GameService) dominionv1connect.GameServiceHandler {
	return &ConnectHandler{GameService: svc}
}

// StreamGameEvents wraps the underlying service method so the real
// connect.ServerStream satisfies our eventSink interface.
func (h *ConnectHandler) StreamGameEvents(ctx context.Context, req *connect.Request[pb.StreamGameEventsRequest], stream *connect.ServerStream[pb.GameEvent]) error {
	return h.GameService.StreamGameEvents(ctx, req, &connectSinkAdapter{stream: stream})
}

type connectSinkAdapter struct {
	stream *connect.ServerStream[pb.GameEvent]
}

func (a *connectSinkAdapter) Send(ev *pb.GameEvent) error { return a.stream.Send(ev) }
```

- [ ] **Step 4: Run tests**

```bash
go test ./internal/service/ -v
```
Expected: PASS. The streaming test receives the initial snapshot.

- [ ] **Step 5: Commit**

```bash
git add internal/service/
git commit -m "feat(service): add StreamGameEvents handler with fan-out"
```

---

## Task 28: `cmd/server/main.go` wiring

**Files:**
- Create: `cmd/server/main.go`

- [ ] **Step 1: Write the server entry point**

Create `cmd/server/main.go`:
```go
package main

import (
	"log"
	"net/http"

	"github.com/tie/dominion-grpc/gen/go/dominion/v1/dominionv1connect"
	"github.com/tie/dominion-grpc/internal/engine"
	"github.com/tie/dominion-grpc/internal/engine/cards"
	"github.com/tie/dominion-grpc/internal/service"
	"github.com/tie/dominion-grpc/internal/store"
)

func main() {
	lookup := func(id engine.CardID) (*engine.Card, bool) {
		return cards.DefaultRegistry.Lookup(id)
	}
	svc := service.NewGameService(store.NewMemory(), lookup)
	handler := service.NewConnectHandler(svc)

	mux := http.NewServeMux()
	path, h := dominionv1connect.NewGameServiceHandler(handler)
	mux.Handle(path, h)

	log.Println("dominion-grpc server listening on :8080")
	if err := http.ListenAndServe(":8080", h2cMux(mux)); err != nil {
		log.Fatal(err)
	}
}
```

- [ ] **Step 2: Add h2c helper**

Create `cmd/server/h2c.go`:
```go
package main

import (
	"net/http"

	"golang.org/x/net/http2"
	"golang.org/x/net/http2/h2c"
)

// h2cMux wraps the mux so it speaks HTTP/2 cleartext (required for
// Connect's grpc wire format on insecure listeners).
func h2cMux(mux *http.ServeMux) http.Handler {
	return h2c.NewHandler(mux, &http2.Server{})
}
```

- [ ] **Step 3: Fetch deps and build**

```bash
go get golang.org/x/net/http2 golang.org/x/net/http2/h2c
go mod tidy
go build ./cmd/server
```
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add cmd/server/ go.mod go.sum
git commit -m "feat(server): add cmd/server main entry point"
```

---

## Task 29: Bot — Connect client wrapper

**Files:**
- Create: `internal/bot/client.go`

- [ ] **Step 1: Write the wrapper**

Create `internal/bot/client.go`:
```go
package bot

import (
	"context"
	"net/http"

	"connectrpc.com/connect"
	pb "github.com/tie/dominion-grpc/gen/go/dominion/v1"
	"github.com/tie/dominion-grpc/gen/go/dominion/v1/dominionv1connect"
)

// Client is a thin wrapper around the generated Connect client that
// hides the request/response wrapping boilerplate.
type Client struct {
	inner dominionv1connect.GameServiceClient
}

// NewClient returns a Client talking to the given base URL.
func NewClient(baseURL string) *Client {
	return &Client{
		inner: dominionv1connect.NewGameServiceClient(http.DefaultClient, baseURL),
	}
}

// CreateGame creates a new game with the given strategy names and seed.
func (c *Client) CreateGame(ctx context.Context, players []string, seed int64) (*pb.CreateGameResponse, error) {
	resp, err := c.inner.CreateGame(ctx, connect.NewRequest(&pb.CreateGameRequest{
		Players: players, Seed: seed,
	}))
	if err != nil {
		return nil, err
	}
	return resp.Msg, nil
}

// SubmitAction sends an action and returns its response.
func (c *Client) SubmitAction(ctx context.Context, gameID string, a *pb.Action) error {
	_, err := c.inner.SubmitAction(ctx, connect.NewRequest(&pb.SubmitActionRequest{
		GameId: gameID, Action: a,
	}))
	return err
}

// Stream opens a server-streaming subscription for the given game.
type Stream struct {
	inner *connect.ServerStreamForClient[pb.GameEvent]
}

// StreamGameEvents begins subscribing.
func (c *Client) StreamGameEvents(ctx context.Context, gameID string, playerIdx int) (*Stream, error) {
	s, err := c.inner.StreamGameEvents(ctx, connect.NewRequest(&pb.StreamGameEventsRequest{
		GameId: gameID, PlayerIdx: int32(playerIdx),
	}))
	if err != nil {
		return nil, err
	}
	return &Stream{inner: s}, nil
}

// Receive returns the next event or false if the stream is closed.
func (s *Stream) Receive() (*pb.GameEvent, bool) {
	if !s.inner.Receive() {
		return nil, false
	}
	return s.inner.Msg(), true
}

// Close releases the stream.
func (s *Stream) Close() error { return s.inner.Close() }

// Err returns the terminal error, if any.
func (s *Stream) Err() error { return s.inner.Err() }
```

- [ ] **Step 2: Verify compile**

```bash
go build ./internal/bot/
```
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add internal/bot/client.go
git commit -m "feat(bot): add Connect client wrapper"
```

---

## Task 30: Bot — `ClientState` reducer

**Files:**
- Create: `internal/bot/state.go`
- Create: `internal/bot/state_test.go`

- [ ] **Step 1: Write failing tests**

Create `internal/bot/state_test.go`:
```go
package bot

import (
	"testing"

	"github.com/stretchr/testify/require"
	pb "github.com/tie/dominion-grpc/gen/go/dominion/v1"
)

func TestClientState_Apply_Snapshot(t *testing.T) {
	cs := &ClientState{Me: 0}
	ev := &pb.GameEvent{
		Sequence: 0,
		Kind: &pb.GameEvent_Snapshot{Snapshot: &pb.GameStateSnapshot{
			GameId:        "g",
			Turn:          1,
			CurrentPlayer: 0,
			Phase:         pb.Phase_PHASE_ACTION,
			Players: []*pb.PlayerView{
				{PlayerIdx: 0, Hand: []string{"copper", "copper", "copper", "estate", "estate"}},
				{PlayerIdx: 1, HandSize: 5},
			},
		}},
	}
	require.NoError(t, cs.Apply(ev))
	require.Equal(t, int32(1), cs.Snapshot.Turn)
	require.Equal(t, 0, cs.CurrentPlayer)
	require.Equal(t, pb.Phase_PHASE_ACTION, cs.Phase)
}

func TestClientState_Apply_SequenceGap(t *testing.T) {
	cs := &ClientState{Me: 0, LastSeq: 5}
	ev := &pb.GameEvent{
		Sequence: 7, // gap — expected 6
		Kind:     &pb.GameEvent_Snapshot{Snapshot: &pb.GameStateSnapshot{}},
	}
	err := cs.Apply(ev)
	require.ErrorIs(t, err, ErrSequenceGap)
}

func TestClientState_IsMyTurn(t *testing.T) {
	cs := &ClientState{Me: 0, CurrentPlayer: 0}
	require.True(t, cs.IsMyTurn())
	cs.CurrentPlayer = 1
	require.False(t, cs.IsMyTurn())
	cs.CurrentPlayer = 0
	cs.Ended = true
	require.False(t, cs.IsMyTurn())
}
```

- [ ] **Step 2: Run to see failure**

```bash
go test ./internal/bot/ -run 'TestClientState' -v
```
Expected: FAIL.

- [ ] **Step 3: Implement `state.go`**

Create `internal/bot/state.go`:
```go
package bot

import (
	"errors"

	pb "github.com/tie/dominion-grpc/gen/go/dominion/v1"
)

// ErrSequenceGap is returned by Apply when the incoming event's
// sequence number is not exactly LastSeq + 1.
var ErrSequenceGap = errors.New("bot: sequence gap — resubscribe required")

// ClientState is the bot's reduction of the event stream into a
// local view of the game.
type ClientState struct {
	Me              int
	LastSeq         uint64
	Snapshot        *pb.GameStateSnapshot
	Phase           pb.Phase
	Turn            int
	CurrentPlayer   int
	PendingDecision *pb.Decision
	DecidingPlayer  int
	Ended           bool
	Winners         []int
}

// Apply reduces one event into the client state.
func (cs *ClientState) Apply(ev *pb.GameEvent) error {
	if cs.LastSeq != 0 && ev.Sequence != cs.LastSeq+1 && ev.Sequence != 0 {
		return ErrSequenceGap
	}
	cs.LastSeq = ev.Sequence

	switch k := ev.Kind.(type) {
	case *pb.GameEvent_Snapshot:
		cs.Snapshot = k.Snapshot
		cs.Phase = k.Snapshot.Phase
		cs.Turn = int(k.Snapshot.Turn)
		cs.CurrentPlayer = int(k.Snapshot.CurrentPlayer)
		cs.PendingDecision = k.Snapshot.PendingDecision
		cs.Ended = k.Snapshot.Ended
		for _, w := range k.Snapshot.Winners {
			cs.Winners = append(cs.Winners, int(w))
		}
	case *pb.GameEvent_PhaseChanged:
		cs.Phase = k.PhaseChanged.NewPhase
	case *pb.GameEvent_TurnStarted:
		cs.Turn = int(k.TurnStarted.Turn)
		cs.CurrentPlayer = int(k.TurnStarted.PlayerIdx)
		cs.PendingDecision = nil
	case *pb.GameEvent_Decision:
		cs.PendingDecision = k.Decision.Decision
		cs.DecidingPlayer = int(k.Decision.PlayerIdx)
	case *pb.GameEvent_Ended:
		cs.Ended = true
	}
	return nil
}

// IsMyTurn reports whether it is the receiver's turn AND the game has
// not ended.
func (cs *ClientState) IsMyTurn() bool {
	return cs.CurrentPlayer == cs.Me && !cs.Ended
}

// MyPlayer returns the PlayerView for the receiver from the last snapshot.
func (cs *ClientState) MyPlayer() *pb.PlayerView {
	if cs.Snapshot == nil {
		return nil
	}
	for _, p := range cs.Snapshot.Players {
		if int(p.PlayerIdx) == cs.Me {
			return p
		}
	}
	return nil
}
```

- [ ] **Step 4: Run to confirm green**

```bash
go test ./internal/bot/ -run TestClientState -v
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/bot/state.go internal/bot/state_test.go
git commit -m "feat(bot): add ClientState reducer"
```

---

## Task 31: Bot — `Strategy` interface + `safeRefusal`

**Files:**
- Create: `internal/bot/strategy.go`

- [ ] **Step 1: Write the file**

Create `internal/bot/strategy.go`:
```go
package bot

import (
	pb "github.com/tie/dominion-grpc/gen/go/dominion/v1"
)

// Strategy decides actions for a bot.
type Strategy interface {
	Name() string
	PickAction(cs *ClientState) *pb.Action
	Resolve(cs *ClientState, d *pb.Decision) *pb.ResolveDecision
}

// endPhase is a small constructor helper used by strategies.
func endPhase(me int) *pb.Action {
	return &pb.Action{Kind: &pb.Action_EndPhase{EndPhase: &pb.EndPhaseAction{PlayerIdx: int32(me)}}}
}

// playCard is a small constructor helper used by strategies.
func playCard(me int, card string) *pb.Action {
	return &pb.Action{Kind: &pb.Action_PlayCard{PlayCard: &pb.PlayCardAction{
		PlayerIdx: int32(me), CardId: card,
	}}}
}

// buyCard is a small constructor helper used by strategies.
func buyCard(me int, card string) *pb.Action {
	return &pb.Action{Kind: &pb.Action_BuyCard{BuyCard: &pb.BuyCardAction{
		PlayerIdx: int32(me), CardId: card,
	}}}
}

// safeRefusal returns the minimum legal answer for a decision, used
// by strategies that do not know how to handle a particular prompt.
// Tier 0 never triggers a decision, so this is a stub that returns a
// ResolveDecision echoing the id with no answer. Tier 2 will expand it.
func safeRefusal(d *pb.Decision) *pb.ResolveDecision {
	return &pb.ResolveDecision{DecisionId: d.Id, PlayerIdx: d.PlayerIdx}
}
```

- [ ] **Step 2: Compile check**

```bash
go build ./internal/bot/
```
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add internal/bot/strategy.go
git commit -m "feat(bot): add Strategy interface and safeRefusal helper"
```

---

## Task 32: Bot — BigMoney strategy

**Files:**
- Create: `internal/bot/bigmoney.go`
- Create: `internal/bot/bigmoney_test.go`

- [ ] **Step 1: Write failing tests**

Create `internal/bot/bigmoney_test.go`:
```go
package bot

import (
	"testing"

	"github.com/stretchr/testify/require"
	pb "github.com/tie/dominion-grpc/gen/go/dominion/v1"
)

func csWithHand(me int, phase pb.Phase, coins int32, buys int32, hand []string) *ClientState {
	return &ClientState{
		Me:            me,
		CurrentPlayer: me,
		Phase:         phase,
		Snapshot: &pb.GameStateSnapshot{
			Phase:         phase,
			CurrentPlayer: int32(me),
			Players: []*pb.PlayerView{
				{PlayerIdx: int32(me), Hand: hand, Coins: coins, Buys: buys},
			},
		},
	}
}

func TestBigMoney_ActionPhase_EndsPhase(t *testing.T) {
	cs := csWithHand(0, pb.Phase_PHASE_ACTION, 0, 1, []string{"copper"})
	a := (BigMoney{}).PickAction(cs)
	require.NotNil(t, a.GetEndPhase())
}

func TestBigMoney_BuyPhase_PlaysTreasuresFirst(t *testing.T) {
	cs := csWithHand(0, pb.Phase_PHASE_BUY, 0, 1, []string{"estate", "copper"})
	a := (BigMoney{}).PickAction(cs)
	require.NotNil(t, a.GetPlayCard())
	require.Equal(t, "copper", a.GetPlayCard().CardId)
}

func TestBigMoney_BuyPhase_BuysProvinceAtEightCoins(t *testing.T) {
	cs := csWithHand(0, pb.Phase_PHASE_BUY, 8, 1, []string{})
	a := (BigMoney{}).PickAction(cs)
	require.NotNil(t, a.GetBuyCard())
	require.Equal(t, "province", a.GetBuyCard().CardId)
}

func TestBigMoney_BuyPhase_BuysGoldAtSixCoins(t *testing.T) {
	cs := csWithHand(0, pb.Phase_PHASE_BUY, 6, 1, []string{})
	a := (BigMoney{}).PickAction(cs)
	require.Equal(t, "gold", a.GetBuyCard().CardId)
}

func TestBigMoney_BuyPhase_BuysSilverAtThreeCoins(t *testing.T) {
	cs := csWithHand(0, pb.Phase_PHASE_BUY, 3, 1, []string{})
	a := (BigMoney{}).PickAction(cs)
	require.Equal(t, "silver", a.GetBuyCard().CardId)
}

func TestBigMoney_BuyPhase_EndsPhaseWhenBroke(t *testing.T) {
	cs := csWithHand(0, pb.Phase_PHASE_BUY, 2, 1, []string{})
	a := (BigMoney{}).PickAction(cs)
	require.NotNil(t, a.GetEndPhase())
}
```

- [ ] **Step 2: Run to see failure**

```bash
go test ./internal/bot/ -run TestBigMoney -v
```
Expected: FAIL.

- [ ] **Step 3: Implement BigMoney**

Create `internal/bot/bigmoney.go`:
```go
package bot

import (
	pb "github.com/tie/dominion-grpc/gen/go/dominion/v1"
)

// BigMoney is the canonical starter strategy: never play action cards,
// play every treasure, buy Provinces at 8+, Gold at 6+, Silver at 3+.
type BigMoney struct{}

// Name implements Strategy.
func (BigMoney) Name() string { return "bigmoney" }

// PickAction implements Strategy.
func (BigMoney) PickAction(cs *ClientState) *pb.Action {
	me := cs.MyPlayer()
	if me == nil {
		return endPhase(cs.Me)
	}
	switch cs.Phase {
	case pb.Phase_PHASE_ACTION:
		return endPhase(cs.Me)
	case pb.Phase_PHASE_BUY:
		for _, c := range me.Hand {
			if isTreasure(c) {
				return playCard(cs.Me, c)
			}
		}
		switch {
		case me.Coins >= 8:
			return buyCard(cs.Me, "province")
		case me.Coins >= 6:
			return buyCard(cs.Me, "gold")
		case me.Coins >= 3:
			return buyCard(cs.Me, "silver")
		}
		return endPhase(cs.Me)
	}
	return endPhase(cs.Me)
}

// Resolve implements Strategy.
func (BigMoney) Resolve(cs *ClientState, d *pb.Decision) *pb.ResolveDecision {
	return safeRefusal(d)
}

func isTreasure(id string) bool {
	switch id {
	case "copper", "silver", "gold":
		return true
	}
	return false
}
```

- [ ] **Step 4: Run to confirm green**

```bash
go test ./internal/bot/ -run TestBigMoney -v
```
Expected: PASS (all 6 tests).

- [ ] **Step 5: Commit**

```bash
git add internal/bot/bigmoney.go internal/bot/bigmoney_test.go
git commit -m "feat(bot): add BigMoney strategy"
```

---

## Task 33: Bot — `Run` loop

**Files:**
- Create: `internal/bot/bot.go`

- [ ] **Step 1: Write the loop**

Create `internal/bot/bot.go`:
```go
package bot

import (
	"context"
	"errors"
)

// Run drives a strategy against the given game via c until the game
// ends or ctx cancels. On sequence-gap errors it closes the stream and
// resubscribes; all other errors terminate the loop.
func Run(ctx context.Context, c *Client, gameID string, me int, strat Strategy) error {
	cs := &ClientState{Me: me}

	for {
		stream, err := c.StreamGameEvents(ctx, gameID, me)
		if err != nil {
			return err
		}
		loopErr := driveOnce(ctx, c, gameID, stream, cs, strat)
		_ = stream.Close()
		if loopErr == nil {
			return nil
		}
		if !errors.Is(loopErr, ErrSequenceGap) {
			return loopErr
		}
		// reset sequence tracking so the next stream's initial snapshot
		// (sequence 0) is accepted
		cs.LastSeq = 0
	}
}

// driveOnce drains a single subscription. Returns nil on normal end,
// ErrSequenceGap to trigger reconnection, or any other error to abort.
func driveOnce(ctx context.Context, c *Client, gameID string, stream *Stream, cs *ClientState, strat Strategy) error {
	for {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		ev, ok := stream.Receive()
		if !ok {
			return stream.Err()
		}
		if err := cs.Apply(ev); err != nil {
			return err
		}
		if cs.Ended {
			return nil
		}
		switch {
		case cs.PendingDecision != nil && cs.DecidingPlayer == cs.Me:
			resp := strat.Resolve(cs, cs.PendingDecision)
			if err := c.submitResolve(ctx, gameID, resp); err != nil {
				return err
			}
		case cs.IsMyTurn() && cs.PendingDecision == nil:
			act := strat.PickAction(cs)
			if act == nil {
				act = endPhase(cs.Me)
			}
			if err := c.SubmitAction(ctx, gameID, act); err != nil {
				return err
			}
		}
	}
}
```

- [ ] **Step 2: Add the `submitResolve` helper to `client.go`**

Modify `internal/bot/client.go`, append to the file:
```go

// submitResolve wraps the generic SubmitAction with a resolve payload.
func (c *Client) submitResolve(ctx context.Context, gameID string, r *pb.ResolveDecision) error {
	return c.SubmitAction(ctx, gameID, &pb.Action{Kind: &pb.Action_Resolve{Resolve: r}})
}
```

- [ ] **Step 3: Verify compile**

```bash
go build ./internal/bot/
```
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add internal/bot/bot.go internal/bot/client.go
git commit -m "feat(bot): add Run loop with sequence-gap reconnect"
```

---

## Task 34: `cmd/bot/main.go` CLI

**Files:**
- Create: `cmd/bot/main.go`

- [ ] **Step 1: Write the CLI**

Create `cmd/bot/main.go`:
```go
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"

	"github.com/tie/dominion-grpc/internal/bot"
)

func main() {
	server := flag.String("server", "http://localhost:8080", "Connect server base URL")
	gameID := flag.String("game", "", "game ID to join (required unless --create)")
	create := flag.Bool("create", false, "create a new bot-only game before joining")
	asPlayer := flag.Int("as-player", 0, "player index this bot plays")
	strategyName := flag.String("strategy", "bigmoney", "strategy to use (bigmoney)")
	seed := flag.Int64("seed", 1, "game seed (only used with --create)")
	flag.Parse()

	strat, err := selectStrategy(*strategyName)
	if err != nil {
		log.Fatal(err)
	}

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()

	c := bot.NewClient(*server)

	id := *gameID
	if *create {
		resp, err := c.CreateGame(ctx, []string{"bigmoney", "bigmoney"}, *seed)
		if err != nil {
			log.Fatalf("create: %v", err)
		}
		id = resp.GameId
		fmt.Printf("created game %s\n", id)
	}
	if id == "" {
		log.Fatal("--game or --create is required")
	}

	if err := bot.Run(ctx, c, id, *asPlayer, strat); err != nil {
		log.Fatalf("run: %v", err)
	}
}

func selectStrategy(name string) (bot.Strategy, error) {
	switch name {
	case "bigmoney":
		return bot.BigMoney{}, nil
	}
	return nil, fmt.Errorf("unknown strategy %q", name)
}
```

- [ ] **Step 2: Build**

```bash
go build ./cmd/bot
```
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add cmd/bot/
git commit -m "feat(bot): add cmd/bot CLI"
```

---

## Task 35: Integration test — BigMoney vs BigMoney bot-vs-bot

**Files:**
- Create: `internal/bot/integration_test.go`

- [ ] **Step 1: Write the test**

Create `internal/bot/integration_test.go`:
```go
package bot_test

import (
	"context"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"golang.org/x/net/http2"
	"golang.org/x/net/http2/h2c"
	"golang.org/x/sync/errgroup"

	"net/http"

	"github.com/tie/dominion-grpc/gen/go/dominion/v1/dominionv1connect"
	"github.com/tie/dominion-grpc/internal/bot"
	"github.com/tie/dominion-grpc/internal/engine"
	"github.com/tie/dominion-grpc/internal/engine/cards"
	"github.com/tie/dominion-grpc/internal/service"
	"github.com/tie/dominion-grpc/internal/store"
)

func newTestServer(t *testing.T) *httptest.Server {
	t.Helper()
	lookup := func(id engine.CardID) (*engine.Card, bool) {
		return cards.DefaultRegistry.Lookup(id)
	}
	svc := service.NewGameService(store.NewMemory(), lookup)
	handler := service.NewConnectHandler(svc)

	mux := http.NewServeMux()
	path, h := dominionv1connect.NewGameServiceHandler(handler)
	mux.Handle(path, h)

	srv := httptest.NewUnstartedServer(h2c.NewHandler(mux, &http2.Server{}))
	srv.EnableHTTP2 = true
	srv.Start()
	t.Cleanup(srv.Close)
	return srv
}

func TestBotVsBot_BigMoney(t *testing.T) {
	srv := newTestServer(t)

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	a := bot.NewClient(srv.URL)
	b := bot.NewClient(srv.URL)

	game, err := a.CreateGame(ctx, []string{"bigmoney", "bigmoney"}, 42)
	require.NoError(t, err)
	require.NotEmpty(t, game.GameId)

	grp, gctx := errgroup.WithContext(ctx)
	grp.Go(func() error { return bot.Run(gctx, a, game.GameId, 0, bot.BigMoney{}) })
	grp.Go(func() error { return bot.Run(gctx, b, game.GameId, 1, bot.BigMoney{}) })
	require.NoError(t, grp.Wait())
}
```

- [ ] **Step 2: Add errgroup dependency**

```bash
go get golang.org/x/sync@latest
go mod tidy
```

- [ ] **Step 3: Run the integration test**

```bash
go test ./internal/bot/ -run TestBotVsBot_BigMoney -v
```
Expected: PASS. The game terminates (Province or 3-pile game end) and both bot loops exit cleanly.

If it hangs, check the service's fan-out: every SubmitAction must produce at least one event, and the `EventGameEnded` event must actually be sent so the bots' `cs.Ended` flips to true.

- [ ] **Step 4: Run the full test suite**

```bash
go test ./...
```
Expected: every package passes.

- [ ] **Step 5: Commit**

```bash
git add internal/bot/integration_test.go go.mod go.sum
git commit -m "test(bot): add BigMoney-vs-BigMoney bot-vs-bot integration test"
```

---

## Task 36: Replay test scaffolding

**Files:**
- Create: `testdata/replays/.gitkeep`
- Create: `internal/engine/replay_test.go`

- [ ] **Step 1: Create fixture directory**

```bash
mkdir -p testdata/replays
touch testdata/replays/.gitkeep
```

- [ ] **Step 2: Write the walker**

Create `internal/engine/replay_test.go`:
```go
package engine

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

// replayFixture is the on-disk format of a replay: a seed plus a
// sequence of actions, plus the expected final outcome.
type replayFixture struct {
	Seed          int64        `json:"seed"`
	PlayerNames   []string     `json:"player_names"`
	Actions       []replayStep `json:"actions"`
	ExpectedEnded bool         `json:"expected_ended"`
	ExpectedWinners []int      `json:"expected_winners"`
}

type replayStep struct {
	Kind   string `json:"kind"` // "play" | "buy" | "end_phase"
	Player int    `json:"player"`
	Card   string `json:"card,omitempty"`
}

func (r replayStep) toAction() Action {
	switch r.Kind {
	case "play":
		return PlayCard{PlayerIdx: r.Player, Card: CardID(r.Card)}
	case "buy":
		return BuyCard{PlayerIdx: r.Player, Card: CardID(r.Card)}
	case "end_phase":
		return EndPhase{PlayerIdx: r.Player}
	}
	return nil
}

// TestReplay_RegressionFixtures runs every file under testdata/replays/.
// Empty directories are valid — the walker just finds nothing to run.
func TestReplay_RegressionFixtures(t *testing.T) {
	entries, err := filepath.Glob(filepath.Join("..", "..", "testdata", "replays", "*.json"))
	require.NoError(t, err)
	for _, path := range entries {
		path := path
		t.Run(filepath.Base(path), func(t *testing.T) {
			raw, err := os.ReadFile(path)
			require.NoError(t, err)
			var fx replayFixture
			require.NoError(t, json.Unmarshal(raw, &fx))

			s, err := NewGame("replay", fx.PlayerNames, fx.Seed, basicsLookup2)
			require.NoError(t, err)
			for i, step := range fx.Actions {
				act := step.toAction()
				require.NotNilf(t, act, "step %d has unknown kind %q", i, step.Kind)
				_, _, err := Apply(s, act, basicsLookup2)
				require.NoErrorf(t, err, "step %d (%+v)", i, step)
			}
			require.Equal(t, fx.ExpectedEnded, s.Ended)
			require.Equal(t, fx.ExpectedWinners, s.Winners)
		})
	}
}
```

- [ ] **Step 3: Run — empty directory is a valid pass**

```bash
go test ./internal/engine/ -run TestReplay_RegressionFixtures -v
```
Expected: PASS (no subtests run, overall result is OK).

- [ ] **Step 4: Commit**

```bash
git add testdata/replays/.gitkeep internal/engine/replay_test.go
git commit -m "test(engine): add replay fixture walker (empty)"
```

---

## Task 37: README + Makefile finishing touches

**Files:**
- Modify: `README.md`
- Modify: `Makefile`

- [ ] **Step 1: Update README**

Replace `README.md` with:
```markdown
# dominion-grpc

A server-authoritative Dominion implementation in Go. Connect-Go for RPC,
protobuf for the contract, pure-Go engine with zero transport awareness.

**Status:** Phase 1a / Tier 0 complete — basics + BigMoney plays end-to-end
via bot-vs-bot integration test. Kingdom cards arrive in Tier 1+.

## Build and test

    make generate       # regenerate gen/go/ from proto/
    make test           # full test suite
    make test-short     # skip the 1000-game sweep
    make lint           # buf lint + buf breaking + golangci-lint
    make server         # run Connect server on :8080
    make bot            # run the standalone bot CLI

## Playing a bot-vs-bot game manually

In one terminal:

    make server

In another:

    go run ./cmd/bot --create --seed 42 --as-player 0 --strategy bigmoney

The bot will create a game, attach as player 0, and drive BigMoney. To
play both seats as bots, open a second bot in another terminal with
`--as-player 1` and the game id printed by the first.

## Layout

    proto/               source of truth — protobuf contract
    gen/go/              generated Go stubs (committed; never hand-edit)
    cmd/server/          Connect-Go HTTP server entry point
    cmd/bot/             bot CLI entry point
    internal/engine/     pure Go game engine (no network, no protobuf)
    internal/engine/cards/ card registry and definitions
    internal/service/    Connect handlers (translation layer)
    internal/store/      in-memory game registry
    internal/bot/        bot library: state reducer, strategies, run loop
    testdata/replays/    regression fixtures (one JSON per captured bug)

## Design

The full design spec lives in the dev-env repo at
`docs/superpowers/specs/2026-04-12-dominion-grpc-design.md`, with a
newcomer-friendly Section 3 primer alongside it.
```

- [ ] **Step 2: Update Makefile**

Replace `Makefile` with:
```makefile
.PHONY: generate test test-short lint server bot install-tools tidy

generate:
	buf generate

tidy:
	go mod tidy

test:
	go test ./...

test-short:
	go test -short ./...

lint:
	buf lint
	golangci-lint run ./...

server:
	go run ./cmd/server

bot:
	go run ./cmd/bot $(ARGS)

install-tools:
	@echo "Install buf: https://buf.build/docs/installation"
	@echo "Install golangci-lint: https://golangci-lint.run/usage/install/"
```

(Note: `buf breaking` is intentionally omitted from the `lint` target until there is a base branch to compare against. CI runs it with `continue-on-error: true` for the same reason.)

- [ ] **Step 3: Run the full suite one more time**

```bash
make generate
make lint
make test
```
Expected: all three succeed.

- [ ] **Step 4: Commit**

```bash
git add README.md Makefile
git commit -m "docs: flesh out README and finalize Makefile targets"
```

---

## Plan done — what ships

At this point `dominion-grpc/` contains:

- A working Connect-Go server (`cmd/server`) that exposes `GameService` over HTTP/2.
- A pure-Go engine with basics (Copper/Silver/Gold/Estate/Duchy/Province/Curse), phase state machine, scoring, and game-end detection.
- An in-memory game registry.
- A bot library with `ClientState` reducer, `Strategy` interface, `Run` loop, and the BigMoney strategy.
- A `cmd/bot` CLI.
- Unit tests on every primitive, card, scoring rule, and apply path.
- A 500-seed card-conservation property test.
- A BigMoney-vs-BigMoney bot-vs-bot integration test using real Connect over loopback HTTP/2.
- Replay fixture scaffolding (empty).
- CI running `buf lint`, `buf generate` freshness check, `golangci-lint`, and `go test ./...` on every push.
- GitHub issue templates for new cards, new primitives, and epics.

## What's deferred to the next plans

- **Plan 2 — Tier 1 (6 cards):** Village, Smithy, Festival, Laboratory, Market, Council Room. Introduces `PhaseAction` card play (currently only EndPhase works in Action phase). Adds SmithyBM strategy.
- **Plan 3 — Tier 2 (10 cards):** decisions. Activates the `Decision` / `ResolveDecision` plumbing that Tier 0 left empty. Major additions to the bot's Resolve path.
- **Plan 4 — Tier 3 (5 cards):** attacks + the Moat reaction system.
- **Plan 5 — Tier 4 (3 cards):** Throne Room recursion, Library set-aside, Sentry three-step.
- **Plan 6 — Tier 5 (2 cards):** Gardens, Merchant. Special hooks on scoring and per-turn triggers.
- **Plan 7 — Phase 1b:** React + Vite frontend.

Each becomes its own brainstorm-and-plan cycle when you're ready.
