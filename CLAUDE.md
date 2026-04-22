# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repo topology — two nested repos

This directory is **two independent git repos**, not one:

- **Outer repo** (`/home/tie/superpower-dominion/`) — dev-env only: a distrobox
  container definition (`distrobox.ini`) and a `Makefile` that wraps distrobox
  lifecycle + tool bootstrap. It also holds `.vscode/` and a code-workspace
  file. The outer `.gitignore` excludes `/dominion-grpc/*`, `/go`, and
  `/.claude`.
- **Inner repo** (`dominion-grpc/`) — the actual Go project. Separate `.git`,
  separate history, separate `.gitignore`, separate `Makefile`. **Not a
  submodule.**

When the user refers to "the project" or "the code," they almost always mean
the inner repo. Treat `dominion-grpc/` as the working root for anything
code-related and `cd` into it for Go commands. Commit to the inner repo's
history for code changes; commit to the outer repo only for dev-env changes
(distrobox, VSCode, top-level Makefile).

## Commands

### Outer repo — distrobox lifecycle

Run from `/home/tie/superpower-dominion/`:

| Command | Purpose |
|---|---|
| `make build` | Symlink `~/.ssh` and `~/.gitconfig` into the repo, then `distrobox assemble create` |
| `make enter` / `make enter-v` | Enter the container (the `-v` variant shows verbose output) |
| `make rebuild` | `clean` then `build` |
| `make install-vscode` / `install-gh` / `install-claude` | Bootstrap tools inside the container (auto-detects apt vs dnf) |

### Inner repo — Go project

Run from `/home/tie/superpower-dominion/dominion-grpc/`:

| Command | Purpose |
|---|---|
| `make generate` | Regenerate `gen/go/` from `proto/` via `buf generate` |
| `make test` | Full suite, including the 500-seed property sweep and integration sweeps |
| `make test-short` | `go test -short ./...` — skips the long sweeps; use while iterating |
| `make lint` | `buf lint` + `golangci-lint run ./...` |
| `make server` | Run the Connect-Go server on `:8080` |
| `make bot ARGS="..."` | Run the bot CLI; forward args via `ARGS` |
| `make install-tools` | Install pinned `buf` and `golangci-lint` into `$GOPATH/bin` |

Running a single Go test: `go test ./internal/engine -run TestApplyBuyCard -v`.
Running the property/integration sweeps alone: drop `-short`, e.g.
`go test ./internal/engine -run Property -v`.

Bot-vs-bot manual smoke test (two terminals):

```
# Terminal 1
make server

# Terminal 2 — create the game as player 0 and capture the printed game id
make bot ARGS="-create -as-player 0 -seed 42"
make bot ARGS="-game <id> -as-player 1"   # as player 1
```

`buf curl --schema proto ...` works against the running server for ad-hoc
RPC probes; see `dominion-grpc/README.md` for worked examples.

## Architecture — things that span files

**Server-authoritative, protobuf-contract-first, pure-Go engine.**
Protobuf under `proto/` is the single source of truth; `gen/go/` is
committed but generated — **never hand-edit it**, regenerate via
`make generate`.

### Layer boundaries (enforced by discipline, not the compiler)

```
proto/                    ← contract
 │
 ▼ (buf generate)
gen/go/                   ← stubs; committed, never hand-edited
 │
internal/service/         ← ONLY layer that knows Connect/protobuf.
 │                          Translates pb ↔ engine types (see translate.go).
 ▼
internal/engine/          ← pure Go. No network, no protobuf, no HTTP.
 │                          Exposes one entry point: Apply(gs, action, lookup).
 └─ cards/                ← per-card OnPlay/OnResolve definitions; each card
                            file registers into DefaultRegistry via init().
internal/store/           ← in-memory game registry (sync.Mutex + map). Phase 1 only.
internal/bot/             ← bot library: ClientState reducer + Strategy interface +
                            run loop. Bots are ordinary Connect clients — same
                            API a human client would use.
cmd/server, cmd/bot/      ← thin main()s; wire the above together.
```

The invariant: `internal/engine/` must never import protobuf, Connect, or
anything HTTP. If you find yourself wanting to, the translation belongs in
`internal/service/translate.go`.

### Engine entry point

`engine.Apply(gs *GameState, act Action, lookup CardLookup) (*GameState, []Event, error)`
is the sole engine entry point. It mutates in place and returns emitted
events. Handlers validate before mutating so failures leave state
consistent.

**Decision-pending guard:** when `gs.PendingDecision != nil`, the only legal
action is `ResolveDecision` — all others return `ErrDecisionPending`. Cards
that need input call `RequestDecision` during `OnPlay`, then handle the
response in `OnResolve`. `DecisionSeq` makes decision IDs deterministic
from the seed.

### Card registry

Every card in `internal/engine/cards/*.go` registers itself into
`cards.DefaultRegistry` from an `init()` function. The engine's
`CardLookup` is a closure over that registry; `cards.NewRegistry()` gives
you a fresh one for tests. A card is "kingdom" iff it has `TypeAction`
(plain actions, attacks, reactions); treasures/victories/curses are
basics.

### Service fan-out model

`GameService` keeps `subs map[gameID][]subscriber` and a `seq` counter per
game. `SubmitAction` applies the action under the store lock, then fans
out **per-viewer scrubbed snapshots** + the events to every subscriber for
that game. Opponents' hand contents are scrubbed; only the viewing
player's own hand is populated.

Streams carry a monotonic sequence number. The bot library detects
sequence gaps (`ErrSequenceGap`), closes, and resubscribes — see
`internal/bot/bot.go`.

### Test layers

- `*_test.go` next to each file — unit tests (most of the suite).
- `internal/engine/properties_test.go` — 500-seed random-legal-action
  sweep that asserts card conservation and other invariants.
- `internal/engine/replay_test.go` — JSON replay fixtures under
  `testdata/replays/` for regression.
- `internal/bot/integration_test.go` — spins up an httptest h2c server
  and runs real bot-vs-bot games end-to-end.

`-short` skips the property sweep and the bot-vs-bot sweeps. Iterating
locally? Prefer `make test-short`. Before a commit that touches engine
or bot code, run the full `make test`.

## Project status and design docs

Status per `dominion-grpc/README.md`: **Phase 1a / Tier 0 complete** — the
seven basics plus BigMoney bot-vs-bot works end-to-end. Tiers 1 and 2
introduce kingdom cards; see the plans in
`dominion-grpc/docs/superpowers/plans/` (one plan per tier) and specs in
`dominion-grpc/docs/superpowers/specs/`. When in doubt about a design
decision (phase ordering, RPC shape, engine invariants), read those specs
before proposing structural changes.

Phase 1b (React/Vite/TS frontend over generated connect-web client) and
Phase 2 (auth, lobby, persistence) are scoped in the specs but not yet
started.
