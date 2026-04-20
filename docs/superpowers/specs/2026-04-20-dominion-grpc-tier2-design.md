# dominion-grpc — Tier 2 Design Spec (Cards with simple decisions)

**Status:** Brainstorming complete. All sections approved by user. Next step is to invoke `superpowers:writing-plans`.
**Date:** 2026-04-20
**Author of brainstorm:** Claude (Opus 4.6) with user
**Parent spec:** [2026-04-12-dominion-grpc-design.md](2026-04-12-dominion-grpc-design.md) — Tier 2 definition in Section 5.
**Scope reminder:** This spec covers **Phase 1a / Tier 2** only: ten cards with simple decisions, the decision/prompt system, two new engine primitives, a `PlayCardFromZone` helper, ChapelBM and RemodelBM strategies, and the corresponding proto changes.

---

## Confirmed decisions (locked-in choices from the brainstorm)

| Topic | Decision |
|---|---|
| **Execution model** | Continuation on card — each card gets an `OnResolve` callback called when `ResolveDecision` arrives |
| **Prompt/Answer types** | Interface + concrete structs (type-safe) |
| **Vassal "play from discard"** | Extract `PlayCardFromZone` helper, reusable for Throne Room in Tier 4 |
| **Multi-step context** | Stored on Decision itself (`Context map[string]any`) for inter-step data |
| **Optional trash (Moneylender/Mine)** | `TrashFromHandPrompt` with `Min: 0` — no separate YesNo step |
| **Bot strategies** | BigMoney/SmithyBM never buy Tier 2 cards, keep safe refusal. New ChapelBM (primary, done-criterion) + RemodelBM (secondary, no statistical gate) |
| **ChapelBM policy** | Trash Estates always, trash Coppers down to 3 remaining, buy 1 Chapel only, stop playing when deck is clean |
| **Poacher zero piles** | Skip decision entirely |
| **Harbinger empty discard** | Skip decision entirely. Prompt carries discard contents, no change to PlayerView |
| **Milestone sequencing** | Tier 0 > Tier 1 > **Tier 2** > Tier 3 > Tier 4 > Phase 1b > Tier 5 |

---

## Section 1 — Decision system (engine changes)

### 1.1 Expanded `Decision` struct

```go
type Decision struct {
    ID        string
    PlayerIdx int
    CardID    CardID            // which card created this decision
    Step      int               // 0-based step index for multi-step cards
    Prompt    Prompt            // what the player must choose
    Context   map[string]any    // inter-step data (e.g., "trashed_cost": 4)
}
```

### 1.2 Prompt and Answer interfaces

```go
type Prompt interface{ isPrompt() }
type Answer interface{ isAnswer() }
```

### 1.3 Concrete prompt types

| Prompt | Fields | Used by |
|---|---|---|
| `DiscardFromHandPrompt` | `Min, Max int` | Cellar, Poacher |
| `TrashFromHandPrompt` | `Min, Max int; TypeFilter []CardType; CardFilter []CardID` | Chapel, Moneylender, Remodel (step 1), Mine (step 1) |
| `GainFromSupplyPrompt` | `MaxCost int; TypeFilter []CardType; Dest GainDest` | Workshop, Remodel (step 2), Mine (step 2), Artisan (step 1) |
| `ChooseFromDiscardPrompt` | `Cards []CardID; Optional bool` | Harbinger |
| `PutOnDeckPrompt` | (no extra fields — always exactly 1 from hand) | Artisan (step 2) |
| `MayPlayActionPrompt` | `Card CardID` | Vassal |

### 1.4 Concrete answer types

| Answer | Fields | Responds to |
|---|---|---|
| `CardListAnswer` | `Cards []CardID` | DiscardFromHand, TrashFromHand |
| `CardChoiceAnswer` | `Card CardID; None bool` | GainFromSupply, ChooseFromDiscard, PutOnDeck |
| `YesNoAnswer` | `Yes bool` | MayPlayAction |

### 1.5 `RequestDecision` primitive

