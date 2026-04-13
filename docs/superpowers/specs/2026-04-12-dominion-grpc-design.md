# dominion-grpc — Design Spec

**Status:** Brainstorming complete. All sections approved by user. Next step is to invoke `superpowers:writing-plans` to produce an implementation plan.
**Date started:** 2026-04-12
**Date completed:** 2026-04-13
**Author of brainstorm:** Claude (Opus 4.6) with user
**Companion document:** `2026-04-12-dominion-grpc-section3-primer.md` — a newcomer-friendly walkthrough of Section 3 for readers new to protobuf / gRPC / Connect.
**Spec location note:** This file lives in the dev-env repo (`/home/tie/superpower-dominion/`). It will be moved into the future project repo (`dominion-grpc/`) once that repo is created.

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

## Section 6 — Bot client design

The bot is the lynchpin of Phase 1a. It is both **the test harness** that proves the proto contract works end-to-end AND **the AI opponent** that single-player mode ships with. Designing it well means the same code that runs inside `go test` runs unchanged when the project ships.

### 6.1 The bot is "just a Connect client"

Directory layout:

```
cmd/bot/main.go               # CLI entry point: connect to a server, play a game
internal/bot/
   client.go                  # thin wrapper around the generated Connect client
   state.go                   # ClientState + Apply(event) reducer
   strategy.go                # Strategy interface
   bot.go                     # Run(ctx, client, gameID, playerIdx, strategy) loop
   bigmoney.go                # BigMoney strategy
   smithy_bm.go               # Smithy + BigMoney strategy
```

**Critical boundary rule:** `internal/bot/` imports `gen/go/dominion/v1` (the generated Connect client) and `connectrpc.com/connect`. It does **NOT** import `internal/engine/`. If the bot ever needed engine internals to function, the contract would have a hole — the bot exists specifically to prove it does not. A future TypeScript React client will live under exactly the same constraint.

### 6.2 Local state from the event stream

The bot keeps its own client-side reduction of the game. This is the same shape the React store will eventually take — a reducer over events — so building it for the bot first means the reducer logic is proven before the frontend exists.

```go
package bot

type ClientState struct {
    Me              int                       // my player index in this game
    LastSeq         uint64                    // last event sequence applied
    Snapshot        *pb.GameStateSnapshot     // last full snapshot received
    Log             []*pb.GameEvent           // events applied since the snapshot
    Phase           pb.Phase
    Turn            int
    CurrentPlayer   int
    PendingDecision *pb.Decision              // nil = no decision pending
    DecidingPlayer  int
    Ended           bool
    Winners         []int
}

func (cs *ClientState) Apply(ev *pb.GameEvent) error {
    if cs.LastSeq != 0 && ev.Sequence != cs.LastSeq+1 {
        return ErrSequenceGap                 // caller re-subscribes for fresh snapshot
    }
    cs.LastSeq = ev.Sequence

    switch k := ev.Kind.(type) {
    case *pb.GameEvent_Snapshot:
        cs.Snapshot = k.Snapshot
        cs.Log = cs.Log[:0]
        cs.Phase = k.Snapshot.Phase
        cs.Turn = int(k.Snapshot.Turn)
        cs.CurrentPlayer = int(k.Snapshot.CurrentPlayer)
        cs.PendingDecision = k.Snapshot.PendingDecision
    case *pb.GameEvent_PhaseChanged:
        cs.Phase = k.PhaseChanged.NewPhase
    case *pb.GameEvent_TurnStarted:
        cs.Turn = int(k.TurnStarted.Turn)
        cs.CurrentPlayer = int(k.TurnStarted.PlayerIdx)
        cs.PendingDecision = nil
    case *pb.GameEvent_Decision:
        cs.PendingDecision = k.Decision.Decision
        cs.DecidingPlayer = int(k.Decision.PlayerIdx)
    case *pb.GameEvent_ActionApplied:
        // apply derived view updates (hand/discard/inplay/coins/buys/actions)
    case *pb.GameEvent_Ended:
        cs.Ended = true
        cs.Winners = intsFrom(k.Ended.Winners)
    }
    cs.Log = append(cs.Log, ev)
    return nil
}

func (cs *ClientState) IsMyTurn() bool { return cs.CurrentPlayer == cs.Me && !cs.Ended }
```

