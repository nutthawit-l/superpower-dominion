# dominion-grpc — Tier 1 Design Spec (Pure stat-boost actions)

**Status:** Brainstorming complete. All sections approved by user. Next step is to invoke `superpowers:writing-plans`.
**Date:** 2026-04-18
**Author of brainstorm:** Claude (Opus 4.7) with user
**Parent spec:** [2026-04-12-dominion-grpc-design.md](2026-04-12-dominion-grpc-design.md) — Tier 1 definition in Section 5.
**Scope reminder:** This spec covers **Phase 1a / Tier 1** only: six pure stat-boost action cards, one new engine primitive, optional kingdom selection, the SmithyBM strategy, and a per-subscriber viewer fanout fix in the service layer.

---

## Confirmed decisions (locked-in choices from the brainstorm)

| Topic | Decision |
|---|---|
| **Kingdom selection shape** | Option C — `NewGame` takes a `kingdom []CardID` parameter; empty/nil → "all registered kingdom cards." `CreateGameRequest` gets an optional `kingdom_card_ids` field. |
| **Scope of this tier** | Cards + `EachOtherPlayer` + SmithyBM + done-criterion test + fix per-subscriber viewer fanout in service layer. Event-model evolution (typed deltas) deferred to a later tier. |
| **Done-criterion test** | Statistical sweep: 200 games, threshold `smithyBM_wins / total >= 0.55`. Seats alternated each game to neutralize starting-player advantage. |
| **SmithyBM — Smithy count cap** | 2 Smithys in the deck. |
| **SmithyBM — late-game Smithy policy** | Strict "no Smithy buys after turn 4." |
| **SmithyBM — play ordering** | Simple: play Smithy if in hand and `Actions >= 1`. No chaining. |
| **Property-test RandomActionBot** | Not in this tier. Coverage of the six new cards comes from unit tests + the SmithyBM sweep. |

---

## Section 1 — Scope

**Ships in this tier:**

1. **Six kingdom cards:**
   - Village (+1 card, +2 actions)
   - Smithy (+3 cards)
   - Festival (+2 actions, +1 buy, +2 coins)
   - Laboratory (+2 cards, +1 action)
   - Market (+1 card, +1 action, +1 buy, +1 coin)
   - Council Room (+4 cards, +1 buy, each other player draws 1)
2. **One new engine primitive:** `EachOtherPlayer` (used by Council Room; Tier 3 attacks will also use it).
3. **Optional kingdom selection:** `NewGame` accepts a `kingdom []CardID` parameter; empty = all registered kingdom cards. `CreateGameRequest` gets an optional `kingdom_card_ids` field (additive proto change).
4. **SmithyBM strategy** with the locked behavior: play Smithy if hand has it and `Actions >= 1`; cap at 2 Smithys owned; no Smithy buys after the bot's 4th turn.
5. **Per-subscriber viewer fanout fix** — the service layer tracks `viewer` per subscriber channel and sends a per-viewer scrubbed snapshot on every fanOut.
6. **Done-criterion test:** a 200-game SmithyBM vs BigMoney sweep with threshold `smithyBM_wins / total >= 0.55`. Seats alternated by seed parity.

**Explicitly NOT in this tier:**

- RandomActionBot / random-action property coverage.
- Event-model evolution (still "full snapshot per SubmitAction" — typed events can come with Tier 2 decisions).
- Persistence, CI pipeline, React frontend.
- Any card from Tier 2–5.

---

## Section 2 — Engine changes

### 2.1 New primitive: `EachOtherPlayer`

```go
// EachOtherPlayer calls fn(idx) for every player except `except`, in
// turn order starting at the next seat, wrapping around. Returns the
// concatenation of all events fn returns.
func EachOtherPlayer(s *GameState, except int, fn func(idx int) []Event) []Event
```

Iteration order is **next seat first, wrapping** — matches Dominion's turn-order convention for attacks (Tier 3 will need this). For Council Room (order-invariant effect) it doesn't matter; fixing the order now keeps the primitive correct for its future users.

### 2.2 `NewGame` signature change