```go
func RequestDecision(s *GameState, playerIdx int, cardID CardID, step int, prompt Prompt, ctx map[string]any) []Event {
    s.PendingDecision = &Decision{
        ID:        generateDecisionID(s),
        PlayerIdx: playerIdx,
        CardID:    cardID,
        Step:      step,
        Prompt:    prompt,
        Context:   ctx,
    }
    return []Event{{Kind: EventDecisionRequested, PlayerIdx: playerIdx}}
}
```

`generateDecisionID` uses a simple counter on the game state (deterministic, no UUIDs).

New event kind: `EventDecisionRequested`.

### 1.6 `ResolveDecision` action expanded

```go
type ResolveDecision struct {
    PlayerIdx  int
    DecisionID string
    Answer     Answer
}
```

### 1.7 New path in `Apply`

```go
case ResolveDecision:
    d := s.PendingDecision
    if d == nil {
        return s, nil, ErrNoDecisionPending
    }
    if d.ID != act.DecisionID {
        return s, nil, ErrWrongDecisionID
    }
    card, ok := lookup(d.CardID)
    if !ok {
        return s, nil, ErrUnknownCard
    }
    s.PendingDecision = nil
    ev, err := card.OnResolve(s, d.PlayerIdx, d, act.Answer, lookup)
    return s, ev, err
```

New errors: `ErrNoDecisionPending`, `ErrWrongDecisionID`.

### 1.8 Who can resolve — deciding player bypass

When `PendingDecision` is set, `Apply` accepts `ResolveDecision` from the **deciding player** (`d.PlayerIdx`), not necessarily the current player. The existing `a.Player() != s.CurrentPlayer` check at the top of `Apply` is bypassed for `ResolveDecision`. This is correct for Tier 3 (attacks create decisions for other players) and should be implemented now.

When `PendingDecision` is set, non-`ResolveDecision` actions are rejected with an error — only resolve is legal while a decision is pending.

### 1.9 Card struct — new `OnResolve` field

```go
type Card struct {
    ID            CardID
    Name          string
    Cost          int
    Types         []CardType
    OnPlay        func(s *GameState, playerIdx int) []Event
    VictoryPoints func(p PlayerState) int
    OnReaction    func(s *GameState, playerIdx int, trigger Trigger) (activated bool, events []Event)
    OnResolve     func(s *GameState, p int, d *Decision, answer Answer, lookup CardLookup) []Event  // NEW
}
```

Cards without decisions leave `OnResolve` nil. The resolve path in `Apply` should check for nil `OnResolve` and return an error if a card somehow created a decision but has no resolve handler.

---

## Section 2 — `PlayCardFromZone` helper

Vassal plays a card from the discard pile. Currently `applyPlayCard` hardcodes hand-to-in-play movement. Extract the reusable part.

### 2.1 Zone type

```go
type Zone int

const (
    ZoneHand Zone = iota
    ZoneDiscard
)
```

### 2.2 `PlayCardFromZone` function

```go
func PlayCardFromZone(s *GameState, p int, cardID CardID, from Zone, lookup CardLookup) ([]Event, error) {
    card, ok := lookup(cardID)
    if !ok {
        return nil, ErrUnknownCard
    }
    ps := &s.Players[p]

    switch from {
    case ZoneHand:
        idx := indexOf(ps.Hand, cardID)
        if idx < 0 {
            return nil, ErrCardNotInHand
        }
        ps.Hand = append(ps.Hand[:idx], ps.Hand[idx+1:]...)
    case ZoneDiscard:
        idx := indexOf(ps.Discard, cardID)
        if idx < 0 {
            return nil, ErrCardNotInDiscard
        }
        ps.Discard = append(ps.Discard[:idx], ps.Discard[idx+1:]...)
    }

    ps.InPlay = append(ps.InPlay, cardID)
    events := []Event{{Kind: EventCardPlayed, PlayerIdx: p, CardID: cardID}}
    if card.OnPlay != nil {
        events = append(events, card.OnPlay(s, p)...)
    }
    return events, nil
}
```