Two deliberate properties:

- **Pure reduction.** `Apply` only mutates `cs`; no I/O, no network, no time.
- **Gap detection built in.** If a sequence number is skipped, `Apply` returns `ErrSequenceGap` and the loop above it re-subscribes. No recovery logic lives inside the reducer itself.

### 6.3 The Strategy interface

Two methods, symmetric to the two states a player can be in (free turn vs. mid-decision):

```go
package bot

type Strategy interface {
    Name() string

    // PickAction is called when it's our turn AND no decision is pending.
    // Returns the next Action to submit, or nil to signal "nothing more
    // to do this phase — the loop should send EndPhase."
    PickAction(cs *ClientState) *pb.Action

    // Resolve is called when a decision is pending AND we are the
    // deciding player. Must reference the current decision's ID.
    Resolve(cs *ClientState, d *pb.Decision) *pb.ResolveDecision
}
```

Key choices:

1. **Strategies are pure.** Read `ClientState`, return a proto message, never mutate, never do I/O. That makes them unit-testable without a server — hand them a fake `ClientState` and assert what they pick.
2. **`Name()` is for logs, metrics, and CLI flags.** `--strategy bigmoney` looks up by name.
3. **`nil` from `PickAction` means "end the phase."** It is the one escape hatch so strategies do not have to construct `EndPhaseAction` explicitly every time they are done.
4. **`Resolve` always echoes `d.Id`.** The returned `ResolveDecision` carries the original ID back so the server can reject stale answers.

### 6.4 The bot event loop

```go
func Run(ctx context.Context, c *Client, gameID string, me int, strat Strategy) error {
    cs := &ClientState{Me: me}

resubscribe:
    stream, err := c.StreamGameEvents(ctx, gameID)
    if err != nil {
        return err
    }

    for stream.Receive() {
        ev := stream.Msg()
        if err := cs.Apply(ev); err != nil {
            if errors.Is(err, ErrSequenceGap) {
                stream.Close()
                goto resubscribe               // fresh snapshot re-baselines us
            }
            return err
        }
        if cs.Ended {
            return nil
        }

        switch {
        case cs.PendingDecision != nil && cs.DecidingPlayer == cs.Me:
            resp := strat.Resolve(cs, cs.PendingDecision)
            if err := c.SubmitResolve(ctx, gameID, resp); err != nil {
                return err
            }

        case cs.IsMyTurn() && cs.PendingDecision == nil:
            action := strat.PickAction(cs)
            if action == nil {
                action = endPhase()             // strategy is done; end phase
            }
            if err := c.SubmitAction(ctx, gameID, action); err != nil {
                return err
            }
        }
    }
    return stream.Err()
}
```

Three properties worth calling out:

1. **No polling.** The loop is woken by stream events only — never by sleeps or timers.
2. **Reconnect is built in.** Sequence-gap → close stream → resubscribe → receive fresh snapshot → resume. The same pattern protects a real client from dropped frames in Phase 2.
3. **Two-state decision tree.** The entire "what should I do now?" logic is two cases: my-turn-no-decision vs. decision-pending-for-me. New card types never add new branches here — they only add new prompt cases inside `Resolve`.

### 6.5 BigMoney (the canary strategy)