```go
func NewGame(gameID string, playerNames []string, kingdom []CardID, seed int64, lookup CardLookup) (*GameState, error)
```

- `kingdom == nil || len(kingdom) == 0` → use all registered kingdom cards. "Kingdom card" = any card in `DefaultRegistry` whose `Types` contain `TypeAction`.
- Supply piles: basics unchanged from Tier 0 — Copper 46, Silver 40, Gold 30, Estate 8, Duchy 8, Province 8, Curse 10 (2-player Base 2e counts).
- Each kingdom card in the resulting supply gets **10 copies** (Base 2e standard for Action kingdom cards, 2-player count).
- Validates that each `CardID` in `kingdom` is known via `lookup`. Unknown ID → error. Duplicates in the `kingdom` slice are collapsed to a single pile.

Callers (currently only `service.GameService.CreateGame`) pass `nil` until the RPC plumbs it through (Section 4).

### 2.3 Kingdom-card classification

Helper on `*Card`:

```go
func (c *Card) IsKingdom() bool { return c.HasType(TypeAction) }
```

All six Tier 1 cards qualify. Basics (Copper/Silver/Gold), victories (Estate/Duchy/Province), and Curse do not (they lack `TypeAction`). Later tiers add Reaction cards which also carry `TypeAction`, so this classification remains correct.

### 2.4 What does NOT change

- `Apply` — no new action types; all six cards reuse `PlayCard` (already dispatches through `card.OnPlay`).
- Phase state machine, `DrawCards`, `AddActions`, `AddBuys`, `AddCoins`, `GainCard`, `DiscardFromHand` — unchanged.
- Cleanup logic — unchanged. Village/Festival's `Actions`/`Buys` reset to 0 naturally as part of existing cleanup (resources are derived, not persistent).
- RNG — no new random operations introduced.

---

## Section 3 — The six kingdom cards

Each lives in its own file under `internal/engine/cards/`, registered via `init()` — same pattern as `basics_treasure.go` and `basics_victory.go`. All five non-Council-Room cards compose existing primitives only.

### 3.1 Village — `kingdom_village.go`, cost 3, Action

```go
OnPlay: draw 1, +2 actions.
// DrawCards(s, p, 1) ++ AddActions(s, p, 2)
```

### 3.2 Smithy — `kingdom_smithy.go`, cost 4, Action

```go
OnPlay: draw 3.
// DrawCards(s, p, 3)
```

### 3.3 Festival — `kingdom_festival.go`, cost 5, Action

```go
OnPlay: +2 actions, +1 buy, +2 coins.
// AddActions(s, p, 2) ++ AddBuys(s, p, 1) ++ AddCoins(s, p, 2)
```

### 3.4 Laboratory — `kingdom_laboratory.go`, cost 5, Action

```go
OnPlay: draw 2, +1 action.
// DrawCards(s, p, 2) ++ AddActions(s, p, 1)
```

### 3.5 Market — `kingdom_market.go`, cost 5, Action

```go
OnPlay: draw 1, +1 action, +1 buy, +1 coin.
// DrawCards(s, p, 1) ++ AddActions(s, p, 1) ++ AddBuys(s, p, 1) ++ AddCoins(s, p, 1)
```

### 3.6 Council Room — `kingdom_council_room.go`, cost 5, Action

The only card in this tier that touches `EachOtherPlayer`.

```go
OnPlay:
  - DrawCards(s, p, 4)
  - AddBuys(s, p, 1)
  - EachOtherPlayer(s, p, func(idx int) []Event {
        return DrawCards(s, idx, 1)
    })
```

The other players' drawn cards surface naturally in the next fanOut snapshot (per-viewer scrubbed), since Section 5's fanout runs after all events from `Apply` complete.

### 3.7 File naming & registry

Filenames are prefixed `kingdom_` to visually separate from `basics_*`. Each file:

```go
func init() { DefaultRegistry.Register(&Village) }
```

No central list of kingdom cards. `NewGame` discovers them by iterating `DefaultRegistry.All()` and filtering `(*Card).IsKingdom()`.

---

## Section 4 — Proto changes

One additive change to one message.

### 4.1 `CreateGameRequest` — optional kingdom list