New error: `ErrCardNotInDiscard`.

### 2.3 Refactored `applyPlayCard`

`applyPlayCard` keeps ownership of phase checks and action decrement, then delegates to `PlayCardFromZone(s, p, card, ZoneHand, lookup)`.

### 2.4 `OnResolve` receives `CardLookup`

Vassal's `OnResolve` needs `lookup` to call `PlayCardFromZone`. The `OnResolve` signature includes `lookup CardLookup` as the final parameter. Cards that don't need it ignore it.

---

## Section 3 — Card implementations

All 10 cards. Each card lives in its own file under `internal/engine/cards/`.

### 3.1 Cellar ($2)

*+1 action, discard any number from hand, draw that many.*

```
OnPlay:    AddActions +1, RequestDecision(DiscardFromHandPrompt{Min: 0, Max: handSize})
OnResolve: DiscardFromHand(chosen), DrawCards(len(chosen))
```

One step. Discarding 0 is legal.

### 3.2 Chapel ($2)

*Trash up to 4 cards from hand.*

```
OnPlay:    RequestDecision(TrashFromHandPrompt{Min: 0, Max: 4})
OnResolve: TrashFromHand(chosen)
```

One step. Trashing 0 is legal.

### 3.3 Harbinger ($3)

*+1 card, +1 action, look at discard pile, may put one on top of deck.*

```
OnPlay:    DrawCards 1, AddActions +1
           if discard is empty -> return (no decision)
           RequestDecision(ChooseFromDiscardPrompt{Cards: discard contents, Optional: true})
OnResolve: if None -> do nothing
           else -> remove chosen from discard, PutOnDeck
```

One step. Skips decision on empty discard.

### 3.4 Vassal ($3)

*Discard the top card of your deck. If it's an Action card, you may play it.*

```
OnPlay:    if deck empty and discard empty -> return (nothing to discard)
           RevealAndDiscardFromDeck(1)
           if discarded card is an Action ->
               RequestDecision(MayPlayActionPrompt{Card: discardedCard})
               Context: {"card": discardedCard}
           else -> return (no decision)
OnResolve: if Yes -> PlayCardFromZone(s, p, card, ZoneDiscard, lookup)
           if No -> do nothing
```

One step. The discarded card stays in discard until the player says yes.

### 3.5 Workshop ($3)

*Gain a card costing up to 4.*

```
OnPlay:    RequestDecision(GainFromSupplyPrompt{MaxCost: 4, Dest: GainToDiscard})
OnResolve: validate cost <= 4, GainCard(chosen, GainToDiscard)
```

One step.

### 3.6 Moneylender ($4)

*You may trash a Copper from hand; if you do, +3 coins.*

```
OnPlay:    if no Copper in hand -> return (no decision, no effect)
           RequestDecision(TrashFromHandPrompt{Min: 0, Max: 1, CardFilter: ["copper"]})
OnResolve: if empty -> do nothing
           TrashFromHand(copper), AddCoins +3
```

One step. `Min: 0` makes it optional. `CardFilter` restricts to Copper only.

### 3.7 Poacher ($4)

*+1 card, +1 action, +1 coin, discard 1 card per empty supply pile.*

```
OnPlay:    DrawCards 1, AddActions +1, AddCoins +1
           emptyPiles := count empty supply piles
           if emptyPiles == 0 -> return (no decision)
           RequestDecision(DiscardFromHandPrompt{Min: emptyPiles, Max: emptyPiles})
OnResolve: DiscardFromHand(chosen)
```

One step. Skips decision when zero piles are empty.

### 3.8 Remodel ($4)

*Trash a card from hand, gain a card costing up to 2 more than the trashed card.*

```
OnPlay:    if hand is empty -> return (nothing to trash)
           RequestDecision(TrashFromHandPrompt{Min: 1, Max: 1}, step=0)
OnResolve step 0: TrashFromHand(chosen)
           trashedCost := lookup(chosen).Cost
           RequestDecision(GainFromSupplyPrompt{MaxCost: trashedCost+2, Dest: GainToDiscard}, step=1)
           Context: {"trashed_cost": trashedCost}
OnResolve step 1: validate cost <= Context["trashed_cost"]+2
           GainCard(chosen, GainToDiscard)
```

