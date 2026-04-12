# dominion-grpc — Design Spec (CHECKPOINT — IN PROGRESS)

**Status:** Brainstorming in progress. Sections 1–5 drafted and informally approved by user. Sections 6–7 still to be presented.
**Date started:** 2026-04-12
**Author of brainstorm:** Claude (Opus 4.6) with user
**Spec location note:** This file lives in the dev-env repo (`/home/tie/superpower-dominion/`). It will be moved into the future project repo (`dominion-grpc/`) once that repo is created.

---

## Resume notes (read this first when picking the session back up)

- The next thing to do is **Section 6 — Bot client design**, then **Section 7 — Testing strategy + GitHub-issue organization**.
- After Section 7, the brainstorming flow's terminal state is to invoke the `superpowers:writing-plans` skill, which produces an implementation plan that becomes the GitHub issues the user originally asked about.
- TaskList items #1–#4 in the Claude Code session track the remaining brainstorming + transition steps.
- The user is **new to protobuf and Connect**; a Tier 1/2/3 reading list was given (Proto3 guide, Buf quickstart, Connect-Go getting started, Dominion rulebook). The user may have done some of this reading before resuming.
- The user has explicitly chosen all the following decisions; do not re-litigate them on resume.

---

## Confirmed decisions (locked-in choices from the brainstorm)