```go
type BigMoney struct{}

func (BigMoney) Name() string { return "bigmoney" }

func (BigMoney) PickAction(cs *ClientState) *pb.Action {
    me := cs.MyPlayer()

    switch cs.Phase {
    case pb.Phase_PHASE_ACTION:
        return nil                              // BigMoney never plays actions

    case pb.Phase_PHASE_BUY:
        for _, c := range me.Hand {
            if isTreasure(c) {
                return playCard(c)              // auto-play all treasures first
            }
        }
        switch {
        case me.Coins >= 8: return buyCard("province")
        case me.Coins >= 6: return buyCard("gold")
        case me.Coins >= 3: return buyCard("silver")
        }
        return nil                              // end phase
    }
    return nil
}

func (BigMoney) Resolve(cs *ClientState, d *pb.Decision) *pb.ResolveDecision {
    // BigMoney never buys action cards, so in a pure-BigMoney game it
    // should never be asked a question. If one arrives anyway (e.g., an
    // opponent's attack forces a decision), return the minimum legal
    // answer so the game does not deadlock. NOT "play well under attack"
    // — that is a Phase 3 concern.
    return safeRefusal(d)
}
```

About 50 lines including helpers. It is the "hello world" of Dominion AI and exists primarily to prove the engine is correct — BigMoney converging on Provinces is a known result, so if the engine is wrong, BigMoney's win rate against itself will show it.

### 6.6 SmithyBM (the second-tier strategy)

Same shape as BigMoney, plus:

- **Action phase:** if a Smithy is in hand and `Actions >= 1`, play it.
- **Buy phase:** on turns 3 and 4, prefer Smithy over Silver. After turn 4, revert to BigMoney's economy rules.

Roughly 80 lines. The important point is not the strategy itself — it is that **adding a new strategy is one new file in `internal/bot/`**, zero engine changes, zero proto changes, zero service-layer changes. Every future strategy fits this shape.

### 6.7 How bots wire into integration tests

The payoff, and the reason the bot is designed as a first-class client instead of a stub:

```go
func TestBotVsBot_BigMoney_Smithy(t *testing.T) {
    // 1. Spin up the real Connect server in-process.
    srv := newTestServer(t)
    defer srv.Close()

    // 2. Two bot clients hit srv.URL via real HTTP (loopback).
    a := bot.NewClient(srv.URL)
    b := bot.NewClient(srv.URL)

    // 3. Create a game with two bot players and a fixed seed.
    game, err := a.CreateGame(ctx, []string{"bigmoney", "smithy_bm"}, /*seed*/ 42)
    require.NoError(t, err)

    // 4. Run both bots concurrently.
    errg, ctx := errgroup.WithContext(ctx)
    errg.Go(func() error { return bot.Run(ctx, a, game.Id, 0, bot.BigMoney{}) })
    errg.Go(func() error { return bot.Run(ctx, b, game.Id, 1, bot.SmithyBM{}) })
    require.NoError(t, errg.Wait())

    // 5. Assert the game terminated correctly.
    final := mustFetchFinal(t, a, game.Id)
    require.True(t, final.Ended)
    require.Len(t, final.Winners, 1)
}
```

What this exercises end-to-end in a single test:

- **Transport layer:** real Connect over loopback HTTP, real protobuf marshalling.
- **Service layer:** request validation, game lookup, decision routing, error translation.
- **Engine layer:** every card effect that actually gets played.
- **Bot library:** event reduction, strategy evaluation, decision handling, reconnect path.
- **Determinism:** fixed seed + fixed strategies = identical outcome every run.

The plan is to run 1000 such games per CI push with random seeds and random kingdom subsets. Section 7A.5 details the sweep.

### 6.8 Bot CLI is a first-class deliverable (Option A)

The bot library is wrapped by `cmd/bot/main.go` as a documented, supported CLI:

```
dominion-bot \
  --server http://localhost:8080 \
  --game abc123 \
  --as-player 1 \
  --strategy bigmoney
```

This is promoted in the README and is the intended workflow for manual Phase 1b acceptance testing: run the server, attach a bot to one seat via CLI, open the browser on the other seat, play an actual game against the bot end-to-end. The CLI already has to exist for tests, so first-class support costs only documentation and a few extra flags.

## Section 7 — Testing strategy + GitHub-issue organization

Section 7 has two halves. **7A** is how we know the code is correct (the test pyramid: unit → property → service → integration → replay). **7B** is how the work is broken into trackable GitHub units.

### 7A — Testing strategy

#### 7A.1 The five test tiers