Two steps.

### 3.9 Mine ($5)

*You may trash a Treasure from hand; gain a Treasure costing up to 3 more than it, to hand.*

```
OnPlay:    if no Treasure in hand -> return (no decision, no effect)
           RequestDecision(TrashFromHandPrompt{Min: 0, Max: 1, TypeFilter: [TypeTreasure]}, step=0)
OnResolve step 0: if empty -> do nothing (opted out)
           TrashFromHand(chosen)
           trashedCost := lookup(chosen).Cost
           RequestDecision(GainFromSupplyPrompt{MaxCost: trashedCost+3, TypeFilter: [TypeTreasure], Dest: GainToHand}, step=1)
           Context: {"trashed_cost": trashedCost}
OnResolve step 1: validate cost <= Context["trashed_cost"]+3, validate is Treasure
           GainCard(chosen, GainToHand)
```

Two steps. Optional at step 0.

### 3.10 Artisan ($6)

*Gain a card costing up to 5 to your hand, then put a card from your hand onto your deck.*

```
OnPlay:    RequestDecision(GainFromSupplyPrompt{MaxCost: 5, Dest: GainToHand}, step=0)
OnResolve step 0: GainCard(chosen, GainToHand)
           RequestDecision(PutOnDeckPrompt{}, step=1)
OnResolve step 1: remove chosen from hand, PutOnDeck
```

Two steps. Neither is optional.

---

## Section 4 — New engine primitives

### 4.1 `PutOnDeck`

```go
func PutOnDeck(s *GameState, p int, cards []CardID) []Event
```

Removes each card from hand and appends to top of deck. Used by Harbinger and Artisan.

### 4.2 `RevealAndDiscardFromDeck`

```go
func RevealAndDiscardFromDeck(s *GameState, p int, n int) ([]CardID, []Event)
```