| Topic | Decision |
|---|---|
| **MVP scope** | Single-player vs simple AI, all 26 Base set 2nd-edition kingdom cards, end-to-end |
| **Multiplayer** | Phased — Phase 1 single-player vs bot, Phase 2 lobby/auth/rooms, Phase 3 polish + smarter AI |
| **Backend language** | Go |
| **RPC framework** | Connect-Go (`connectrpc.com/connect`), running on stdlib `net/http`. **Not** Fiber. **Not** raw gRPC. |
| **Contract format** | Protobuf (proto3) — single source of truth |
| **Schema tooling** | `buf` CLI for `buf generate`, `buf lint`, `buf breaking` |
| **Frontend (Phase 1b)** | React + Vite + TypeScript, consuming `@connectrpc/connect-web` generated client |
| **Build order** | **Backend-first.** Phase 1a is engine + proto + Connect server + bot client + bot-vs-bot integration tests, all without any frontend. Phase 1b adds the React app on top of the proven contract. |
| **Other clients** | Future: SolidJS web client, mobile app. Designed for via sibling `clients/<name>/` directories. |
| **Repo strategy** | Monorepo for `dominion-grpc` now (proto + server + bot + clients all in one repo). BSR + extracted client repos as a planned exit when contract stabilizes. |
| **Repo separation from dev-env** | The current `/home/tie/superpower-dominion/` repo holds **dev-env only** (distrobox config, Makefile). The actual project lives in `/home/tie/superpower-dominion/dominion-grpc/`, a **separate independent git repo** (no submodule). The dev-env repo's `.gitignore` will exclude `/dominion-grpc/`. |
| **Project name** | `dominion-grpc` (user's choice; technically uses Connect, but the name is fine since Connect is gRPC-compatible) |
| **Persistence in Phase 1** | None — all game state is in-memory in a `map[GameID]*GameState` behind a mutex. Persistence arrives in Phase 2. |
| **Single-player AI for E2E testing** | A simple rule-based bot ("Big Money", later "Smithy + Big Money"). The bot is just another Connect client hitting the same API as a human player would. It is **test infrastructure AND a Phase 1 deliverable**, not a "feature." Smarter AI (MCTS, ported Dominiate strategies) is Phase 3. |

---

## Phase definitions

| Phase | Scope | Done when |
|---|---|---|
| **1a — Backend MVP** | proto contract, Go engine package, all 26 Base kingdom cards + 7 basics, Connect-Go server, bot client (Big Money), bot-vs-bot integration tests | Bot-vs-bot can play 1000 random games end-to-end without crashes or illegal states; all card-effect tests pass |
| **1b — Frontend MVP** | React + Vite + TS app, generated TS client, view layer for game state, action UI, game log | A human can play vs the bot in a browser, full Base set, end-to-end |
| **2 — Online multiplayer** | Auth, lobby, matchmaking, real game rooms, persistence layer, reconnection, turn timers, BSR for proto distribution | Two humans can find each other and play a complete game online |
| **3 — Polish + smarter AI** | Spectators, replays, account history, smarter AI opponents (MCTS or ported strategies), maybe more card sets | (out of scope for this spec) |

---

## Section 1 — Architecture overview

**Server-authoritative turn-based game.** The engine lives entirely on the server. Clients only send actions and receive state.

```
┌─────────────────┐         ┌──────────────────────────────┐
│  Web client     │         │  Go server                    │
│  (Phase 1b)     │         │                               │
│  React + Vite   │ ──RPC── │  Connect-Go handlers          │
│  connect-es     │         │       │                       │
└─────────────────┘         │       ▼                       │
                            │  Game service layer           │
┌─────────────────┐         │  (creates/looks up games,     │
│  Bot client     │         │   routes actions to engine)   │
│  (Phase 1a)     │ ──RPC── │       │                       │
│  Go             │         │       ▼                       │
│  connect-go     │         │  Engine package (pure Go)     │
└─────────────────┘         │  - turn state machine         │
                            │  - card effect primitives     │
                            │  - 26 Base set kingdom cards  │
                            │  - 7 basic cards              │
                            │                               │
                            │  In-memory game registry      │
                            └──────────────────────────────┘
```

**Key principles:**

1. **Engine package is pure Go with zero network/transport awareness.** No Connect, no protobuf, no HTTP. Takes a game state and an action, returns a new state (or an error). Heavily unit-tested.
2. **Service layer is the only thing that knows about Connect/protobuf.** Translates protobuf messages → engine actions, calls engine, translates engine state → protobuf responses.
3. **Bots and the future React client are interchangeable.** Both speak the same Connect RPCs. The server doesn't know or care which is which. This is what makes "bot for E2E testing" the same code path as "bot for AI opponent."
4. **State is in-memory in Phase 1.** A `map[GameID]*GameState` behind a mutex. Phase 2 swaps for a real store.
5. **Server-authoritative — client never computes legality.** Client sends "I want to play Smithy"; server says yes-and-here's-the-new-state, or no-and-here's-why.

---

## Section 2 — Repo layout

Monorepo for `dominion-grpc`. Proto, server, bot, and (later) frontends all live together so the contract and its consumers move in lockstep.

```
dominion-grpc/                # separate git repo, lives at
                              # /home/tie/superpower-dominion/dominion-grpc/
├── proto/                    # source of truth — protobuf definitions
│   └── dominion/v1/
│       ├── game.proto        # GameService RPCs, game state messages
│       ├── card.proto        # card identity, card data
│       └── common.proto      # shared enums (CardType, Phase, etc.)
│
├── gen/                      # generated code — never hand-edit
│   ├── go/                   # buf generates Go stubs here
│   └── ts/                   # buf generates TS client here (Phase 1b)
│
├── cmd/                      # entry points — main packages
│   ├── server/main.go        # Connect-Go HTTP server
│   └── bot/main.go           # standalone bot client (also used in tests)
│
├── internal/                 # private Go packages
│   ├── engine/               # PURE — no network, no protobuf
│   │   ├── state.go          # GameState, PlayerState, Supply
│   │   ├── phases.go         # action / buy / cleanup state machine
│   │   ├── primitives.go     # +cards, +action, gain, trash, discard, reveal
│   │   ├── action.go         # Action union type, Apply(state, action)
│   │   └── cards/
│   │       ├── registry.go   # CardID → card definition lookup
│   │       ├── basic.go      # Copper/Silver/Gold/Estate/Duchy/Province/Curse
│   │       ├── smithy.go     # one file per kingdom card
│   │       ├── village.go
│   │       └── ...           # 26 kingdom cards total
│   │
│   ├── service/              # Connect handlers — THIN translation layer
│   │   └── game_service.go   # protobuf <-> engine.Action / engine.State
│   │
│   ├── store/                # in-memory game registry (Phase 1)
│   │   └── memory.go
│   │
│   └── bot/                  # bot strategies as a library
│       ├── bigmoney.go
│       └── smithy_bm.go
│
├── clients/
│   └── web-react/            # added in Phase 1b
│       └── (Vite app)
│
├── buf.yaml                  # buf module config
├── buf.gen.yaml              # codegen targets (Go now, TS later)
├── go.mod
├── Makefile                  # buf generate, test, run targets
└── README.md
```

**Boundary rules:**

- `proto/` is the contract. Touch this first when changing the API. `buf generate` regenerates everything downstream.
- `internal/engine/` has **zero imports** from `gen/` or `connect-go`. If you ever need to import protobuf into engine code, that's a smell — translation belongs in `service/`.
- `internal/service/` is the **only** layer that knows Connect exists.
- `cmd/bot/` is both a CLI tool and the basis for integration tests.
- `clients/web-react/` is empty until Phase 1b.
- Each future client is a sibling under `clients/`. **No client imports another client. No client reaches into `internal/`.** Only `gen/` is shared.
- Future migration path: push `proto/` to BSR, then clients can be extracted to their own repos consuming the published BSR module.

---

## Section 3 — Proto contract shape

### One service, three RPCs

```proto
service GameService {
  // Create a new game with a list of players (each player is a strategy
  // identifier — "human", "bigmoney", "smithy_bm", etc.). Returns the
  // game ID and initial state.
  rpc CreateGame(CreateGameRequest) returns (CreateGameResponse);

  // Server-streaming. Subscribe to all events for a game: state updates,
  // turn transitions, card-played notifications, decisions awaiting
  // response. Client opens this once per game and reduces events into
  // local state.
  rpc StreamGameEvents(StreamGameEventsRequest) returns (stream GameEvent);

  // Unary. Submit a player action OR a response to a pending decision.
  // Server validates against current game state and either applies it
  // (broadcasting events on the stream) or returns an error.
  rpc SubmitAction(SubmitActionRequest) returns (SubmitActionResponse);
}
```

### Action union (single SubmitAction RPC, oneof payload)

```proto
message Action {
  oneof kind {
    PlayCardAction      play_card      = 1;
    BuyCardAction       buy_card       = 2;
    EndPhaseAction      end_phase      = 3;
    ResolveDecision     resolve        = 4;
  }
}
```

Rationale: avoids ~15 typed RPCs (`PlayCard`, `BuyCard`, `ResolveCellarDiscard`, …); mirrors the engine's internal `Action` union; new action types are additive proto changes.

### Mid-effect player decisions (the hard part)

The engine carries a `pending_decision` field in game state. When non-null, the **only** legal action is a `ResolveDecision` answering that prompt's ID. When null, free actions are legal.

```proto
message Decision {
  string id = 1;
  oneof prompt {
    DiscardFromHandPrompt    discard      = 2;
    TrashFromHandPrompt      trash        = 3;
    GainFromSupplyPrompt     gain         = 4;
    ChooseFromRevealedPrompt revealed     = 5;
    YesNoPrompt              yes_no       = 6;
    PlayActionTwicePrompt    throne_room  = 7;
  }
}

message ResolveDecision {
  string decision_id = 1;
  oneof answer {
    CardSelection cards   = 2;
    bool          yes_no  = 3;
    int32         index   = 4;
  }
}
```

**~6–8 prompt primitives cover every Base set card.** New cards reuse the prompts; only engine effect logic changes.

### Events (server-streaming)

```proto
message GameEvent {
  uint64 sequence = 1;          // monotonic per game, for client ordering
  google.protobuf.Timestamp at = 2;
  oneof kind {
    GameStateSnapshot    snapshot       = 3;  // full state, sent on subscribe
    PlayerActionApplied  action_applied = 4;
    PhaseChanged         phase_changed  = 5;
    TurnStarted          turn_started   = 6;
    DecisionRequested    decision       = 7;
    GameEnded            ended          = 8;
  }
}
```

First event after `StreamGameEvents` is always a full `GameStateSnapshot`. Subsequent events are deltas. Reconnect = re-subscribe + fresh snapshot. Sequence numbers let clients detect gaps.

### Symmetric client loop (works for bots and UIs)

```go
stream := client.StreamGameEvents(ctx, ...)
for event := stream.Recv() {
    state.Apply(event)
    if state.IsMyTurn() && state.PendingDecision == nil {
        action := strategy.PickAction(state)
        client.SubmitAction(ctx, action)
    } else if state.PendingDecision != nil && state.DecidingPlayer == me {
        choice := strategy.Resolve(state.PendingDecision, state)
        client.SubmitAction(ctx, ResolveDecision{...})
    }
}
```

A React component does the same shape: reduce events into a state store, render based on state, dispatch `SubmitAction` on user clicks.

---

## Section 4 — Engine structure

### Core types

```go
package engine

type GameState struct {
    GameID          string
    Seed            int64           // for deterministic RNG/shuffles
    rng             *rand.Rand      // seeded from Seed; never exposed
    Players         []PlayerState
    CurrentPlayer   int
    Phase           Phase           // Action | Buy | Cleanup
    Supply          Supply
    Trash           []CardID
    Turn            int
    PendingDecision *Decision       // non-nil = waiting for player input
    Log             []LogEntry
    Ended           bool
    Winners         []int
}

type PlayerState struct {
    Name    string
    Hand    []CardID
    Deck    []CardID            // top of deck = end of slice
    Discard []CardID
    InPlay  []CardID
    Actions int
    Buys    int
    Coins   int
    VPTokens int                // unused in Base set
}

type Supply struct {
    Piles map[CardID]int
}

type Phase int
const (
    PhaseAction Phase = iota
    PhaseBuy
    PhaseCleanup
)
```

**What's NOT in state:** transport types, WebSocket connections, timestamps, i18n strings.

### Apply function — the engine's only entry point

```go
func Apply(state GameState, action Action) (GameState, []Event, error)
```

- Pure: same inputs → same outputs.
- Returns events alongside new state (engine knows exactly what changed because it just changed it).
- Errors mean illegal action; the error message becomes the gRPC error returned to the client.

### Action union

```go
type Action interface { isAction() }

type PlayCard        struct { PlayerIdx int; Card CardID }
type BuyCard         struct { PlayerIdx int; Card CardID }
type EndPhase        struct { PlayerIdx int }
type ResolveDecision struct {
    PlayerIdx  int
    DecisionID string
    Answer     DecisionAnswer
}
```

Four action types total. **New cards never add new action types** — they reuse `PlayCard` + `ResolveDecision`.

### Phase state machine

```
       ┌─────────────────┐
       │  PhaseAction    │ ── PlayCard (action) ──┐
       │  (Actions > 0)  │ ── EndPhase ─┐         │
       └─────────────────┘              │         │
                                        ▼         │
       ┌─────────────────┐                        │
       │  PhaseBuy       │ ── PlayCard (treas) ──┤
       │                 │ ── BuyCard ──────────┤
       │                 │ ── EndPhase ─┐        │
       └─────────────────┘              │         │
                                        ▼         │
       ┌─────────────────┐                        │
       │  PhaseCleanup   │ (automatic — engine    │
       │                 │  moves InPlay+Hand to  │
       │                 │  Discard, draws 5,     │
       │                 │  advances player)      │
       └─────────────────┘                        │
                            │                     │
                            └─────────────────────┘
```

`PendingDecision` is an **orthogonal substate**, not a separate phase. While non-nil, only `ResolveDecision` matching that ID is legal; free actions error with "decision pending."

### Effect primitives — the toolkit cards bind to

```go
package engine

func DrawCards(s *GameState, playerIdx, n int) []Event
func DiscardFromHand(s *GameState, playerIdx int, cards []CardID) []Event
func TrashFromHand(s *GameState, playerIdx int, cards []CardID) []Event
func GainCard(s *GameState, playerIdx int, card CardID, dest GainDest) []Event
func RevealFromDeck(s *GameState, playerIdx, n int) ([]CardID, []Event)
func PutOnDeck(s *GameState, playerIdx int, cards []CardID) []Event

func AddActions(s *GameState, playerIdx, n int) []Event
func AddBuys(s *GameState, playerIdx, n int) []Event
func AddCoins(s *GameState, playerIdx, n int) []Event

func RequestDecision(s *GameState, playerIdx int, prompt Prompt) []Event
// ^ sets s.PendingDecision; engine exits without applying further effects
//   until ResolveDecision arrives.

func EachOtherPlayer(s *GameState, except int, fn func(idx int) []Event) []Event
// ^ helper for attack cards (Witch, Bureaucrat, Militia, Bandit).
```

**Roughly 15 primitives total.** Every Base set card composes these.

### Determinism

**Every random op in the engine goes through `state.rng`**, seeded from `state.Seed` at game creation. Consequences:

- Same seed + same action sequence = bit-identical state every time.
- Replay tests trivial: store seed + action list.
- Bot-vs-bot integration tests reproducible — failures are debuggable by replay.
- Save/restore is `(seed, action_log)` — no full-state serialization needed.

**Hard rule:** never use `math/rand` package-level functions in `engine/`.

### What's deliberately NOT in the engine

- No concurrency (one goroutine per game; service layer holds the per-game mutex).
- No persistence (Phase 2 adds `store/`).
- No network awareness (no contexts, deadlines, client identity).
- No clock (timestamps and turn timers are service-layer).

---

## Section 5 — Card representation & 26-card breakdown

### Unified Card struct

Treasures, victories, curses, kingdom cards — all the same type. No special cases.

```go
package engine

type Card struct {
    ID    CardID                                // "smithy", "copper", "province"
    Name  string
    Cost  int
    Types []CardType                            // {Action}, {Treasure}, {Victory}, {Action,Attack}, {Action,Reaction}, ...

    // OnPlay runs when a player plays the card.
    OnPlay func(s *GameState, playerIdx int) []Event

    // VictoryPoints is called at game end. Returns 0 for non-victory.
    // Gardens overrides this to count deck size.
    VictoryPoints func(p PlayerState) int

    // OnReaction is called when another player triggers an event the
    // card can react to (currently: attacks). Nil for non-reaction cards.
    OnReaction func(s *GameState, playerIdx int, trigger Trigger) (activated bool, events []Event)
}
```

Five fields. Every card in the Base set fits.

### Basic cards example

```go
var Copper = engine.Card{
    ID: "copper", Name: "Copper", Cost: 0,
    Types: []engine.CardType{engine.TypeTreasure},
    OnPlay: func(s *engine.GameState, p int) []engine.Event {
        return engine.AddCoins(s, p, 1)
    },
}

var Province = engine.Card{
    ID: "province", Name: "Province", Cost: 8,
    Types: []engine.CardType{engine.TypeVictory},
    VictoryPoints: func(p engine.PlayerState) int { return 6 },
}

var Curse = engine.Card{
    ID: "curse", Name: "Curse", Cost: 0,
    Types: []engine.CardType{engine.TypeCurse},
    VictoryPoints: func(p engine.PlayerState) int { return -1 },
}
```

### Registry

```go
package cards

var registry = map[engine.CardID]*engine.Card{}

func Register(c *engine.Card) {
    if _, exists := registry[c.ID]; exists {
        panic("duplicate card ID: " + string(c.ID))
    }
    registry[c.ID] = c
}

func Lookup(id engine.CardID) (*engine.Card, bool) { ... }
func All() []*engine.Card { ... }

// Each card file has init() { Register(&Smithy) }
```

`engine/` never imports `cards/`. Engine takes a card lookup function as a parameter when needed.

### Implementation tier order (each tier proves a new engine capability)

#### Tier 0 — Basics (no kingdom cards)
| Cards | What's needed |
|---|---|
| Copper, Silver, Gold | `AddCoins`, treasure-in-buy-phase rule |
| Estate, Duchy, Province | `VictoryPoints` hook, end-of-game scoring |
| Curse | Negative VP, Curse pile in supply |

**Done when:** A bot plays an entire game with only treasures and Provinces. Big Money strategy works.

#### Tier 1 — Pure stat-boost actions (no decisions)
| Card | Effect | New primitive |
|---|---|---|
| Village | +1 card, +2 actions | `AddActions` |
| Smithy | +3 cards | (none) |
| Festival | +2 actions, +1 buy, +2 coins | `AddBuys` |
| Laboratory | +2 cards, +1 action | (none) |
| Market | +1 card, +1 action, +1 buy, +1 coin | (none) |
| Council Room | +4 cards, +1 buy, each other player draws 1 | `EachOtherPlayer` |

**Done when:** Smithy + Big Money outperforms pure Big Money in head-to-head — a known result, doubles as engine correctness check.

#### Tier 2 — Cards with simple decisions (no targeting other players)
| Card | Effect | New prompt |
|---|---|---|
| Cellar | +1 action, discard any → draw same | `DiscardFromHandPrompt` |
| Chapel | Trash up to 4 from hand | `TrashFromHandPrompt` |
| Workshop | Gain a card costing ≤4 | `GainFromSupplyPrompt` (cost filter) |
| Moneylender | May trash a Copper → +3 coins | `YesNoPrompt` |
| Remodel | Trash → gain costing ≤ trashed+2 | Two-step (trash → gain) |
| Mine | May trash a Treasure → gain Treasure costing ≤ trashed+3, to hand | Two-step |
| Harbinger | +1 card, +1 action, look at discard, may put one on deck | `ChooseFromListPrompt` |
| Vassal | +2 coins, discard top of deck; if Action, may play | `YesNoPrompt` after reveal |
| Poacher | +1 card, +1 action, +1 coin, discard 1 per empty pile | `DiscardFromHandPrompt` (exact count) |
| Artisan | Gain a card costing ≤5 to hand, then put one from hand on deck | Two-step (gain → place) |

**Done when:** 1000-game bot-vs-bot integration test passes with these in supply. ~6 distinct prompt types covers all 10 cards.

#### Tier 3 — Attacks + reactions
| Card | Effect | New capability |
|---|---|---|
| Witch | +2 cards, each other gains a Curse | Attack flag, gain to other players |
| Militia | +2 coins, each other discards to 3 | Per-victim decision |
| Bureaucrat | Gain Silver to deck; each other reveals a Victory and puts on deck | Per-victim conditional decision |
| Bandit | Gain Gold; each other reveals top 2, trashes a non-Copper Treasure, discards rest | Per-victim multi-step |
| Moat | +2 cards; **Reaction:** when an Attack is played, reveal Moat to be unaffected | **Reaction system** (~50 LoC engine addition) |

**Moat introduces the trigger/reaction concept** — the only piece in Phase 1a that requires engine changes beyond primitives.

**Done when:** Witch correctly empties the Curse pile. Moat correctly blocks attacks. Bot-vs-bot games with all attacks still terminate normally.

#### Tier 4 — Complex multi-step
| Card | Hard part |
|---|---|
| **Throne Room** | Recursion — calls another card's OnPlay twice. If the doubled card requests a decision, the second play has to wait for the first to fully resolve. Throne-Room-of-Throne-Room is a real edge case worth a dedicated test. |
| **Library** | Loop with per-card decisions. Reveal one at a time, Yes/No on actions, continue until hand size = 7 OR deck+discard empty. Set-aside zone is a temporary card location not used elsewhere. |
| **Sentry** | Three-step decision: trash some, discard some, reorder the rest. |

**Done when:** Throne-Room-of-Throne-Room-of-Witch correctly gives each opponent two Curses. Library stops at 7 cards even when deck runs out mid-draw. Sentry's reorder doesn't lose cards.

#### Tier 5 — Special hooks
| Card | New hook |
|---|---|
| Gardens | `VictoryPoints` reads whole deck size |
| Merchant | "First time you play a Silver this turn" — per-turn trigger flag |

### Sequencing

```
Tier 0 → Tier 1 → Tier 2 → Tier 3 → Tier 4 → Tier 5
basics    no-dec    decisions  attacks   complex    special
            (6)        (10)       (5)       (3)        (2)
```

Each tier = a **GitHub milestone**. Each card within a tier = a **GitHub issue**. Engine work concentrated in Tiers 0–1; later tiers are mostly "compose primitives in a new file."

### What this design does NOT try to handle

Forward-compat with future Dominion sets (durations, tokens, VP chips, exile, etc.). Phase 4+ work. The engine should be **good for Base**, refactor when expansions come up.

---

## Section 6 — Bot client design (TO DO ON RESUME)

To cover when brainstorming resumes:

- The bot as a Connect client (uses `gen/go/` typed client, identical surface to a future React client)
- Strategy interface — `PickAction(state) Action` and `Resolve(decision, state) Answer`
- Built-in strategies for Phase 1a:
  - **BigMoney** — buy Province if ≥8 coins, Gold ≥6, Silver ≥3, else nothing; never play actions
  - **SmithyBM** — same as BigMoney but buy Smithy on early turns and play it during Action phase
- How bots are wired into integration tests (in-process server, two bot clients, full game in milliseconds)
- Whether to also expose bots over the network (e.g., spectatable bot-only games via the same Connect API)

## Section 7 — Testing strategy + GitHub-issue organization (TO DO ON RESUME)

To cover when brainstorming resumes:

- **Engine unit tests** — table-driven, one test file per card, covers happy path + edge cases (empty deck, empty supply, decision-pending guards)
- **Integration tests** — `bot-vs-bot` games at the Connect layer, in-process server, runs N=1000 games per CI run with random supplies and seeds; fails on any panic, illegal state, or non-terminating game
- **Replay tests** — known-buggy game seed + action log captured as a regression fixture; replay must produce identical outcome
- **Property tests** — invariants like "total cards in game is conserved" (sum of all hands+decks+discards+inplay+supply+trash always equals starting card count)
- **Linting** — `buf lint`, `buf breaking` against main branch, `golangci-lint` on Go code
- **Pre-commit / CI** — `buf generate` is committed (or verified-clean in CI), tests run on every push
- **GitHub-issue organization:**
  - **Milestones** map to phases and tiers (`Phase 1a — Tier 0 Basics`, `Phase 1a — Tier 1 Stat Boosts`, …)
  - **Labels:** `area:engine`, `area:proto`, `area:server`, `area:bot`, `area:client-react`, `area:tooling`, `kind:card`, `kind:engine-primitive`, `kind:test`, `kind:infra`
  - **Issue templates** for "new card" and "new engine primitive" so each PR is small, focused, and consistent
  - **Epic issues** for cross-cutting work (the proto contract, the engine package, the bot strategy framework)

After Section 7 is presented and approved, the brainstorming flow's terminal action is to invoke the `superpowers:writing-plans` skill to produce a step-by-step implementation plan. That plan becomes the actual GitHub issues the user originally asked about.

---

## Open questions (none currently blocking)

- Exact bot strategy beyond Big Money + Smithy-BM — punted to Phase 3 ("smarter AI").
- Whether the dev-env repo and the project repo share the same name on GitHub or differ — leaning toward project = `dominion-grpc` on GitHub, dev-env stays as a personal/private setup repo. To be confirmed.
- Logging format and verbosity in the engine — to be decided during implementation; not architectural.