```proto
message CreateGameRequest {
  repeated string players = 1;             // strategy identifiers
  int64           seed    = 2;
  repeated string kingdom_card_ids = 3;    // NEW — empty = server default
}
```

- Field 3 is optional (`repeated` is implicitly optional). Existing clients passing no field get the server default ("all registered kingdom cards").
- Field numbers 1 and 2 unchanged → `buf breaking` passes.
- Unknown card IDs → `InvalidArgument` Connect error.

### 4.2 No changes elsewhere

- `SubmitAction`, `StreamGameEvents`, `Action`, `StreamGameEventsResponse`, `PlayerView`, `GameStateSnapshot` — all unchanged.
- Tier 1 cards produce no new event kinds; the existing snapshot-per-action model covers everything including Council Room's out-of-turn draws.
- Prompt / Decision messages remain unused in Tier 1 (arrive in Tier 2).

### 4.3 Regeneration

`make generate` regenerates `gen/go/`. The regenerated Go code is committed alongside the `.proto` change, per the existing repo rule ("`buf generate` result is committed to git").

---

## Section 5 — Service-layer changes

### 5.1 Plumb `kingdom_card_ids` into `NewGame`

In `CreateGame`:

```go
kingdom := make([]engine.CardID, len(req.Msg.KingdomCardIds))
for i, id := range req.Msg.KingdomCardIds {
    kingdom[i] = engine.CardID(id)
}
s, err := engine.NewGame(id, names, kingdom, req.Msg.Seed, g.lookup)
```

Validation (unknown IDs) happens inside `NewGame`; the service translates the resulting `error` to `InvalidArgument`.

### 5.2 Per-subscriber viewer fanout

Today, `subs map[string][]chan *pb.StreamGameEventsResponse` stores just channels, and `fanOut` always sends the viewer=0 snapshot to every subscriber (see [game_service.go:108-113](../../../dominion-grpc/internal/service/game_service.go) — comment explicitly notes "Tier 1 will track per-subscriber viewer indices").

Upgrade to track viewer per subscriber:

```go
type subscriber struct {
    ch     chan *pb.StreamGameEventsResponse
    viewer int
}

subs map[string][]subscriber
```