Reveals top N cards of the deck (may trigger shuffle if deck is empty but discard has cards), moves them to discard. Returns the revealed card IDs so the caller can inspect them (Vassal checks if it's an Action). If deck and discard are both empty, returns empty.

---

## Section 5 — Proto changes

### 5.1 Decision message — add prompt oneof

```protobuf
message Decision {
    string id = 1;
    int32 player_idx = 2;
    string card_id = 3;
    int32 step = 4;

    oneof prompt {
        DiscardFromHandPrompt discard_from_hand = 5;
        TrashFromHandPrompt trash_from_hand = 6;
        GainFromSupplyPrompt gain_from_supply = 7;
        ChooseFromDiscardPrompt choose_from_discard = 8;
        PutOnDeckPrompt put_on_deck = 9;
        MayPlayActionPrompt may_play_action = 10;
    }
}
```

### 5.2 Prompt messages

```protobuf
message DiscardFromHandPrompt {
    int32 min = 1;
    int32 max = 2;
}

message TrashFromHandPrompt {
    int32 min = 1;
    int32 max = 2;
    repeated CardType type_filter = 3;
    repeated string card_filter = 4;
}

message GainFromSupplyPrompt {
    int32 max_cost = 1;
    repeated CardType type_filter = 2;
    GainDest dest = 3;
}

message ChooseFromDiscardPrompt {
    repeated string cards = 1;
    bool optional = 2;
}

message PutOnDeckPrompt {}

message MayPlayActionPrompt {
    string card_id = 1;
}
```

### 5.3 New enums

`GainDest` and `CardType` enums — reuse if they already exist in `common.proto` or `card.proto`, otherwise add them.

```protobuf
enum GainDest {
    GAIN_DEST_UNSPECIFIED = 0;
    GAIN_DEST_DISCARD = 1;
    GAIN_DEST_HAND = 2;
    GAIN_DEST_DECK = 3;
}
```

### 5.4 ResolveDecision message — add answer oneof

```protobuf
message ResolveDecision {
    string decision_id = 1;
    int32 player_idx = 2;

    oneof answer {
        CardListAnswer card_list = 3;
        CardChoiceAnswer card_choice = 4;
        YesNoAnswer yes_no = 5;
    }
}

message CardListAnswer {
    repeated string cards = 1;
}

message CardChoiceAnswer {
    string card = 1;
    bool none = 2;
}

message YesNoAnswer {
    bool yes = 1;
}
```

### 5.5 Backwards compatibility

All new fields are additive — new `oneof` variants and new messages. No existing field numbers change. `buf breaking` passes.

---

## Section 6 — Service layer changes

### 6.1 Prompt/Answer translation

Two new functions in `translate.go`:

- `PromptToProto(p engine.Prompt) -> proto Decision prompt oneof` — maps each engine prompt struct to its proto message.
- `AnswerFromProto(d *pb.Decision, r *pb.ResolveDecision) -> engine.Answer` — maps the proto answer oneof back to the engine answer struct. Takes the Decision to validate the answer type matches the prompt type.

### 6.2 `ActionFromProto` update

The existing `ResolveDecision` case in `ActionFromProto` needs to call `AnswerFromProto` to populate the `Answer` field on the engine's `ResolveDecision` action.

### 6.3 `SnapshotFromState` update

Already includes `pending_decision`. Now translates the engine's `Decision` (with prompt) into the proto `Decision`. Prompt contents are public information — no scrubbing needed.

### 6.4 `DecisionRequested` event emission

When the engine emits `EventDecisionRequested`, the `fanOut` function sends a `DecisionRequested` stream event so clients learn about pending decisions without waiting for the next full snapshot. The proto message `StreamGameEventsResponse.decision` already exists.

### 6.5 Deciding player bypass

Engine-level change (Section 1.8). No service-layer pre-validation to adjust — `SubmitAction` already passes the action through to `engine.Apply` without checking the player.

---

## Section 7 — Bot strategies

### 7.1 ChapelBM (done-criterion strategy)

**Buy policy:**
- Buy 1 Chapel on turns 1-2 (whichever comes first with $2+ coins)
- After owning 1 Chapel, never buy another
- Otherwise BigMoney: Province at $8, Gold at $6, Silver at $3

**Action phase — play policy:**
- Play Chapel if in hand and there are trashable cards (Estates, or Coppers above threshold)
- No other action cards purchased or played

**Resolve policy (Chapel prompt):**
- Trash all Estates in hand (up to 4 slots)
- Fill remaining slots with Coppers, keeping at least 3 Coppers in total deck
- Track total Coppers remaining via `trashedCount map[string]int` on the strategy struct: `7 (starting) - trashedCount["copper"]`

### 7.2 RemodelBM (secondary strategy, no statistical gate)

**Buy policy:**
- Buy 1 Remodel on turns 1-4
- Otherwise BigMoney: Province at $8, Gold at $6, Silver at $3

**Action phase — play policy:**
- Play Remodel if in hand

**Resolve policy:**
- Step 0 (trash): Trash an Estate if in hand, otherwise trash the lowest-value card
- Step 1 (gain): Gain the most expensive card available within the cost limit, preferring Province > Gold > Silver

### 7.3 Safe refusal updates

`safeRefusal` returns a valid minimal answer per prompt type:

| Prompt | Safe refusal answer |
|---|---|
| DiscardFromHand (Min: 0) | `CardListAnswer{Cards: []}` |
| DiscardFromHand (Min > 0) | Pick the first N cards from hand |
| TrashFromHand | `CardListAnswer{Cards: []}` |
| GainFromSupply | Pick the cheapest available card within MaxCost |
| ChooseFromDiscard | `CardChoiceAnswer{None: true}` |
| PutOnDeck | Pick the first card in hand |
| MayPlayAction | `YesNoAnswer{Yes: false}` |

BigMoney and SmithyBM never buy Tier 2 cards — safe refusal is only hit if forced into a decision by another card's effect.

### 7.4 Existing strategies unchanged

BigMoney and SmithyBM skip all Tier 2 cards in their buy policy. Their `Resolve` method uses safe refusal. No other changes.

---

## Section 8 — Testing strategy

### 8.1 Engine unit tests — per card

One test file per card in `internal/engine/cards/`. Each covers:

- Happy path (card effect with normal hand/deck)
- OnPlay sets correct prompt type with correct Min/Max/filters
- OnResolve applies answer correctly (state changes match)
- Empty answer where optional (trash/discard nothing is legal)
- Invalid answer (wrong card count, card not in hand, cost too high -> error)
- Multi-step flow (Remodel/Mine/Artisan): step 0 -> resolve -> step 1 -> resolve -> final state
- Edge cases: empty deck/discard (Harbinger skips, Vassal has nothing)
- Game-ended guard

### 8.2 Primitive tests

| Primitive | Key tests |
|---|---|
| `RequestDecision` | Sets PendingDecision, returns EventDecisionRequested |
| `PutOnDeck` | Card moves from hand to top of deck, hand shrinks |
| `RevealAndDiscardFromDeck` | Returns revealed cards, moves to discard, handles empty deck |
| `PlayCardFromZone` | Plays from hand, plays from discard, card not found errors |

### 8.3 Decision system tests (in `apply_test.go`)

- ResolveDecision with no pending -> `ErrNoDecisionPending`
- ResolveDecision with wrong ID -> `ErrWrongDecisionID`
- Non-resolve action while decision pending -> error
- Resolve from deciding player (not current player) -> accepted
- Multi-step: resolve step 0 sets new pending with step=1

### 8.4 Bot strategy tests

- ChapelBM buys Chapel on turns 1-2 at $2+
- ChapelBM stops buying Chapel after owning 1
- ChapelBM trashes Estates before Coppers
- ChapelBM keeps 3 Coppers (stops trashing at threshold)
- RemodelBM two-step resolve returns correct answers
- Safe refusal returns valid minimal answer per prompt type

### 8.5 Done-criterion

- **ChapelBM sweep:** 200 games, seats alternated by seed parity, threshold `chapelBM_wins / total >= 0.55`
- **Integration sweep:** 1000 games, random kingdoms from all Tier 0-2 cards, random strategy pairs (BigMoney, SmithyBM, ChapelBM, RemodelBM). Must complete without errors, panics, or conservation violations.

### 8.6 Service layer tests

- Submit `ResolveDecision` proto -> engine receives correct `Answer`
- Submit `ResolveDecision` when no decision pending -> `FailedPrecondition`
- Snapshot includes populated `Decision` with prompt fields
- `DecisionRequested` event is sent on stream

---

## Scope boundaries

**Ships in this tier:**

1. Decision system (engine: Decision, Prompt, Answer, RequestDecision, ResolveDecision path in Apply, deciding-player bypass)
2. `PlayCardFromZone` helper + `applyPlayCard` refactor
3. New primitives: `PutOnDeck`, `RevealAndDiscardFromDeck`
4. Ten kingdom cards: Cellar, Chapel, Harbinger, Vassal, Workshop, Moneylender, Poacher, Remodel, Mine, Artisan
5. Proto changes: prompt oneof on Decision, answer oneof on ResolveDecision, prompt/answer messages, GainDest enum
6. Service layer: prompt/answer translation, DecisionRequested event emission
7. Bot strategies: ChapelBM (done-criterion), RemodelBM (secondary)
8. Done-criterion test: 200-game ChapelBM vs BigMoney sweep
9. Integration sweep updated to include Tier 2 cards and strategies

**Explicitly NOT in this tier:**

- Attacks, reactions, or the reaction system (Tier 3)
- Throne Room, Library, Sentry (Tier 4)
- Gardens, Merchant (Tier 5)
- RandomActionBot / random-action property coverage
- Persistence, CI pipeline, React frontend
- Event-model evolution (still full snapshot per SubmitAction)