| Tier | What it tests | Where it lives | Run frequency |
|---|---|---|---|
| **1. Engine unit tests** | Single card effects, primitives, phase transitions | `internal/engine/cards/*_test.go` and `internal/engine/*_test.go` | Every save / every push |
| **2. Engine property tests** | Invariants that hold across any legal action sequence | `internal/engine/properties_test.go` | Every push |
| **3. Service-layer tests** | Proto ↔ engine translation, Connect error codes | `internal/service/*_test.go` | Every push |
| **4. Bot-vs-bot integration tests** | Whole stack (proto + transport + service + engine + bot), 1000 games per run | `internal/bot/integration_test.go` | Every push |
| **5. Replay regression tests** | Captured buggy `(seed, action_log)` fixtures replayed to a known outcome | `testdata/replays/*.json` consumed by a single parameterized test | Every push |

Each tier catches bugs the tier below misses. Unit tests catch "Smithy drew the wrong number of cards." Property tests catch "somewhere in the engine, cards get duplicated." Service tests catch "we forgot to translate decision answers." Integration tests catch "the full loop deadlocks under Militia." Replay tests catch "we fixed that last month and just re-introduced it."

#### 7A.2 Engine unit tests — the foundation

Pattern: **table-driven, one file per card, cover happy path + every guard.** Go's standard `testing` package plus `testify/require` for assertions — no other test framework.

```go
func TestSmithy_OnPlay_DrawsThreeCards(t *testing.T) {
    cases := []struct {
        name     string
        deckSize int
        discard  int
        want     int
    }{
        {"full deck", 10, 0, 3},
        {"empty deck, discard has enough", 0, 5, 3},
        {"deck + discard together have fewer than 3", 1, 1, 2},
        {"nothing to draw", 0, 0, 0},
    }
    for _, tc := range cases {
        t.Run(tc.name, func(t *testing.T) {
            s := newTestState(tc.deckSize, tc.discard)
            before := len(s.Players[0].Hand)
            _, events, err := engine.Apply(s, engine.PlayCard{PlayerIdx: 0, Card: "smithy"})
            require.NoError(t, err)
            require.Equal(t, before+tc.want, len(s.Players[0].Hand))
            require.Contains(t, events, engine.CardDrawnEvent{Count: tc.want})
        })
    }
}
```

**Every card's test file must cover:** happy path, empty-deck edge, decision-pending guard (if the card sets one), resource guards (`Actions == 0`, `Buys == 0` etc.), end-of-game guard. The `new-card.md` issue template (Section 7B.3) makes this a checklist.

Every *primitive* (`DrawCards`, `TrashFromHand`, `GainCard`, …) gets its own unit test file. Primitives are the most reused code in the engine; a bug in `GainCard` affects every gain in the game.

#### 7A.3 Engine property tests — the "something is wrong somewhere" detector

The engine has a small number of **global invariants** that should hold after any legal action, regardless of which cards are in play. Cheap to express, extremely effective at catching bugs unit tests miss.

```go
func TestProperty_CardConservation(t *testing.T) {
    for i := 0; i < 500; i++ {
        seed := int64(i)
        state := randomStartState(seed)
        startTotal := totalCards(state)

        final := playRandomGame(t, state, /*maxActions*/ 10000, seed)

        require.Equal(t, startTotal, totalCards(final),
            "card conservation violated at seed %d", seed)
    }
}

func totalCards(s engine.GameState) int {
    total := len(s.Trash)
    for _, p := range s.Players {
        total += len(p.Hand) + len(p.Deck) + len(p.Discard) + len(p.InPlay)
    }
    for _, n := range s.Supply.Piles {
        total += n
    }
    return total
}
```

**Invariants to check as properties:**

1. **Card conservation** — sum of all piles (hands + decks + discards + in-play + trash + supply) equals the starting card count. The single most important invariant; a violation means something either duplicated or dropped a card.
2. **Resource non-negativity** — `Actions`, `Buys`, `Coins` never go negative.
3. **Phase ordering** — a game never leaves `PhaseCleanup` for `PhaseAction` of the *same* player; cleanup always advances.
4. **Decision resolution** — if `PendingDecision` is non-nil at step N, step N+1 either resolves it (pending becomes nil) or returns an error (pending unchanged). No state where pending flips to a different decision without resolution.
5. **Game termination** — after a bounded number of steps, every random game either is still playable or has ended. No infinite loops, no stuck states.