- `StreamGameEvents` appends `subscriber{ch, int(req.Msg.PlayerIdx)}` on registration (existing code already reads `viewer` — it just wasn't propagated to fanOut).
- `fanOut` builds one scrubbed snapshot per *distinct* viewer seen in the subscriber list, then sends each subscriber its matching response. Concretely: group subscribers by viewer, call `SnapshotFromState(s, viewer)` once per group, wrap in `StreamGameEventsResponse{Sequence: seq, Kind: Snapshot{...}}`, deliver.
- The `EventGameEnded` branch still sends a single `GameEnded` response to every subscriber regardless of viewer (game-end is not viewer-specific).

### 5.3 Sequence numbering unchanged

One `seq` counter per game; every subscriber sees the same sequence number for the same `SubmitAction` — different payload (their own scrubbed snapshot), same sequence. This preserves the bot's existing gap-detection logic.

### 5.4 Initial snapshot

`StreamGameEvents`'s existing "send `Sequence: 0` snapshot on subscribe" already uses `viewer` correctly — no change needed there.

### 5.5 Tests

- New service-level test (`TestStreamGameEvents_PerViewerScrubbing`): two subscribers at seats 0 and 1, one `SubmitAction`, assert each receives a snapshot whose only-unscrubbed hand is its own seat's.
- Existing `CreateGame` / `SubmitAction` / streaming tests continue to pass — the viewer fix is orthogonal to their assertions.

---

## Section 6 — Bot changes

### 6.1 SmithyBM strategy — `internal/bot/smithy_bm.go`

```go
type SmithyBM struct{}

func (SmithyBM) Name() string { return "smithy_bm" }

func (SmithyBM) PickAction(cs *ClientState) *pb.Action {
    me := cs.MyPlayer()
    if me == nil { return endPhase(cs.Me) }

    switch cs.Phase {
    case pb.Phase_PHASE_ACTION:
        if me.Actions >= 1 && handContains(me.Hand, "smithy") {
            return playCard(cs.Me, "smithy")
        }
        return endPhase(cs.Me)

    case pb.Phase_PHASE_BUY:
        for _, c := range me.Hand {
            if isTreasure(c) { return playCard(cs.Me, c) }
        }
        smithysOwned := countOwned(me, "smithy")
        earlyTurn := cs.MyTurnsTaken <= 4
        switch {
        case me.Coins >= 8:
            return buyCard(cs.Me, "province")
        case me.Coins >= 6:
            return buyCard(cs.Me, "gold")
        case me.Coins >= 4 && earlyTurn && smithysOwned < 2:
            return buyCard(cs.Me, "smithy")
        case me.Coins >= 3:
            return buyCard(cs.Me, "silver")
        }
        return endPhase(cs.Me)
    }
    return endPhase(cs.Me)
}

func (SmithyBM) Resolve(cs *ClientState, d *pb.Decision) *pb.ResolveDecision {
    return safeRefusal(d)
}
```

`countOwned(me, id)` counts across `Hand + Deck + Discard + InPlay` — the full deck composition as visible in the player's own scrubbed snapshot.

Both guards (`smithysOwned < 2` AND `earlyTurn`) enforce the locked behavior: cap at 2, strict cutoff after turn 4.

### 6.2 `ClientState.MyTurnsTaken`

Add a counter. The server currently only fans out `Snapshot` and `Ended` responses (the engine's `EventTurnStarted` is produced in `phases.go` but not translated to a proto `TurnStarted` response — the reducer's `TurnStarted` case is effectively dead code today). So the bot derives `MyTurnsTaken` from snapshot transitions rather than a dedicated event. Two fields on `ClientState`:

```go
MyTurnsTaken int
LastMyTurn   int  // the `Turn` value of the most recent turn counted as mine
```

Update inside the snapshot branch of `Apply`:

```go
case *pb.StreamGameEventsResponse_Snapshot:
    cs.Snapshot = k.Snapshot
    cs.Phase = k.Snapshot.Phase
    cs.Turn = int(k.Snapshot.Turn)
    cs.CurrentPlayer = int(k.Snapshot.CurrentPlayer)
    // ... existing fields ...
    if cs.CurrentPlayer == cs.Me && cs.Turn != cs.LastMyTurn {
        cs.MyTurnsTaken++
        cs.LastMyTurn = cs.Turn
    }
```

Properties:

- Increments **once per turn**, not once per action, because the guard `cs.Turn != cs.LastMyTurn` blocks re-counting within a single turn (multiple snapshots arrive per turn, one per `SubmitAction`).
- Handles the fresh-game starting-player case naturally: initial snapshot has `Turn == 1` and `CurrentPlayer == cs.Me`, `LastMyTurn == 0`, so `MyTurnsTaken` becomes `1`.
- Handles the fresh-game non-starter case naturally: initial snapshot has `CurrentPlayer != cs.Me`, so nothing increments until the first snapshot after my opponent ends their first buy phase (which carries `CurrentPlayer == cs.Me` and `Turn == 2`).
- Reconnect mid-game re-subscribes and receives a fresh snapshot. `MyTurnsTaken` will be re-initialized from scratch starting at the reconnect moment — acceptable for Tier 1 since the integration sweep never reconnects; a precise reconnect bootstrap is deferred.

The reducer's existing `StreamGameEventsResponse_TurnStarted` case stays in place (harmless dead code) for when Tier 2+ starts emitting typed events.

### 6.3 Strategy registration

`internal/bot/strategy.go` gains a lookup:

```go
func StrategyByName(name string) Strategy {
    switch name {
    case "bigmoney":  return BigMoney{}
    case "smithy_bm": return SmithyBM{}
    }
    return nil
}
```

`cmd/bot/main.go` uses this to map the `-strategy` flag to a concrete strategy. The service layer will eventually use the same mechanism to instantiate per-seat strategies when a CreateGame request names them.

### 6.4 BigMoney play-order note

No change to `BigMoney`. It already ends the Action phase immediately — the six new action cards don't affect it.

### 6.5 Kingdom composition for the done-criterion sweep

For the 200-game SmithyBM-vs-BigMoney sweep, the kingdom **must include Smithy** but should not include other Tier 1 cards, because BigMoney never buys kingdoms and SmithyBM only buys Smithy — extras just waste supply space and add noise. Sweep kingdom = `["smithy"]`. Per-card correctness comes from unit tests, not the sweep.

---

## Section 7 — Testing strategy

### 7.1 Engine unit tests

One file per card, table-driven, following the Tier 0 pattern (`basics_treasure_test.go`):

| File | Coverage |
|---|---|
| `kingdom_village_test.go` | +1 card / +2 actions; empty deck draws 0; plays when Actions = 1 (after play, Actions = 2); action-phase guard |
| `kingdom_smithy_test.go` | +3 cards; partial draw on short deck + discard; 0 cards when both empty; already-ended guard |
| `kingdom_festival_test.go` | +2 actions / +1 buy / +2 coins; stacking with prior resources |
| `kingdom_laboratory_test.go` | +2 cards / +1 action; empty deck behavior |
| `kingdom_market_test.go` | +1 card / +1 action / +1 buy / +1 coin |
| `kingdom_council_room_test.go` | Self draws 4, each other player draws 1, +1 buy; 3-player variant (all three "other" players draw 1) to prove the engine function is N-safe even though Tier 1 only ships 2-player |

### 7.2 Primitive unit test

`engine/primitives_test.go` gains `TestEachOtherPlayer_IterationOrder`: 4-player fixture, `except = 1`, expect callback order `[2, 3, 0]`.

### 7.3 NewGame unit tests

`engine/newgame_test.go` extended:

- Default (nil / empty kingdom): supply contains all 6 Tier 1 kingdom IDs, 10 each.
- Explicit kingdom `["smithy", "village"]`: supply contains exactly those two + basics.
- Unknown card ID: returns error.
- Duplicate IDs in `kingdom`: supply has one pile of 10.

### 7.4 Service-layer tests

- `TestGameService_CreateGame_WithKingdom`: proto carries `kingdom_card_ids`; resulting game state has the requested supply.
- `TestGameService_CreateGame_UnknownKingdomCard`: unknown ID → `InvalidArgument`.
- `TestStreamGameEvents_PerViewerScrubbing`: two subscribers at seats 0 and 1, one `SubmitAction`, assert each snapshot unscrubs only its own seat's hand.

### 7.5 Engine property tests

No new properties. The existing 500-seed property sweep (`properties_test.go`) still passes. Since no RandomActionBot is in scope, the sweep does not yet randomly play Tier 1 cards; coverage of those cards comes from unit tests + the SmithyBM sweep.

### 7.6 SmithyBM integration sweep

`internal/bot/integration_test.go` extended:

```go
func TestBotVsBot_SmithyBM_Outperforms_BigMoney(t *testing.T) {
    if testing.Short() { t.Skip("integration sweep") }

    const games = 200
    const threshold = 0.55
    wins := 0
    srv := newTestServer(t)
    defer srv.Close()

    for seed := int64(0); seed < games; seed++ {
        // Alternate seat assignment each game so starting-player
        // advantage averages out rather than always favoring one side.
        smithySeat := int(seed % 2)
        bmSeat := 1 - smithySeat
        strategies := []string{"", ""}
        strategies[smithySeat] = "smithy_bm"
        strategies[bmSeat] = "bigmoney"

        final := runOneGame(t, srv.URL, seed, []string{"smithy"}, strategies)
        if len(final.Winners) == 1 && int(final.Winners[0]) == smithySeat {
            wins++
        }
    }
    rate := float64(wins) / float64(games)
    require.GreaterOrEqualf(t, rate, threshold,
        "SmithyBM win rate %.2f below threshold %.2f over %d games", rate, threshold, games)
}
```

Alternating seats matters — a 200-game sweep where SmithyBM always sits at seat 0 conflates strategy strength with starting-player advantage. Alternating halves cancels it out.

Expected true win rate is ~0.67 (published Dominiate-style results); probability of the sweep falling below 0.55 with a correct engine/strategy is essentially zero.

### 7.7 Regression replay

No fixtures added in this tier. Format established in Tier 0; new replays are captured only when a bug surfaces.

### 7.8 Runtime budget

- `go test -short ./...` — unit tests + translation tests stay under 2s locally.
- `go test ./...` — adds the 500-seed property sweep + the 200-game SmithyBM sweep. Expected ≤15s total on the existing engine, well inside Section 7A's 60s whole-stack budget.

---

## Section 8 — Work ordering & milestones

Twelve reviewable units, each a separate PR closing one issue. Ordered so each PR lands with its own tests green on top of `main` without depending on unlanded work.

### Stage A — Infrastructure (unblocks the cards)

1. **Proto: add `kingdom_card_ids` to `CreateGameRequest`.** Regenerate `gen/go/`. Pure additive — no code changes beyond regeneration. `buf breaking` passes.
2. **Engine primitive: `EachOtherPlayer`.** Function + unit test. No consumers yet; fine to land alone.
3. **Engine: `NewGame` kingdom parameter.** Add `kingdom []CardID` argument, default-when-empty behavior, validation. Existing single caller (`service.CreateGame`) passes `nil` — no behavior change. Unit tests cover default / explicit / unknown-ID / duplicates.
4. **Service: plumb `kingdom_card_ids`.** Service reads the field and passes it through. Tests for default, explicit, and unknown-ID paths.
5. **Service: per-subscriber viewer fanout.** The `subs` map refactor + per-viewer snapshot group. Dedicated test for two subscribers at different seats.

### Stage B — The six cards (can land in any order once Stage A is in)

6. Village — `kingdom_village.go` + tests.
7. Smithy — `kingdom_smithy.go` + tests.
8. Festival — `kingdom_festival.go` + tests.
9. Laboratory — `kingdom_laboratory.go` + tests.
10. Market — `kingdom_market.go` + tests.
11. Council Room — `kingdom_council_room.go` + tests. Depends on #2 `EachOtherPlayer`.

### Stage C — Strategy + sweep (needs cards + viewer fanout)

12. **SmithyBM + `MyTurnsTaken` + integration sweep.** Single PR:
    - Add `MyTurnsTaken` to `ClientState` + reducer update + unit test.
    - Add `SmithyBM` strategy + unit tests (mock `ClientState`, assert picks).
    - Register in `StrategyByName`; wire through `cmd/bot/main.go`.
    - Add the 200-game sweep (`TestBotVsBot_SmithyBM_Outperforms_BigMoney`).

### GitHub milestone structure

Per Section 7B of the base spec:

- Milestone **"Phase 1a / Tier 1 — Pure stat-boost actions"** — 12 issues (one per PR above). One epic issue tracks the whole tier.
- Labels:
  - PRs 1, 4, 5 → `area:server`
  - PRs 2, 3 → `area:engine` + `kind:primitive`
  - PRs 6–11 → `area:engine` + `kind:card`
  - PR 12 → `area:bot`

### Milestone exit criteria

- All 12 issues closed.
- `go test ./...` green on `main`, including the 200-game SmithyBM sweep.
- `make generate` and `make lint` clean.
- README's "Quick start" snippet works with `-strategy smithy_bm`.

### Dependency graph

```
#1 proto ────┐
#2 EachOtherPlayer ─┐
#3 NewGame kingdom ─┼── #4 service plumb
                    │
                    └── #6..#10 (5 stat cards; any order)
                    └── #11 Council Room
#5 viewer fanout ───┘
                    └── #12 SmithyBM + sweep
```

---

## Open questions

None currently blocking. Items deferred by decision during brainstorming:

- RandomActionBot strategy + random-action property-sweep coverage of Tier 1 cards.
- Event-model evolution from "snapshot per action" to typed deltas — natural fit for Tier 2 when decisions arrive.
- Mid-game reconnect bootstrap for `MyTurnsTaken` — not exercised by Tier 1 tests.

---

## Next step

Invoke `superpowers:writing-plans` against this spec to produce the step-by-step implementation plan, matching the 12-PR structure in Section 8.