Seeded deterministically (0..500) so failures are reproducible.

#### 7A.4 Service-layer tests — the translation boundary

Thin, targeted. The service layer's job is protobuf ↔ engine translation, so the tests look like:

```go
func TestGameService_SubmitAction_PlayCard(t *testing.T) {
    svc := service.New(store.NewMemory(), engine.NewDefaultRegistry())

    game, _ := svc.CreateGame(ctx, req(&pb.CreateGameRequest{
        Players: []string{"human", "human"}, Seed: 42,
    }))

    _, err := svc.SubmitAction(ctx, req(&pb.SubmitActionRequest{
        GameId: game.Id,
        Action: &pb.Action{Kind: &pb.Action_PlayCard{PlayCard: &pb.PlayCardAction{
            PlayerIdx: 0, CardId: "smithy",
        }}},
    }))

    require.NoError(t, err)
    state := svc.Debug_GetState(game.Id)
    require.Contains(t, state.Players[0].InPlay, engine.CardID("smithy"))
}

func TestGameService_SubmitAction_IllegalReturnsConnectError(t *testing.T) {
    svc, game := setupGameWithNoActionsLeft(t)

    _, err := svc.SubmitAction(ctx, req(&pb.SubmitActionRequest{
        GameId: game.Id,
        Action: playCardAction(0, "smithy"),
    }))

    var connectErr *connect.Error
    require.ErrorAs(t, err, &connectErr)
    require.Equal(t, connect.CodeFailedPrecondition, connectErr.Code())
}
```

Two kinds of test:
- **Happy-path translation:** a valid proto request produces the right engine state change.
- **Error translation:** engine errors become the right Connect error codes. `FailedPrecondition` for illegal moves, `NotFound` for unknown game IDs, `InvalidArgument` for malformed protobuf.

Service tests are NOT where we exhaustively test card behavior — that is the engine unit tests' job. They only verify the translation is faithful.

#### 7A.5 Bot-vs-bot integration tests — the whole-stack hammer

The test shape is already shown in Section 6.7. Here it is parameterized across thousands of scenarios:

```go
func TestBotVsBot_RandomKingdoms(t *testing.T) {
    if testing.Short() {
        t.Skip("integration sweep is slow; use go test -short to skip")
    }

    const gamesPerRun = 1000
    srv := newTestServer(t)
    defer srv.Close()

    for i := 0; i < gamesPerRun; i++ {
        seed := int64(i)
        kingdom := randomKingdomSubset(seed, 10)     // 10 of 26 Base cards
        strategies := randomStrategyPair(seed)       // bigmoney vs smithy_bm, etc.

        t.Run(fmt.Sprintf("seed=%d", seed), func(t *testing.T) {
            runOneGame(t, srv.URL, seed, kingdom, strategies)
        })
    }
}
```

**Failure conditions:** any panic, any Connect error at all (the deterministic strategies should never submit illegal moves — a Connect error means either a strategy bug or a server bug, both of which should fail the test), game does not terminate within `maxTurns` (e.g., 100 turns — real games finish in 15–20), or final state violates any conservation invariant.

**Runtime budget:** 1000 games in under 60 seconds on CI. Engine is fast, server is in-process, realistic numbers are closer to 10–30 seconds. If a future change pushes past 60 seconds, drop to 100 games on PRs and run 1000 nightly.

**CI configuration:**
- `go test ./...` runs unit + property + service + integration + replay tests together.
- `go test -short ./...` skips the 1000-game sweep for local iterative development.
- A dedicated GitHub Actions workflow runs `go test ./...` on every push and every PR.

#### 7A.6 Replay regression tests

When a bug is found (in the wild or in a 1000-game sweep), the fix protocol is:

1. Capture the failing game as `(seed, kingdom_cards, action_log)` — the engine already holds all three.
2. Save it as a JSON fixture under `testdata/replays/<short-description>.json`.
3. A single parameterized test walks `testdata/replays/` and replays each fixture.

```go
func TestReplay_RegressionFixtures(t *testing.T) {
    entries, _ := filepath.Glob("testdata/replays/*.json")
    for _, path := range entries {
        t.Run(filepath.Base(path), func(t *testing.T) {
            replay := loadReplay(t, path)
            final := replayGame(t, replay.Seed, replay.Kingdom, replay.Actions)
            require.Equal(t, replay.ExpectedFinal, finalSummary(final))
        })
    }
}
```

Cheap and invaluable. Every bug that is fixed becomes a permanent regression test **automatically**, without writing a new test by hand each time. The fixture captures exactly the thing that broke. Determinism is what makes this possible — because the engine's only source of randomness is `state.rng` seeded from `state.Seed`, `(seed, actions)` is a complete description of a game.

**Fixture format:** JSON. One file per replay. Chosen over generated Go struct literals because JSON files are diffable in PRs and editable by hand if a fix requires updating the expected outcome.

#### 7A.7 Linting and pre-commit

- **`buf lint`** — enforces proto style (field naming, message naming, package layout). Runs in CI.
- **`buf breaking`** — compares the proto schema against `main` and fails the build on any field-number change, field removal, or type change. The guardrail against accidental backwards-incompatible schema changes.
- **`golangci-lint`** — standard Go linting. A vetted preset: `gofmt`, `govet`, `staticcheck`, `errcheck`, `ineffassign`, `unused`. Nothing more.
- **`buf generate` result is committed to git.** Generated code (`gen/go/`) lives in the repo. CI verifies the committed generated code matches what `buf generate` would produce right now — if they diverge, the build fails with "you forgot to regenerate after touching proto/."

**Rationale for committing generated code:** `go build ./...` works out of a fresh checkout with nothing but a Go toolchain. Contributors do not need `buf` installed just to compile. Only people who modify `.proto` files need `buf`.

### 7B — GitHub-issue organization

Each tier in Section 5 is a chunk of work that slots cleanly into GitHub's milestone/issue model.

#### 7B.1 Milestone structure

Milestones are **phases × tiers**. Each is a shippable checkpoint.

```
Phase 1a / Tier 0 — Basics                   (6 cards + engine skeleton)
Phase 1a / Tier 1 — Pure stat-boost actions  (6 cards)
Phase 1a / Tier 2 — Simple decisions         (10 cards, 6 prompt types)
Phase 1a / Tier 3 — Attacks + reactions      (5 cards, reaction system)
Phase 1a / Tier 4 — Complex multi-step       (3 cards)
Phase 1a / Tier 5 — Special hooks            (2 cards)
Phase 1a / Infrastructure                    (proto, server, bot loop, CI)
Phase 1b / Frontend MVP                      (React app)
Phase 2  / Online multiplayer                (placeholder — detailed later)
Phase 3  / Polish + smarter AI               (placeholder — detailed later)
```

Milestones are ordered. "Done" for a milestone means every issue in it is closed AND the integration sweep passes with those cards enabled.

#### 7B.2 Labels

Two label taxonomies that compose; a typical issue has exactly one `area:*` and one `kind:*`.

**`area:*` — which part of the codebase is affected**
- `area:proto` — `.proto` files or generated code
- `area:engine` — `internal/engine/`
- `area:server` — `internal/service/`, `cmd/server/`
- `area:bot` — `internal/bot/`, `cmd/bot/`
- `area:client-react` — `clients/web-react/` (Phase 1b and later)
- `area:tooling` — buf config, golangci-lint config, Makefile
- `area:ci` — GitHub Actions workflows

**`kind:*` — what kind of work it is**
- `kind:card` — implementing a single Dominion card
- `kind:primitive` — adding or modifying an engine primitive (DrawCards etc.)
- `kind:test` — adding tests not tied to a card (property tests, integration sweeps)
- `kind:epic` — tracking issue for a cross-cutting initiative
- `kind:bug` — something broke
- `kind:chore` — infrastructure, config, docs
- `kind:design` — needs design discussion before implementation

#### 7B.3 Issue templates

Three templates live under `.github/ISSUE_TEMPLATE/` and cover ~90% of issues.

**Template 1 — `new-card.md`** (for every Tier 0–5 card)

```markdown
## Card: <Name>

**Tier:** <0-5>
**Cost:** <int>
**Types:** <Action/Treasure/Victory/Attack/Reaction>

### Rulebook text
> <copy verbatim from the 2nd edition rulebook>

### Primitives used
- [ ] DrawCards
- [ ] AddActions
- [ ] ...

### Prompts used (if any)
- [ ] DiscardFromHandPrompt
- [ ] ...

### Unit tests required
- [ ] Happy path
- [ ] Empty deck / empty discard
- [ ] Decision-pending guard (if applicable)
- [ ] Resource guards (Actions/Buys/Coins)
- [ ] Game-ended guard

### Definition of done
- [ ] Card file added to `internal/engine/cards/`
- [ ] Registered via `init()` → `Register()`
- [ ] All unit tests pass
- [ ] Included in the Tier N integration sweep
- [ ] No new engine primitives needed (or: new primitive issue linked)
```

**Template 2 — `new-primitive.md`** (for engine plumbing)

```markdown
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

**Template 3 — `epic.md`** (cross-cutting tracking issues)

```markdown
## Epic: <Title>

**Phase/Tier:** <>
**Area:** <>

### Goal
<one paragraph>

### Scope (in)
- <bullet>

### Scope (out)
- <bullet>

### Child issues
- [ ] #NN

### Exit criteria
- <measurable>
```

#### 7B.4 From milestone to PR

1. **Open the milestone.** Create one epic issue per milestone theme (e.g., "Tier 1 — Stat-boost actions"). Create one card issue per card, linked as children of the epic.
2. **Work the issues in dependency order.** Tier 0 before Tier 1 before Tier 2. Within a tier, primitive-dependent cards before primitive dependents.
3. **One card = one PR.** The PR closes its card issue on merge. The PR must ship with its unit tests green and must not break any existing integration-sweep test. (New cards are often excluded from the sweep until their whole tier is done — the sweep's kingdom selection can be gated on what is implemented.)
4. **Milestone closes** when every child issue is closed AND the milestone's integration sweep is green with the milestone's cards enabled.

One card is a unit of work around 200 lines and one focused hour once the primitives exist — small, reviewable, and individually testable.

#### 7B.5 Initial issue population

At the moment `dominion-grpc/` is initialized, these issues should exist up front so work can start immediately:

- **1 epic per milestone** (~10 epics)
- **1 issue per card** (26 kingdom cards + 7 basics = 33 card issues)
- **1 issue per engine primitive** (~15 primitives)
- **1 epic for "proto contract v1"** (Tier 0 proto + generated code + buf config)
- **1 epic for "Connect server skeleton"** (cmd/server/main.go + service layer shell)
- **1 epic for "bot library + event loop"**
- **1 epic for "integration sweep harness"**
- **1 epic for "CI pipeline"** (golangci-lint + buf lint + buf breaking + test workflows)

Total ~65 issues at project birth. The `superpowers:writing-plans` skill (next step after this brainstorm) is what actually drafts the text of each one.

---

## Open questions (none currently blocking)

- Exact bot strategy beyond BigMoney + SmithyBM — punted to Phase 3 ("smarter AI").
- Whether the dev-env repo and the project repo share the same name on GitHub or differ — leaning toward project = `dominion-grpc` on GitHub, dev-env stays as a personal/private setup repo. To be confirmed when the project repo is created.
- Logging format and verbosity in the engine — decided during implementation; not architectural.

---

## Next step

Invoke `superpowers:writing-plans` against this spec to produce the step-by-step implementation plan, which becomes the initial GitHub issue set described in Section 7B.5.
