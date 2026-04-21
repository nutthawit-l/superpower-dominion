# Phase 1a / Tier 2 Implementation Plan — Cards with simple decisions

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the decision/prompt system to the engine, implement 10 Tier 2 kingdom cards (Cellar, Chapel, Harbinger, Vassal, Workshop, Moneylender, Poacher, Remodel, Mine, Artisan), update the proto contract with prompt/answer types, add ChapelBM and RemodelBM bot strategies, and verify correctness via a 200-game ChapelBM vs BigMoney competitive-parity sweep (≥48%).

**Architecture:** The decision system adds `OnResolve` to `Card`, typed `Prompt`/`Answer` interfaces, and a `RequestDecision` primitive. When a card needs player input, `OnPlay` sets `PendingDecision` and returns. The engine rejects all non-`ResolveDecision` actions while a decision is pending. When `ResolveDecision` arrives, `Apply` calls the card's `OnResolve` with the typed answer. Multi-step cards chain by setting a new `PendingDecision` from within `OnResolve`. A `PlayCardFromZone` helper enables Vassal to play cards from the discard pile (reusable for Throne Room in Tier 4).

**Tech Stack:** Go 1.22+, Connect-Go RPC (`connectrpc.com/connect`), protobuf via `buf`, testing via stdlib `testing` + `github.com/stretchr/testify/require`, concurrency via `golang.org/x/sync/errgroup`.

**Working directory:** All commands below run from `/home/tie/superpower-dominion/dominion-grpc/` unless explicitly noted. This plan touches both the `dominion-grpc` subrepo (the actual project) and the outer `superpower-dominion` repo (docs only).

**Design source:** [docs/superpowers/specs/2026-04-20-dominion-grpc-tier2-design.md](../specs/2026-04-20-dominion-grpc-tier2-design.md)

---

## File Structure

Files created or modified in this plan:

| Stage | File | Purpose |
|---|---|---|
| A | `dominion-grpc/internal/engine/state.go` | Expand `Decision` struct, add `Prompt`/`Answer` interfaces, add `DecisionSeq` counter, add `EventDecisionRequested` |
| A | `dominion-grpc/internal/engine/types.go` | Add `Zone`, `GainDest` already exists, add new error vars |
| A | `dominion-grpc/internal/engine/decision.go` | New file: concrete prompt/answer types, `RequestDecision` primitive |
| A | `dominion-grpc/internal/engine/decision_test.go` | New file: test `RequestDecision` sets pending, generates deterministic IDs |
| A | `dominion-grpc/internal/engine/primitives.go` | Add `TrashFromHand`, `PutOnDeck`, `RevealAndDiscardFromDeck`, `PlayCardFromZone` |
| A | `dominion-grpc/internal/engine/primitives_test.go` | Tests for all new primitives |
| A | `dominion-grpc/internal/engine/card.go` | Add `OnResolve` field to `Card` |
| A | `dominion-grpc/internal/engine/action.go` | Expand `ResolveDecision` with `Answer` field |
| A | `dominion-grpc/internal/engine/apply.go` | Wire `ResolveDecision` path, decision-pending guard, deciding-player bypass |
| A | `dominion-grpc/internal/engine/apply_test.go` | Decision system tests |
| B | `dominion-grpc/proto/dominion/v1/common.proto` | Add `GainDest` enum |
| B | `dominion-grpc/proto/dominion/v1/game.proto` | Expand `Decision` and `ResolveDecision` with prompt/answer oneofs, add prompt/answer messages |
| B | `dominion-grpc/gen/go/dominion/v1/*.go` | Regenerated via `buf generate` |
| B | `dominion-grpc/internal/service/translate.go` | Add `DecisionToProto`, `PromptToProto`, `AnswerFromProto` |
| B | `dominion-grpc/internal/service/game_service.go` | Emit `DecisionRequested` event in `fanOut` |
| B | `dominion-grpc/internal/service/game_service_test.go` | Tests for decision translation and event emission |
| C | `dominion-grpc/internal/engine/cards/kingdom_cellar.go` | Cellar card |
| C | `dominion-grpc/internal/engine/cards/kingdom_cellar_test.go` | Cellar tests |
| C | `dominion-grpc/internal/engine/cards/kingdom_chapel.go` | Chapel card |
| C | `dominion-grpc/internal/engine/cards/kingdom_chapel_test.go` | Chapel tests |
| C | `dominion-grpc/internal/engine/cards/kingdom_harbinger.go` | Harbinger card |
| C | `dominion-grpc/internal/engine/cards/kingdom_harbinger_test.go` | Harbinger tests |
| C | `dominion-grpc/internal/engine/cards/kingdom_vassal.go` | Vassal card |
| C | `dominion-grpc/internal/engine/cards/kingdom_vassal_test.go` | Vassal tests |
| C | `dominion-grpc/internal/engine/cards/kingdom_workshop.go` | Workshop card |
| C | `dominion-grpc/internal/engine/cards/kingdom_workshop_test.go` | Workshop tests |
| C | `dominion-grpc/internal/engine/cards/kingdom_moneylender.go` | Moneylender card |
| C | `dominion-grpc/internal/engine/cards/kingdom_moneylender_test.go` | Moneylender tests |
| C | `dominion-grpc/internal/engine/cards/kingdom_poacher.go` | Poacher card |
| C | `dominion-grpc/internal/engine/cards/kingdom_poacher_test.go` | Poacher tests |
| C | `dominion-grpc/internal/engine/cards/kingdom_remodel.go` | Remodel card |
| C | `dominion-grpc/internal/engine/cards/kingdom_remodel_test.go` | Remodel tests |
| C | `dominion-grpc/internal/engine/cards/kingdom_mine.go` | Mine card |
| C | `dominion-grpc/internal/engine/cards/kingdom_mine_test.go` | Mine tests |
| C | `dominion-grpc/internal/engine/cards/kingdom_artisan.go` | Artisan card |
| C | `dominion-grpc/internal/engine/cards/kingdom_artisan_test.go` | Artisan tests |
| C | `dominion-grpc/internal/engine/cards/testutil_test.go` | Add helpers for decision-based card tests |
| D | `dominion-grpc/internal/bot/strategy.go` | Update `safeRefusal` to handle prompt types |
| D | `dominion-grpc/internal/bot/chapel_bm.go` | ChapelBM strategy |
| D | `dominion-grpc/internal/bot/chapel_bm_test.go` | ChapelBM unit tests |
| D | `dominion-grpc/internal/bot/remodel_bm.go` | RemodelBM strategy |
| D | `dominion-grpc/internal/bot/remodel_bm_test.go` | RemodelBM unit tests |
| D | `dominion-grpc/internal/bot/integration_test.go` | ChapelBM sweep + updated integration sweep |

---

## Stage A: Engine — Decision System + New Primitives

### Task 1: Prompt/Answer types and RequestDecision primitive

**Files:**
- Modify: `dominion-grpc/internal/engine/state.go`
- Modify: `dominion-grpc/internal/engine/types.go`
- Create: `dominion-grpc/internal/engine/decision.go`
- Create: `dominion-grpc/internal/engine/decision_test.go`

- [ ] **Step 1: Write the failing test for `RequestDecision`**

Create `dominion-grpc/internal/engine/decision_test.go`:

```go
package engine

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestRequestDecision_SetsPendingDecision(t *testing.T) {
	s := newTestState(2)
	prompt := DiscardFromHandPrompt{Min: 0, Max: 3}

	events := RequestDecision(s, 0, "cellar", 0, prompt, nil)

	require.NotNil(t, s.PendingDecision)
	require.Equal(t, 0, s.PendingDecision.PlayerIdx)
	require.Equal(t, CardID("cellar"), s.PendingDecision.CardID)
	require.Equal(t, 0, s.PendingDecision.Step)
	require.Equal(t, prompt, s.PendingDecision.Prompt)
	require.Len(t, events, 1)
	require.Equal(t, EventDecisionRequested, events[0].Kind)
}

func TestRequestDecision_DeterministicIDs(t *testing.T) {
	s := newTestState(2)
	RequestDecision(s, 0, "cellar", 0, DiscardFromHandPrompt{}, nil)
	id1 := s.PendingDecision.ID
	s.PendingDecision = nil

	RequestDecision(s, 0, "chapel", 0, TrashFromHandPrompt{}, nil)
	id2 := s.PendingDecision.ID

	require.NotEqual(t, id1, id2, "sequential decision IDs must differ")
}

func TestRequestDecision_WithContext(t *testing.T) {
	s := newTestState(2)
	ctx := map[string]any{"trashed_cost": 4}

	RequestDecision(s, 0, "remodel", 1, GainFromSupplyPrompt{MaxCost: 6}, ctx)

	require.Equal(t, 4, s.PendingDecision.Context["trashed_cost"])
	require.Equal(t, 1, s.PendingDecision.Step)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/engine/ -run TestRequestDecision -v`
Expected: FAIL — `RequestDecision` undefined, prompt types undefined.

- [ ] **Step 3: Add `EventDecisionRequested` to `state.go` and `Zone` to `types.go`**

In `dominion-grpc/internal/engine/state.go`, expand the `Decision` struct and add `DecisionSeq`:

```go
// Decision is a server-generated prompt requiring player input.
type Decision struct {
	ID        string
	PlayerIdx int
	CardID    CardID
	Step      int
	Prompt    Prompt
	Context   map[string]any
}
```

Add `DecisionSeq uint64` field to `GameState` (after `PendingDecision`):

```go
// DecisionSeq is a monotonic counter for generating deterministic
// decision IDs. Incremented by RequestDecision.
DecisionSeq uint64
```

Add `EventDecisionRequested` to the `EventKind` const block.

In `dominion-grpc/internal/engine/types.go`, add:

```go
// Zone represents where a card is being played from.
type Zone int

const (
	ZoneHand Zone = iota
	ZoneDiscard
)
```

- [ ] **Step 4: Create `decision.go` with prompt/answer types and `RequestDecision`**

Create `dominion-grpc/internal/engine/decision.go`:

```go
package engine

import "fmt"

// Prompt is the interface for all decision prompts.
type Prompt interface{ isPrompt() }

// Answer is the interface for all decision answers.
type Answer interface{ isAnswer() }

// --- Prompt types ---

// DiscardFromHandPrompt asks the player to discard cards from hand.
type DiscardFromHandPrompt struct {
	Min int
	Max int
}

func (DiscardFromHandPrompt) isPrompt() {}

// TrashFromHandPrompt asks the player to trash cards from hand.
type TrashFromHandPrompt struct {
	Min        int
	Max        int
	TypeFilter []CardType // e.g., [TypeTreasure] for Mine
	CardFilter []CardID   // e.g., ["copper"] for Moneylender
}

func (TrashFromHandPrompt) isPrompt() {}

// GainFromSupplyPrompt asks the player to gain a card from supply.
type GainFromSupplyPrompt struct {
	MaxCost    int
	TypeFilter []CardType
	Dest       GainDest
}

func (GainFromSupplyPrompt) isPrompt() {}

// ChooseFromDiscardPrompt asks the player to choose a card from their
// discard pile. Optional means they may decline.
type ChooseFromDiscardPrompt struct {
	Cards    []CardID
	Optional bool
}

func (ChooseFromDiscardPrompt) isPrompt() {}

// PutOnDeckPrompt asks the player to put one card from hand on top of
// their deck.
type PutOnDeckPrompt struct{}

func (PutOnDeckPrompt) isPrompt() {}

// MayPlayActionPrompt asks whether the player wants to play the given
// action card (e.g., Vassal's revealed action).
type MayPlayActionPrompt struct {
	Card CardID
}

func (MayPlayActionPrompt) isPrompt() {}

// --- Answer types ---

// CardListAnswer holds zero or more cards chosen by the player.
type CardListAnswer struct {
	Cards []CardID
}

func (CardListAnswer) isAnswer() {}

// CardChoiceAnswer holds a single card choice, or None to decline.
type CardChoiceAnswer struct {
	Card CardID
	None bool
}

func (CardChoiceAnswer) isAnswer() {}

// YesNoAnswer holds a boolean response.
type YesNoAnswer struct {
	Yes bool
}

func (YesNoAnswer) isAnswer() {}

// RequestDecision sets a pending decision on the game state. The engine
// will reject all non-ResolveDecision actions until this is resolved.
func RequestDecision(s *GameState, playerIdx int, cardID CardID, step int, prompt Prompt, ctx map[string]any) []Event {
	s.DecisionSeq++
	s.PendingDecision = &Decision{
		ID:        fmt.Sprintf("d%d", s.DecisionSeq),
		PlayerIdx: playerIdx,
		CardID:    cardID,
		Step:      step,
		Prompt:    prompt,
		Context:   ctx,
	}
	return []Event{{Kind: EventDecisionRequested, PlayerIdx: playerIdx}}
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `go test ./internal/engine/ -run TestRequestDecision -v`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add internal/engine/decision.go internal/engine/decision_test.go internal/engine/state.go internal/engine/types.go
git commit -m "feat(engine): add decision system — Prompt/Answer types and RequestDecision primitive"
```

---

### Task 2: New primitives — TrashFromHand, PutOnDeck, RevealAndDiscardFromDeck, PlayCardFromZone

**Files:**
- Modify: `dominion-grpc/internal/engine/primitives.go`
- Modify: `dominion-grpc/internal/engine/primitives_test.go`
- Modify: `dominion-grpc/internal/engine/apply.go` (new error vars)

- [ ] **Step 1: Write failing tests for `TrashFromHand`**

Add to `dominion-grpc/internal/engine/primitives_test.go`:

```go
func TestTrashFromHand_MovesCardsToTrash(t *testing.T) {
	s := newTestState(2)
	s.Players[0].Hand = []CardID{"estate", "copper", "estate"}

	events := TrashFromHand(s, 0, []CardID{"estate", "copper"})

	require.Equal(t, []CardID{"estate"}, s.Players[0].Hand)
	require.Contains(t, s.Trash, CardID("estate"))
	require.Contains(t, s.Trash, CardID("copper"))
	require.Len(t, events, 2)
	require.Equal(t, EventCardTrashed, events[0].Kind)
}

func TestTrashFromHand_SkipsMissingCards(t *testing.T) {
	s := newTestState(2)
	s.Players[0].Hand = []CardID{"copper"}

	events := TrashFromHand(s, 0, []CardID{"silver"})

	require.Equal(t, []CardID{"copper"}, s.Players[0].Hand)
	require.Empty(t, s.Trash)
	require.Empty(t, events)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/engine/ -run TestTrashFromHand -v`
Expected: FAIL — `TrashFromHand` undefined.

- [ ] **Step 3: Implement `TrashFromHand`**

Add to `dominion-grpc/internal/engine/primitives.go`:

```go
// TrashFromHand moves the named cards from hand to the trash pile.
// Cards not present in hand are silently skipped.
func TrashFromHand(s *GameState, p int, cards []CardID) []Event {
	ps := &s.Players[p]
	var events []Event
	for _, c := range cards {
		idx := indexOf(ps.Hand, c)
		if idx < 0 {
			continue
		}
		ps.Hand = append(ps.Hand[:idx], ps.Hand[idx+1:]...)
		s.Trash = append(s.Trash, c)
		events = append(events, Event{Kind: EventCardTrashed, PlayerIdx: p, CardID: c})
	}
	return events
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/engine/ -run TestTrashFromHand -v`
Expected: PASS.

- [ ] **Step 5: Write failing tests for `PutOnDeck`**

Add to `dominion-grpc/internal/engine/primitives_test.go`:

```go
func TestPutOnDeck_MovesFromHandToTopOfDeck(t *testing.T) {
	s := newTestState(2)
	s.Players[0].Hand = []CardID{"copper", "silver", "gold"}
	s.Players[0].Deck = []CardID{"estate"}

	events := PutOnDeck(s, 0, []CardID{"silver"})

	require.Equal(t, []CardID{"copper", "gold"}, s.Players[0].Hand)
	require.Equal(t, []CardID{"estate", "silver"}, s.Players[0].Deck)
	require.Len(t, events, 1)
}

func TestPutOnDeck_SkipsMissingCards(t *testing.T) {
	s := newTestState(2)
	s.Players[0].Hand = []CardID{"copper"}

	events := PutOnDeck(s, 0, []CardID{"silver"})

	require.Equal(t, []CardID{"copper"}, s.Players[0].Hand)
	require.Empty(t, events)
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `go test ./internal/engine/ -run TestPutOnDeck -v`
Expected: FAIL — `PutOnDeck` undefined.

- [ ] **Step 7: Implement `PutOnDeck`**

Add to `dominion-grpc/internal/engine/primitives.go`:

```go
// PutOnDeck moves the named cards from hand to the top of the player's
// deck. Cards not present in hand are silently skipped.
func PutOnDeck(s *GameState, p int, cards []CardID) []Event {
	ps := &s.Players[p]
	var events []Event
	for _, c := range cards {
		idx := indexOf(ps.Hand, c)
		if idx < 0 {
			continue
		}
		ps.Hand = append(ps.Hand[:idx], ps.Hand[idx+1:]...)
		ps.Deck = append(ps.Deck, c)
		events = append(events, Event{Kind: EventCardDiscarded, PlayerIdx: p, CardID: c})
	}
	return events
}
```

Note: reuses `EventCardDiscarded` for simplicity — the card moves from hand to deck top. A future `EventCardPutOnDeck` event kind can be added if the frontend needs to distinguish.

- [ ] **Step 8: Run test to verify it passes**

Run: `go test ./internal/engine/ -run TestPutOnDeck -v`
Expected: PASS.

- [ ] **Step 9: Write failing tests for `RevealAndDiscardFromDeck`**

Add to `dominion-grpc/internal/engine/primitives_test.go`:

```go
func TestRevealAndDiscardFromDeck_MovesToDiscard(t *testing.T) {
	s := newTestState(2)
	s.Players[0].Deck = []CardID{"estate", "copper", "silver"}

	revealed, events := RevealAndDiscardFromDeck(s, 0, 1)

	require.Equal(t, []CardID{"silver"}, revealed)
	require.Contains(t, s.Players[0].Discard, CardID("silver"))
	require.Equal(t, []CardID{"estate", "copper"}, s.Players[0].Deck)
	require.Len(t, events, 1)
	require.Equal(t, EventCardDiscarded, events[0].Kind)
}

func TestRevealAndDiscardFromDeck_EmptyDeckShufflesDiscard(t *testing.T) {
	s := newTestState(2)
	s.Players[0].Deck = nil
	s.Players[0].Discard = []CardID{"gold", "silver"}

	revealed, events := RevealAndDiscardFromDeck(s, 0, 1)

	require.Len(t, revealed, 1)
	require.Len(t, events, 1)
}

func TestRevealAndDiscardFromDeck_EmptyBoth_ReturnsEmpty(t *testing.T) {
	s := newTestState(2)

	revealed, events := RevealAndDiscardFromDeck(s, 0, 1)

	require.Empty(t, revealed)
	require.Empty(t, events)
}
```

- [ ] **Step 10: Run test to verify it fails**

Run: `go test ./internal/engine/ -run TestRevealAndDiscardFromDeck -v`
Expected: FAIL — `RevealAndDiscardFromDeck` undefined.

- [ ] **Step 11: Implement `RevealAndDiscardFromDeck`**

Add to `dominion-grpc/internal/engine/primitives.go`:

```go
// RevealAndDiscardFromDeck reveals the top n cards of the player's deck
// and moves them to discard. If the deck is empty, the discard is
// shuffled into the deck first. Returns the revealed card IDs.
func RevealAndDiscardFromDeck(s *GameState, p int, n int) ([]CardID, []Event) {
	ps := &s.Players[p]
	var revealed []CardID
	var events []Event
	for i := 0; i < n; i++ {
		if len(ps.Deck) == 0 {
			if len(ps.Discard) == 0 {
				return revealed, events
			}
			ps.Deck = ps.Discard
			ps.Discard = nil
			shuffleCards(s.rng, ps.Deck)
		}
		top := len(ps.Deck) - 1
		card := ps.Deck[top]
		ps.Deck = ps.Deck[:top]
		ps.Discard = append(ps.Discard, card)
		revealed = append(revealed, card)
		events = append(events, Event{Kind: EventCardDiscarded, PlayerIdx: p, CardID: card})
	}
	return revealed, events
}
```

- [ ] **Step 12: Run test to verify it passes**

Run: `go test ./internal/engine/ -run TestRevealAndDiscardFromDeck -v`
Expected: PASS.

- [ ] **Step 13: Write failing tests for `PlayCardFromZone`**

Add to `dominion-grpc/internal/engine/primitives_test.go`:

```go
func TestPlayCardFromZone_Hand(t *testing.T) {
	s := newTestState(2)
	s.Players[0].Hand = []CardID{"smithy"}
	called := false
	lookup := func(id CardID) (*Card, bool) {
		if id == "smithy" {
			return &Card{
				ID: "smithy", Types: []CardType{TypeAction},
				OnPlay: func(s *GameState, p int) []Event {
					called = true
					return []Event{{Kind: EventCardDrawn, PlayerIdx: p, Count: 3}}
				},
			}, true
		}
		return nil, false
	}

	events, err := PlayCardFromZone(s, 0, "smithy", ZoneHand, lookup)

	require.NoError(t, err)
	require.True(t, called)
	require.Empty(t, s.Players[0].Hand)
	require.Contains(t, s.Players[0].InPlay, CardID("smithy"))
	require.GreaterOrEqual(t, len(events), 1)
	require.Equal(t, EventCardPlayed, events[0].Kind)
}

func TestPlayCardFromZone_Discard(t *testing.T) {
	s := newTestState(2)
	s.Players[0].Discard = []CardID{"village"}
	lookup := func(id CardID) (*Card, bool) {
		if id == "village" {
			return &Card{
				ID: "village", Types: []CardType{TypeAction},
				OnPlay: func(s *GameState, p int) []Event { return nil },
			}, true
		}
		return nil, false
	}

	events, err := PlayCardFromZone(s, 0, "village", ZoneDiscard, lookup)

	require.NoError(t, err)
	require.Empty(t, s.Players[0].Discard)
	require.Contains(t, s.Players[0].InPlay, CardID("village"))
	require.Equal(t, EventCardPlayed, events[0].Kind)
}

func TestPlayCardFromZone_CardNotInZone_Error(t *testing.T) {
	s := newTestState(2)
	lookup := func(id CardID) (*Card, bool) {
		return &Card{ID: "smithy"}, true
	}

	_, err := PlayCardFromZone(s, 0, "smithy", ZoneHand, lookup)
	require.ErrorIs(t, err, ErrCardNotInHand)

	_, err = PlayCardFromZone(s, 0, "smithy", ZoneDiscard, lookup)
	require.ErrorIs(t, err, ErrCardNotInDiscard)
}
```

- [ ] **Step 14: Run test to verify it fails**

Run: `go test ./internal/engine/ -run TestPlayCardFromZone -v`
Expected: FAIL — `PlayCardFromZone` undefined.

- [ ] **Step 15: Add `ErrCardNotInDiscard` to `apply.go` and implement `PlayCardFromZone`**

Add to `dominion-grpc/internal/engine/apply.go` error vars:

```go
ErrCardNotInDiscard  = errors.New("engine: card not in discard")
ErrNoDecisionPending = errors.New("engine: no decision pending")
ErrWrongDecisionID   = errors.New("engine: wrong decision ID")
ErrDecisionPending   = errors.New("engine: decision pending — only ResolveDecision is legal")
ErrNoResolveHandler  = errors.New("engine: card has no OnResolve handler")
```

Add to `dominion-grpc/internal/engine/primitives.go`:

```go
// PlayCardFromZone moves a card from the specified zone to in-play and
// calls its OnPlay. Does NOT consume an Action — the caller decides
// whether to decrement actions.
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

- [ ] **Step 16: Run test to verify it passes**

Run: `go test ./internal/engine/ -run TestPlayCardFromZone -v`
Expected: PASS.

- [ ] **Step 17: Commit**

```bash
git add internal/engine/primitives.go internal/engine/primitives_test.go internal/engine/apply.go
git commit -m "feat(engine): add TrashFromHand, PutOnDeck, RevealAndDiscardFromDeck, PlayCardFromZone primitives"
```

---

### Task 3: OnResolve on Card, ResolveDecision wiring in Apply, decision-pending guard

**Files:**
- Modify: `dominion-grpc/internal/engine/card.go`
- Modify: `dominion-grpc/internal/engine/action.go`
- Modify: `dominion-grpc/internal/engine/apply.go`
- Modify: `dominion-grpc/internal/engine/apply_test.go`

- [ ] **Step 1: Write failing tests for decision system in Apply**

Add to `dominion-grpc/internal/engine/apply_test.go`:

```go
func TestApply_ResolveDecision_NoDecisionPending(t *testing.T) {
	s, _ := NewGame("g", []string{"A", "B"}, nil, 1, basicsLookup2)
	s.CurrentPlayer = 0

	_, _, err := Apply(s, ResolveDecision{PlayerIdx: 0, DecisionID: "d1"}, applyTestLookup)
	require.ErrorIs(t, err, ErrNoDecisionPending)
}

func TestApply_ResolveDecision_WrongID(t *testing.T) {
	s, _ := NewGame("g", []string{"A", "B"}, nil, 1, basicsLookup2)
	s.CurrentPlayer = 0
	s.PendingDecision = &Decision{
		ID: "d1", PlayerIdx: 0, CardID: "cellar",
		Prompt: DiscardFromHandPrompt{Min: 0, Max: 3},
	}

	_, _, err := Apply(s, ResolveDecision{PlayerIdx: 0, DecisionID: "wrong"}, applyTestLookup)
	require.ErrorIs(t, err, ErrWrongDecisionID)
}

func TestApply_DecisionPending_BlocksNonResolveActions(t *testing.T) {
	s, _ := NewGame("g", []string{"A", "B"}, nil, 1, basicsLookup2)
	s.CurrentPlayer = 0
	s.PendingDecision = &Decision{
		ID: "d1", PlayerIdx: 0, CardID: "cellar",
		Prompt: DiscardFromHandPrompt{},
	}

	_, _, err := Apply(s, EndPhase{PlayerIdx: 0}, applyTestLookup)
	require.ErrorIs(t, err, ErrDecisionPending)
}

func TestApply_ResolveDecision_FromDecidingPlayer_NotCurrentPlayer(t *testing.T) {
	s, _ := NewGame("g", []string{"A", "B"}, nil, 1, basicsLookup2)
	s.CurrentPlayer = 0
	// Decision is for player 1 (not the current player).
	resolved := false
	testCard := &Card{
		ID: "testcard", Types: []CardType{TypeAction},
		OnResolve: func(s *GameState, p int, d *Decision, a Answer, lookup CardLookup) ([]Event, error) {
			resolved = true
			return nil, nil
		},
	}
	s.PendingDecision = &Decision{
		ID: "d1", PlayerIdx: 1, CardID: "testcard",
		Prompt: DiscardFromHandPrompt{},
	}
	testLookup := func(id CardID) (*Card, bool) {
		if id == "testcard" {
			return testCard, true
		}
		return applyTestLookup(id)
	}

	_, _, err := Apply(s, ResolveDecision{PlayerIdx: 1, DecisionID: "d1", Answer: CardListAnswer{}}, testLookup)
	require.NoError(t, err)
	require.True(t, resolved)
	require.Nil(t, s.PendingDecision)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/engine/ -run "TestApply_ResolveDecision|TestApply_DecisionPending" -v`
Expected: FAIL — compilation errors.

- [ ] **Step 3: Add `OnResolve` to `Card`**

In `dominion-grpc/internal/engine/card.go`, add `OnResolve` field:

```go
type Card struct {
	ID    CardID
	Name  string
	Cost  int
	Types []CardType

	OnPlay        func(s *GameState, playerIdx int) []Event
	VictoryPoints func(p PlayerState) int
	OnResolve     func(s *GameState, p int, d *Decision, answer Answer, lookup CardLookup) ([]Event, error)
}
```

Note: `OnResolve` returns `([]Event, error)` so cards can validate answers and reject invalid ones.

- [ ] **Step 4: Expand `ResolveDecision` action with `Answer`**

In `dominion-grpc/internal/engine/action.go`, update:

```go
type ResolveDecision struct {
	PlayerIdx  int
	DecisionID string
	Answer     Answer
}
```

- [ ] **Step 5: Wire ResolveDecision in Apply, add decision-pending guard and deciding-player bypass**

In `dominion-grpc/internal/engine/apply.go`, update `Apply`:

```go
func Apply(s *GameState, a Action, lookup CardLookup) (*GameState, []Event, error) {
	if s.Ended {
		return s, nil, ErrGameEnded
	}

	// Decision-pending guard: only ResolveDecision is legal while a
	// decision is pending.
	if s.PendingDecision != nil {
		resolve, ok := a.(ResolveDecision)
		if !ok {
			return s, nil, ErrDecisionPending
		}
		ev, err := applyResolveDecision(s, resolve, lookup)
		return s, ev, err
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
	default:
		return s, nil, ErrUnknownAction
	}
}

func applyResolveDecision(s *GameState, act ResolveDecision, lookup CardLookup) ([]Event, error) {
	d := s.PendingDecision
	if d == nil {
		return nil, ErrNoDecisionPending
	}
	if d.ID != act.DecisionID {
		return nil, ErrWrongDecisionID
	}
	if act.PlayerIdx != d.PlayerIdx {
		return nil, ErrNotYourTurn
	}
	card, ok := lookup(d.CardID)
	if !ok {
		return nil, ErrUnknownCard
	}
	if card.OnResolve == nil {
		return nil, ErrNoResolveHandler
	}
	s.PendingDecision = nil
	return card.OnResolve(s, d.PlayerIdx, d, act.Answer, lookup)
}
```

Also remove the old `case ResolveDecision:` branch that returned `ErrUnknownAction`.

- [ ] **Step 6: Refactor `applyPlayCard` to use `PlayCardFromZone`**

In `dominion-grpc/internal/engine/apply.go`, update `applyPlayCard`:

```go
func applyPlayCard(s *GameState, a PlayCard, lookup CardLookup) ([]Event, error) {
	card, ok := lookup(a.Card)
	if !ok {
		return nil, ErrUnknownCard
	}
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
	return PlayCardFromZone(s, a.PlayerIdx, a.Card, ZoneHand, lookup)
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `go test ./internal/engine/ -v`
Expected: ALL PASS — existing tests still pass, new decision tests pass.

- [ ] **Step 8: Commit**

```bash
git add internal/engine/card.go internal/engine/action.go internal/engine/apply.go internal/engine/apply_test.go
git commit -m "feat(engine): wire ResolveDecision in Apply, add decision-pending guard and deciding-player bypass"
```

---

## Stage B: Proto + Service Layer

### Task 4: Proto changes — prompt/answer messages

**Files:**
- Modify: `dominion-grpc/proto/dominion/v1/common.proto`
- Modify: `dominion-grpc/proto/dominion/v1/game.proto`
- Modify: `dominion-grpc/gen/go/dominion/v1/*.go` (regenerated)

- [ ] **Step 1: Add `GainDest` enum to `common.proto`**

Add to `dominion-grpc/proto/dominion/v1/common.proto`:

```protobuf
// GainDest says where a gained card should land.
enum GainDest {
    GAIN_DEST_UNSPECIFIED = 0;
    GAIN_DEST_DISCARD = 1;
    GAIN_DEST_HAND = 2;
    GAIN_DEST_DECK = 3;
}
```

- [ ] **Step 2: Expand `Decision` message with prompt oneof, add prompt messages**

In `dominion-grpc/proto/dominion/v1/game.proto`, replace the `Decision` message:

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

- [ ] **Step 3: Expand `ResolveDecision` message with answer oneof, add answer messages**

In `dominion-grpc/proto/dominion/v1/game.proto`, replace the `ResolveDecision` message:

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

- [ ] **Step 4: Add import for `common.proto` in `game.proto` if not already present**

Verify `game.proto` already has `import "dominion/v1/common.proto";` — it does, since `Phase` and `CardType` are defined there.

- [ ] **Step 5: Regenerate Go code**

Run: `buf generate`
Expected: generates updated files in `gen/go/dominion/v1/`.

- [ ] **Step 6: Verify build**

Run: `go build ./...`
Expected: compiles cleanly.

- [ ] **Step 7: Commit**

```bash
git add proto/ gen/
git commit -m "feat(proto): add prompt/answer oneofs to Decision and ResolveDecision"
```

---

### Task 5: Service layer — prompt/answer translation and DecisionRequested event

**Files:**
- Modify: `dominion-grpc/internal/service/translate.go`
- Modify: `dominion-grpc/internal/service/game_service.go`
- Modify: `dominion-grpc/internal/service/game_service_test.go`

- [ ] **Step 1: Write failing test for `DecisionToProto`**

Add to `dominion-grpc/internal/service/game_service_test.go`:

```go
func TestDecisionToProto_DiscardFromHand(t *testing.T) {
	d := &engine.Decision{
		ID: "d1", PlayerIdx: 0, CardID: "cellar", Step: 0,
		Prompt: engine.DiscardFromHandPrompt{Min: 0, Max: 3},
	}

	proto := DecisionToProto(d)

	require.Equal(t, "d1", proto.Id)
	require.Equal(t, int32(0), proto.PlayerIdx)
	require.Equal(t, "cellar", proto.CardId)
	p := proto.GetDiscardFromHand()
	require.NotNil(t, p)
	require.Equal(t, int32(0), p.Min)
	require.Equal(t, int32(3), p.Max)
}

func TestAnswerFromProto_CardList(t *testing.T) {
	r := &pb.ResolveDecision{
		DecisionId: "d1", PlayerIdx: 0,
		Answer: &pb.ResolveDecision_CardList{CardList: &pb.CardListAnswer{
			Cards: []string{"copper", "estate"},
		}},
	}

	answer, err := AnswerFromProto(r)
	require.NoError(t, err)
	cl, ok := answer.(engine.CardListAnswer)
	require.True(t, ok)
	require.Equal(t, []engine.CardID{"copper", "estate"}, cl.Cards)
}

func TestAnswerFromProto_CardChoice(t *testing.T) {
	r := &pb.ResolveDecision{
		DecisionId: "d1", PlayerIdx: 0,
		Answer: &pb.ResolveDecision_CardChoice{CardChoice: &pb.CardChoiceAnswer{
			Card: "silver", None: false,
		}},
	}

	answer, err := AnswerFromProto(r)
	require.NoError(t, err)
	cc, ok := answer.(engine.CardChoiceAnswer)
	require.True(t, ok)
	require.Equal(t, engine.CardID("silver"), cc.Card)
	require.False(t, cc.None)
}

func TestAnswerFromProto_YesNo(t *testing.T) {
	r := &pb.ResolveDecision{
		DecisionId: "d1", PlayerIdx: 0,
		Answer: &pb.ResolveDecision_YesNo{YesNo: &pb.YesNoAnswer{Yes: true}},
	}

	answer, err := AnswerFromProto(r)
	require.NoError(t, err)
	yn, ok := answer.(engine.YesNoAnswer)
	require.True(t, ok)
	require.True(t, yn.Yes)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/service/ -run "TestDecisionToProto|TestAnswerFromProto" -v`
Expected: FAIL — `DecisionToProto`, `AnswerFromProto` undefined.

- [ ] **Step 3: Implement `DecisionToProto`, `PromptToProto`, `AnswerFromProto` in `translate.go`**

Add to `dominion-grpc/internal/service/translate.go`:

```go
// DecisionToProto translates an engine Decision to its proto representation.
func DecisionToProto(d *engine.Decision) *pb.Decision {
	if d == nil {
		return nil
	}
	pd := &pb.Decision{
		Id:        d.ID,
		PlayerIdx: int32(d.PlayerIdx),
		CardId:    string(d.CardID),
		Step:      int32(d.Step),
	}
	switch p := d.Prompt.(type) {
	case engine.DiscardFromHandPrompt:
		pd.Prompt = &pb.Decision_DiscardFromHand{DiscardFromHand: &pb.DiscardFromHandPrompt{
			Min: int32(p.Min), Max: int32(p.Max),
		}}
	case engine.TrashFromHandPrompt:
		tf := make([]pb.CardType, len(p.TypeFilter))
		for i, ct := range p.TypeFilter {
			tf[i] = cardTypeToProto(ct)
		}
		cf := make([]string, len(p.CardFilter))
		for i, c := range p.CardFilter {
			cf[i] = string(c)
		}
		pd.Prompt = &pb.Decision_TrashFromHand{TrashFromHand: &pb.TrashFromHandPrompt{
			Min: int32(p.Min), Max: int32(p.Max), TypeFilter: tf, CardFilter: cf,
		}}
	case engine.GainFromSupplyPrompt:
		tf := make([]pb.CardType, len(p.TypeFilter))
		for i, ct := range p.TypeFilter {
			tf[i] = cardTypeToProto(ct)
		}
		pd.Prompt = &pb.Decision_GainFromSupply{GainFromSupply: &pb.GainFromSupplyPrompt{
			MaxCost: int32(p.MaxCost), TypeFilter: tf, Dest: gainDestToProto(p.Dest),
		}}
	case engine.ChooseFromDiscardPrompt:
		cards := make([]string, len(p.Cards))
		for i, c := range p.Cards {
			cards[i] = string(c)
		}
		pd.Prompt = &pb.Decision_ChooseFromDiscard{ChooseFromDiscard: &pb.ChooseFromDiscardPrompt{
			Cards: cards, Optional: p.Optional,
		}}
	case engine.PutOnDeckPrompt:
		pd.Prompt = &pb.Decision_PutOnDeck{PutOnDeck: &pb.PutOnDeckPrompt{}}
	case engine.MayPlayActionPrompt:
		pd.Prompt = &pb.Decision_MayPlayAction{MayPlayAction: &pb.MayPlayActionPrompt{
			CardId: string(p.Card),
		}}
	}
	return pd
}

// AnswerFromProto translates a proto ResolveDecision answer into an engine Answer.
func AnswerFromProto(r *pb.ResolveDecision) (engine.Answer, error) {
	switch a := r.Answer.(type) {
	case *pb.ResolveDecision_CardList:
		cards := make([]engine.CardID, len(a.CardList.Cards))
		for i, c := range a.CardList.Cards {
			cards[i] = engine.CardID(c)
		}
		return engine.CardListAnswer{Cards: cards}, nil
	case *pb.ResolveDecision_CardChoice:
		return engine.CardChoiceAnswer{
			Card: engine.CardID(a.CardChoice.Card),
			None: a.CardChoice.None,
		}, nil
	case *pb.ResolveDecision_YesNo:
		return engine.YesNoAnswer{Yes: a.YesNo.Yes}, nil
	default:
		return nil, fmt.Errorf("service: unknown answer type %T", a)
	}
}

func cardTypeToProto(ct engine.CardType) pb.CardType {
	switch ct {
	case engine.TypeTreasure:
		return pb.CardType_CARD_TYPE_TREASURE
	case engine.TypeVictory:
		return pb.CardType_CARD_TYPE_VICTORY
	case engine.TypeCurse:
		return pb.CardType_CARD_TYPE_CURSE
	case engine.TypeAction:
		return pb.CardType_CARD_TYPE_ACTION
	case engine.TypeAttack:
		return pb.CardType_CARD_TYPE_ATTACK
	case engine.TypeReaction:
		return pb.CardType_CARD_TYPE_REACTION
	}
	return pb.CardType_CARD_TYPE_UNSPECIFIED
}

func gainDestToProto(d engine.GainDest) pb.GainDest {
	switch d {
	case engine.GainToDiscard:
		return pb.GainDest_GAIN_DEST_DISCARD
	case engine.GainToHand:
		return pb.GainDest_GAIN_DEST_HAND
	case engine.GainToDeck:
		return pb.GainDest_GAIN_DEST_DECK
	}
	return pb.GainDest_GAIN_DEST_UNSPECIFIED
}
```

- [ ] **Step 4: Update `ActionFromProto` to populate `Answer`**

In `dominion-grpc/internal/service/translate.go`, update the `ResolveDecision` case in `ActionFromProto`:

```go
case *pb.Action_Resolve:
	answer, err := AnswerFromProto(k.Resolve)
	if err != nil {
		return nil, err
	}
	return engine.ResolveDecision{
		PlayerIdx:  int(k.Resolve.PlayerIdx),
		DecisionID: k.Resolve.DecisionId,
		Answer:     answer,
	}, nil
```

- [ ] **Step 5: Update `SnapshotFromState` to translate Decision**

In `dominion-grpc/internal/service/translate.go`, `SnapshotFromState` already sets `snap.PendingDecision`. Update it to use `DecisionToProto`:

In the `SnapshotFromState` function, after building the snapshot, before the return, add:

```go
snap.PendingDecision = DecisionToProto(s.PendingDecision)
```

- [ ] **Step 6: Emit `DecisionRequested` event in `fanOut`**

In `dominion-grpc/internal/service/game_service.go`, update `fanOut` to detect `EventDecisionRequested` and send a `DecisionRequested` stream event. Add a check alongside the existing `gameEnded` check:

```go
var decisionEvent *engine.Event
for _, ev := range events {
	if ev.Kind == engine.EventGameEnded {
		gameEnded = true
	}
	if ev.Kind == engine.EventDecisionRequested {
		e := ev
		decisionEvent = &e
	}
}
```

After the snapshot fanout block, if `decisionEvent` is set, emit a `DecisionRequested` event. However, since the current fanout pattern sends a full snapshot per action (which already includes `PendingDecision`), the `DecisionRequested` event is informational. For now, include the decision info in the snapshot — the snapshot already carries `pending_decision`. The separate `DecisionRequested` event can be added as an optimization later when the event model evolves. No code change needed here beyond the snapshot update in step 5.

- [ ] **Step 7: Run tests to verify they pass**

Run: `go test ./internal/service/ -v`
Expected: ALL PASS.

- [ ] **Step 8: Commit**

```bash
git add internal/service/translate.go internal/service/game_service.go internal/service/game_service_test.go
git commit -m "feat(service): add Decision/Answer proto translation, update snapshot with prompt data"
```

---

## Stage C: Card Implementations

All 10 cards follow the same TDD pattern. Each card is its own task. The test helper `newTestStateForCards` in `testutil_test.go` needs updating first.

### Task 6: Update test helpers for decision-based card tests

**Files:**
- Modify: `dominion-grpc/internal/engine/cards/testutil_test.go`

- [ ] **Step 1: Add decision-testing helpers**

Update `dominion-grpc/internal/engine/cards/testutil_test.go`:

```go
package cards

import (
	"math/rand"

	"github.com/nutthawit-l/dominion-grpc/internal/engine"
)

func newTestStateForCards(numPlayers int) *engine.GameState {
	players := make([]engine.PlayerState, numPlayers)
	for i := range players {
		players[i] = engine.PlayerState{Name: "p" + string(rune('0'+i))}
	}
	s := engine.NewTestStateWithRNG("test", 1, players)
	s.Phase = engine.PhaseBuy
	s.Supply = engine.Supply{Piles: map[engine.CardID]int{}}
	return s
}

// newActionPhaseState creates a test state where player 0 is in the Action
// phase with 1 action, for testing card OnPlay.
func newActionPhaseState() *engine.GameState {
	s := newTestStateForCards(2)
	s.Phase = engine.PhaseAction
	s.CurrentPlayer = 0
	s.Players[0].Actions = 1
	s.Players[0].Buys = 1
	return s
}

// testLookup returns a CardLookup that finds cards in the DefaultRegistry.
func testLookup(id engine.CardID) (*engine.Card, bool) {
	return DefaultRegistry.Lookup(id)
}
```

This requires exposing a `NewTestStateWithRNG` constructor from the engine package (since `rng` is unexported). Add to `dominion-grpc/internal/engine/state.go`:

```go
// NewTestStateWithRNG builds a GameState with an initialized RNG.
// Exported for use by card tests that need primitives requiring rng
// (e.g., DrawCards shuffles when deck is empty).
func NewTestStateWithRNG(gameID string, seed int64, players []PlayerState) *GameState {
	return &GameState{
		GameID:  gameID,
		Seed:    seed,
		rng:     rand.New(rand.NewSource(seed)),
		Players: players,
		Supply:  Supply{Piles: map[CardID]int{}},
	}
}
```

- [ ] **Step 2: Verify existing card tests still pass**

Run: `go test ./internal/engine/cards/ -v`
Expected: ALL PASS.

- [ ] **Step 3: Commit**

```bash
git add internal/engine/cards/testutil_test.go internal/engine/state.go
git commit -m "feat(engine): add test helpers for decision-based card tests"
```

---

### Task 7: Cellar

**Files:**
- Create: `dominion-grpc/internal/engine/cards/kingdom_cellar.go`
- Create: `dominion-grpc/internal/engine/cards/kingdom_cellar_test.go`

- [ ] **Step 1: Write failing tests**

Create `dominion-grpc/internal/engine/cards/kingdom_cellar_test.go`:

```go
package cards

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/nutthawit-l/dominion-grpc/internal/engine"
)

func TestCellar_OnPlay_AddsActionAndSetsPrompt(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"cellar", "copper", "estate", "silver"}
	s.Players[0].Deck = []engine.CardID{"gold", "gold", "gold"}
	s.Players[0].Actions = 1

	// Simulate playing Cellar via Apply.
	_, events, err := engine.Apply(s, engine.PlayCard{PlayerIdx: 0, Card: "cellar"}, testLookup)
	require.NoError(t, err)
	require.Equal(t, 1, s.Players[0].Actions) // +1 action, but 1 was consumed to play = net 1
	require.NotNil(t, s.PendingDecision)

	prompt, ok := s.PendingDecision.Prompt.(engine.DiscardFromHandPrompt)
	require.True(t, ok)
	require.Equal(t, 0, prompt.Min)
	require.Equal(t, 3, prompt.Max) // 3 cards left in hand after cellar moved to in-play
	_ = events
}

func TestCellar_OnResolve_DiscardsAndDraws(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"copper", "estate", "silver"}
	s.Players[0].Deck = []engine.CardID{"gold", "gold", "gold"}

	// Manually set up decision as if OnPlay ran.
	engine.RequestDecision(s, 0, "cellar", 0, engine.DiscardFromHandPrompt{Min: 0, Max: 3}, nil)

	_, _, err := engine.Apply(s, engine.ResolveDecision{
		PlayerIdx: 0, DecisionID: s.PendingDecision.ID,
		Answer: engine.CardListAnswer{Cards: []engine.CardID{"copper", "estate"}},
	}, testLookup)
	require.NoError(t, err)
	require.Nil(t, s.PendingDecision)
	// Discarded 2, drew 2: hand should have silver + 2 drawn = 3 cards.
	require.Len(t, s.Players[0].Hand, 3)
	require.Contains(t, s.Players[0].Hand, engine.CardID("silver"))
}

func TestCellar_OnResolve_DiscardZero(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"copper"}
	s.Players[0].Deck = []engine.CardID{"gold"}

	engine.RequestDecision(s, 0, "cellar", 0, engine.DiscardFromHandPrompt{Min: 0, Max: 1}, nil)

	_, _, err := engine.Apply(s, engine.ResolveDecision{
		PlayerIdx: 0, DecisionID: s.PendingDecision.ID,
		Answer: engine.CardListAnswer{Cards: nil},
	}, testLookup)
	require.NoError(t, err)
	require.Len(t, s.Players[0].Hand, 1) // no change
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/engine/cards/ -run TestCellar -v`
Expected: FAIL — `Cellar` undefined.

- [ ] **Step 3: Implement Cellar**

Create `dominion-grpc/internal/engine/cards/kingdom_cellar.go`:

```go
package cards

import "github.com/nutthawit-l/dominion-grpc/internal/engine"

var Cellar = &engine.Card{
	ID:    "cellar",
	Name:  "Cellar",
	Cost:  2,
	Types: []engine.CardType{engine.TypeAction},
	OnPlay: func(s *engine.GameState, p int) []engine.Event {
		events := engine.AddActions(s, p, 1)
		handSize := len(s.Players[p].Hand)
		events = append(events, engine.RequestDecision(s, p, "cellar", 0,
			engine.DiscardFromHandPrompt{Min: 0, Max: handSize}, nil)...)
		return events
	},
	OnResolve: func(s *engine.GameState, p int, d *engine.Decision, answer engine.Answer, lookup engine.CardLookup) ([]engine.Event, error) {
		cards := answer.(engine.CardListAnswer).Cards
		events := engine.DiscardFromHand(s, p, cards)
		events = append(events, engine.DrawCards(s, p, len(cards))...)
		return events, nil
	},
}

func init() {
	DefaultRegistry.Register(Cellar)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/engine/cards/ -run TestCellar -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/engine/cards/kingdom_cellar.go internal/engine/cards/kingdom_cellar_test.go
git commit -m "feat(cards): add Cellar — discard any, draw that many"
```

---

### Task 8: Chapel

**Files:**
- Create: `dominion-grpc/internal/engine/cards/kingdom_chapel.go`
- Create: `dominion-grpc/internal/engine/cards/kingdom_chapel_test.go`

- [ ] **Step 1: Write failing tests**

Create `dominion-grpc/internal/engine/cards/kingdom_chapel_test.go`:

```go
package cards

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/nutthawit-l/dominion-grpc/internal/engine"
)

func TestChapel_OnPlay_SetsTrashPrompt(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"chapel", "copper", "estate", "estate", "copper"}
	s.Players[0].Actions = 1

	_, _, err := engine.Apply(s, engine.PlayCard{PlayerIdx: 0, Card: "chapel"}, testLookup)
	require.NoError(t, err)
	require.NotNil(t, s.PendingDecision)

	prompt, ok := s.PendingDecision.Prompt.(engine.TrashFromHandPrompt)
	require.True(t, ok)
	require.Equal(t, 0, prompt.Min)
	require.Equal(t, 4, prompt.Max)
}

func TestChapel_OnResolve_TrashesCards(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"copper", "estate", "estate", "copper"}

	engine.RequestDecision(s, 0, "chapel", 0, engine.TrashFromHandPrompt{Min: 0, Max: 4}, nil)

	_, _, err := engine.Apply(s, engine.ResolveDecision{
		PlayerIdx: 0, DecisionID: s.PendingDecision.ID,
		Answer: engine.CardListAnswer{Cards: []engine.CardID{"estate", "estate"}},
	}, testLookup)
	require.NoError(t, err)
	require.Len(t, s.Players[0].Hand, 2) // 2 coppers remain
	require.Len(t, s.Trash, 2)
}

func TestChapel_OnResolve_TrashZero(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"copper"}

	engine.RequestDecision(s, 0, "chapel", 0, engine.TrashFromHandPrompt{Min: 0, Max: 4}, nil)

	_, _, err := engine.Apply(s, engine.ResolveDecision{
		PlayerIdx: 0, DecisionID: s.PendingDecision.ID,
		Answer: engine.CardListAnswer{Cards: nil},
	}, testLookup)
	require.NoError(t, err)
	require.Len(t, s.Players[0].Hand, 1)
	require.Empty(t, s.Trash)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/engine/cards/ -run TestChapel -v`
Expected: FAIL.

- [ ] **Step 3: Implement Chapel**

Create `dominion-grpc/internal/engine/cards/kingdom_chapel.go`:

```go
package cards

import "github.com/nutthawit-l/dominion-grpc/internal/engine"

var Chapel = &engine.Card{
	ID:    "chapel",
	Name:  "Chapel",
	Cost:  2,
	Types: []engine.CardType{engine.TypeAction},
	OnPlay: func(s *engine.GameState, p int) []engine.Event {
		return engine.RequestDecision(s, p, "chapel", 0,
			engine.TrashFromHandPrompt{Min: 0, Max: 4}, nil)
	},
	OnResolve: func(s *engine.GameState, p int, d *engine.Decision, answer engine.Answer, lookup engine.CardLookup) ([]engine.Event, error) {
		cards := answer.(engine.CardListAnswer).Cards
		return engine.TrashFromHand(s, p, cards), nil
	},
}

func init() {
	DefaultRegistry.Register(Chapel)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/engine/cards/ -run TestChapel -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/engine/cards/kingdom_chapel.go internal/engine/cards/kingdom_chapel_test.go
git commit -m "feat(cards): add Chapel — trash up to 4 from hand"
```

---

### Task 9: Harbinger

**Files:**
- Create: `dominion-grpc/internal/engine/cards/kingdom_harbinger.go`
- Create: `dominion-grpc/internal/engine/cards/kingdom_harbinger_test.go`

- [ ] **Step 1: Write failing tests**

Create `dominion-grpc/internal/engine/cards/kingdom_harbinger_test.go`:

```go
package cards

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/nutthawit-l/dominion-grpc/internal/engine"
)

func TestHarbinger_OnPlay_DrawsAndAddsAction(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"harbinger"}
	s.Players[0].Deck = []engine.CardID{"copper"}
	s.Players[0].Discard = []engine.CardID{"silver", "gold"}
	s.Players[0].Actions = 1

	_, _, err := engine.Apply(s, engine.PlayCard{PlayerIdx: 0, Card: "harbinger"}, testLookup)
	require.NoError(t, err)
	require.Equal(t, 1, s.Players[0].Actions) // +1 action, -1 to play = net 1
	require.Contains(t, s.Players[0].Hand, engine.CardID("copper"))
	require.NotNil(t, s.PendingDecision)

	prompt, ok := s.PendingDecision.Prompt.(engine.ChooseFromDiscardPrompt)
	require.True(t, ok)
	require.True(t, prompt.Optional)
	require.Len(t, prompt.Cards, 2)
}

func TestHarbinger_OnPlay_EmptyDiscard_NoDecision(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"harbinger"}
	s.Players[0].Deck = []engine.CardID{"copper"}
	s.Players[0].Actions = 1

	_, _, err := engine.Apply(s, engine.PlayCard{PlayerIdx: 0, Card: "harbinger"}, testLookup)
	require.NoError(t, err)
	require.Nil(t, s.PendingDecision)
}

func TestHarbinger_OnResolve_PutsCardOnDeck(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Discard = []engine.CardID{"silver", "gold"}
	s.Players[0].Deck = []engine.CardID{"copper"}

	engine.RequestDecision(s, 0, "harbinger", 0,
		engine.ChooseFromDiscardPrompt{Cards: []engine.CardID{"silver", "gold"}, Optional: true}, nil)

	_, _, err := engine.Apply(s, engine.ResolveDecision{
		PlayerIdx: 0, DecisionID: s.PendingDecision.ID,
		Answer: engine.CardChoiceAnswer{Card: "gold"},
	}, testLookup)
	require.NoError(t, err)
	require.Equal(t, []engine.CardID{"silver"}, s.Players[0].Discard)
	require.Equal(t, engine.CardID("gold"), s.Players[0].Deck[len(s.Players[0].Deck)-1])
}

func TestHarbinger_OnResolve_DeclineIsLegal(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Discard = []engine.CardID{"silver"}

	engine.RequestDecision(s, 0, "harbinger", 0,
		engine.ChooseFromDiscardPrompt{Cards: []engine.CardID{"silver"}, Optional: true}, nil)

	_, _, err := engine.Apply(s, engine.ResolveDecision{
		PlayerIdx: 0, DecisionID: s.PendingDecision.ID,
		Answer: engine.CardChoiceAnswer{None: true},
	}, testLookup)
	require.NoError(t, err)
	require.Equal(t, []engine.CardID{"silver"}, s.Players[0].Discard)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/engine/cards/ -run TestHarbinger -v`
Expected: FAIL.

- [ ] **Step 3: Implement Harbinger**

Create `dominion-grpc/internal/engine/cards/kingdom_harbinger.go`:

```go
package cards

import "github.com/nutthawit-l/dominion-grpc/internal/engine"

var Harbinger = &engine.Card{
	ID:    "harbinger",
	Name:  "Harbinger",
	Cost:  3,
	Types: []engine.CardType{engine.TypeAction},
	OnPlay: func(s *engine.GameState, p int) []engine.Event {
		events := engine.DrawCards(s, p, 1)
		events = append(events, engine.AddActions(s, p, 1)...)
		if len(s.Players[p].Discard) == 0 {
			return events
		}
		discardCopy := make([]engine.CardID, len(s.Players[p].Discard))
		copy(discardCopy, s.Players[p].Discard)
		events = append(events, engine.RequestDecision(s, p, "harbinger", 0,
			engine.ChooseFromDiscardPrompt{Cards: discardCopy, Optional: true}, nil)...)
		return events
	},
	OnResolve: func(s *engine.GameState, p int, d *engine.Decision, answer engine.Answer, lookup engine.CardLookup) ([]engine.Event, error) {
		choice := answer.(engine.CardChoiceAnswer)
		if choice.None {
			return nil, nil
		}
		// Remove chosen card from discard, put on top of deck.
		ps := &s.Players[p]
		idx := engine.IndexOf(ps.Discard, choice.Card)
		if idx < 0 {
			return nil, nil // card no longer in discard — silently skip
		}
		ps.Discard = append(ps.Discard[:idx], ps.Discard[idx+1:]...)
		ps.Deck = append(ps.Deck, choice.Card)
		return nil, nil
	},
}

func init() {
	DefaultRegistry.Register(Harbinger)
}
```

Note: This requires exporting `indexOf` from `primitives.go` as `IndexOf` (or adding a helper). Add to `dominion-grpc/internal/engine/primitives.go`:

```go
// IndexOf returns the index of the first occurrence of c in cards, or -1.
// Exported for use by card implementations in the cards package.
func IndexOf(cards []CardID, c CardID) int {
	return indexOf(cards, c)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/engine/cards/ -run TestHarbinger -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/engine/cards/kingdom_harbinger.go internal/engine/cards/kingdom_harbinger_test.go internal/engine/primitives.go
git commit -m "feat(cards): add Harbinger — +1 card, +1 action, may top-deck from discard"
```

---

### Task 10: Vassal

**Files:**
- Create: `dominion-grpc/internal/engine/cards/kingdom_vassal.go`
- Create: `dominion-grpc/internal/engine/cards/kingdom_vassal_test.go`

- [ ] **Step 1: Write failing tests**

Create `dominion-grpc/internal/engine/cards/kingdom_vassal_test.go`:

```go
package cards

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/nutthawit-l/dominion-grpc/internal/engine"
)

func TestVassal_OnPlay_DiscardsTopCard_NonAction_NoDecision(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"vassal"}
	s.Players[0].Deck = []engine.CardID{"copper"}
	s.Players[0].Actions = 1

	_, _, err := engine.Apply(s, engine.PlayCard{PlayerIdx: 0, Card: "vassal"}, testLookup)
	require.NoError(t, err)
	require.Nil(t, s.PendingDecision)
	require.Contains(t, s.Players[0].Discard, engine.CardID("copper"))
}

func TestVassal_OnPlay_DiscardsAction_AsksToPlay(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"vassal"}
	s.Players[0].Deck = []engine.CardID{"village"}
	s.Players[0].Actions = 1

	_, _, err := engine.Apply(s, engine.PlayCard{PlayerIdx: 0, Card: "vassal"}, testLookup)
	require.NoError(t, err)
	require.NotNil(t, s.PendingDecision)

	prompt, ok := s.PendingDecision.Prompt.(engine.MayPlayActionPrompt)
	require.True(t, ok)
	require.Equal(t, engine.CardID("village"), prompt.Card)
}

func TestVassal_OnResolve_Yes_PlaysFromDiscard(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Discard = []engine.CardID{"village"}
	s.Players[0].Deck = []engine.CardID{"gold", "gold"}

	engine.RequestDecision(s, 0, "vassal", 0,
		engine.MayPlayActionPrompt{Card: "village"},
		map[string]any{"card": engine.CardID("village")})

	_, _, err := engine.Apply(s, engine.ResolveDecision{
		PlayerIdx: 0, DecisionID: s.PendingDecision.ID,
		Answer: engine.YesNoAnswer{Yes: true},
	}, testLookup)
	require.NoError(t, err)
	require.Contains(t, s.Players[0].InPlay, engine.CardID("village"))
	require.Empty(t, s.Players[0].Discard)
	// Village's OnPlay: +1 card, +2 actions
	require.Len(t, s.Players[0].Hand, 1) // drew 1
}

func TestVassal_OnResolve_No_DoesNothing(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Discard = []engine.CardID{"village"}

	engine.RequestDecision(s, 0, "vassal", 0,
		engine.MayPlayActionPrompt{Card: "village"},
		map[string]any{"card": engine.CardID("village")})

	_, _, err := engine.Apply(s, engine.ResolveDecision{
		PlayerIdx: 0, DecisionID: s.PendingDecision.ID,
		Answer: engine.YesNoAnswer{Yes: false},
	}, testLookup)
	require.NoError(t, err)
	require.Contains(t, s.Players[0].Discard, engine.CardID("village"))
}

func TestVassal_OnPlay_EmptyDeck_NoEffect(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"vassal"}
	s.Players[0].Actions = 1

	_, _, err := engine.Apply(s, engine.PlayCard{PlayerIdx: 0, Card: "vassal"}, testLookup)
	require.NoError(t, err)
	require.Nil(t, s.PendingDecision)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/engine/cards/ -run TestVassal -v`
Expected: FAIL.

- [ ] **Step 3: Implement Vassal**

Create `dominion-grpc/internal/engine/cards/kingdom_vassal.go`:

```go
package cards

import "github.com/nutthawit-l/dominion-grpc/internal/engine"

var Vassal = &engine.Card{
	ID:    "vassal",
	Name:  "Vassal",
	Cost:  3,
	Types: []engine.CardType{engine.TypeAction},
	OnPlay: func(s *engine.GameState, p int) []engine.Event {
		revealed, events := engine.RevealAndDiscardFromDeck(s, p, 1)
		if len(revealed) == 0 {
			return events
		}
		card := revealed[0]
		c, ok := DefaultRegistry.Lookup(card)
		if !ok || !c.HasType(engine.TypeAction) {
			return events
		}
		events = append(events, engine.RequestDecision(s, p, "vassal", 0,
			engine.MayPlayActionPrompt{Card: card},
			map[string]any{"card": card})...)
		return events
	},
	OnResolve: func(s *engine.GameState, p int, d *engine.Decision, answer engine.Answer, lookup engine.CardLookup) ([]engine.Event, error) {
		yn := answer.(engine.YesNoAnswer)
		if !yn.Yes {
			return nil, nil
		}
		cardID := d.Context["card"].(engine.CardID)
		ev, err := engine.PlayCardFromZone(s, p, cardID, engine.ZoneDiscard, lookup)
		return ev, err
	},
}

func init() {
	DefaultRegistry.Register(Vassal)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/engine/cards/ -run TestVassal -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/engine/cards/kingdom_vassal.go internal/engine/cards/kingdom_vassal_test.go
git commit -m "feat(cards): add Vassal — discard top of deck, may play if Action"
```

---

### Task 11: Workshop

**Files:**
- Create: `dominion-grpc/internal/engine/cards/kingdom_workshop.go`
- Create: `dominion-grpc/internal/engine/cards/kingdom_workshop_test.go`

- [ ] **Step 1: Write failing tests**

Create `dominion-grpc/internal/engine/cards/kingdom_workshop_test.go`:

```go
package cards

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/nutthawit-l/dominion-grpc/internal/engine"
)

func TestWorkshop_OnPlay_SetsGainPrompt(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"workshop"}
	s.Players[0].Actions = 1

	_, _, err := engine.Apply(s, engine.PlayCard{PlayerIdx: 0, Card: "workshop"}, testLookup)
	require.NoError(t, err)
	require.NotNil(t, s.PendingDecision)

	prompt, ok := s.PendingDecision.Prompt.(engine.GainFromSupplyPrompt)
	require.True(t, ok)
	require.Equal(t, 4, prompt.MaxCost)
	require.Equal(t, engine.GainToDiscard, prompt.Dest)
}

func TestWorkshop_OnResolve_GainsCard(t *testing.T) {
	s := newActionPhaseState()
	s.Supply.Piles["silver"] = 10

	engine.RequestDecision(s, 0, "workshop", 0,
		engine.GainFromSupplyPrompt{MaxCost: 4, Dest: engine.GainToDiscard}, nil)

	_, _, err := engine.Apply(s, engine.ResolveDecision{
		PlayerIdx: 0, DecisionID: s.PendingDecision.ID,
		Answer: engine.CardChoiceAnswer{Card: "silver"},
	}, testLookup)
	require.NoError(t, err)
	require.Contains(t, s.Players[0].Discard, engine.CardID("silver"))
	require.Equal(t, 9, s.Supply.Piles["silver"])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/engine/cards/ -run TestWorkshop -v`
Expected: FAIL.

- [ ] **Step 3: Implement Workshop**

Create `dominion-grpc/internal/engine/cards/kingdom_workshop.go`:

```go
package cards

import (
	"fmt"

	"github.com/nutthawit-l/dominion-grpc/internal/engine"
)

var Workshop = &engine.Card{
	ID:    "workshop",
	Name:  "Workshop",
	Cost:  3,
	Types: []engine.CardType{engine.TypeAction},
	OnPlay: func(s *engine.GameState, p int) []engine.Event {
		return engine.RequestDecision(s, p, "workshop", 0,
			engine.GainFromSupplyPrompt{MaxCost: 4, Dest: engine.GainToDiscard}, nil)
	},
	OnResolve: func(s *engine.GameState, p int, d *engine.Decision, answer engine.Answer, lookup engine.CardLookup) ([]engine.Event, error) {
		choice := answer.(engine.CardChoiceAnswer)
		card, ok := lookup(choice.Card)
		if !ok {
			return nil, fmt.Errorf("workshop: unknown card %q", choice.Card)
		}
		prompt := d.Prompt.(engine.GainFromSupplyPrompt)
		if card.Cost > prompt.MaxCost {
			return nil, fmt.Errorf("workshop: card %q costs %d, max %d", choice.Card, card.Cost, prompt.MaxCost)
		}
		return engine.GainCard(s, p, choice.Card, prompt.Dest), nil
	},
}

func init() {
	DefaultRegistry.Register(Workshop)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/engine/cards/ -run TestWorkshop -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/engine/cards/kingdom_workshop.go internal/engine/cards/kingdom_workshop_test.go
git commit -m "feat(cards): add Workshop — gain a card costing up to 4"
```

---

### Task 12: Moneylender

**Files:**
- Create: `dominion-grpc/internal/engine/cards/kingdom_moneylender.go`
- Create: `dominion-grpc/internal/engine/cards/kingdom_moneylender_test.go`

- [ ] **Step 1: Write failing tests**

Create `dominion-grpc/internal/engine/cards/kingdom_moneylender_test.go`:

```go
package cards

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/nutthawit-l/dominion-grpc/internal/engine"
)

func TestMoneylender_OnPlay_NoCopperInHand_NoDecision(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"moneylender", "estate", "silver"}
	s.Players[0].Actions = 1

	_, _, err := engine.Apply(s, engine.PlayCard{PlayerIdx: 0, Card: "moneylender"}, testLookup)
	require.NoError(t, err)
	require.Nil(t, s.PendingDecision)
}

func TestMoneylender_OnPlay_CopperInHand_SetsPrompt(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"moneylender", "copper", "estate"}
	s.Players[0].Actions = 1

	_, _, err := engine.Apply(s, engine.PlayCard{PlayerIdx: 0, Card: "moneylender"}, testLookup)
	require.NoError(t, err)
	require.NotNil(t, s.PendingDecision)

	prompt, ok := s.PendingDecision.Prompt.(engine.TrashFromHandPrompt)
	require.True(t, ok)
	require.Equal(t, 0, prompt.Min)
	require.Equal(t, 1, prompt.Max)
	require.Equal(t, []engine.CardID{"copper"}, prompt.CardFilter)
}

func TestMoneylender_OnResolve_TrashCopper_Adds3Coins(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"copper", "estate"}
	s.Players[0].Coins = 0

	engine.RequestDecision(s, 0, "moneylender", 0,
		engine.TrashFromHandPrompt{Min: 0, Max: 1, CardFilter: []engine.CardID{"copper"}}, nil)

	_, _, err := engine.Apply(s, engine.ResolveDecision{
		PlayerIdx: 0, DecisionID: s.PendingDecision.ID,
		Answer: engine.CardListAnswer{Cards: []engine.CardID{"copper"}},
	}, testLookup)
	require.NoError(t, err)
	require.Equal(t, 3, s.Players[0].Coins)
	require.Contains(t, s.Trash, engine.CardID("copper"))
}

func TestMoneylender_OnResolve_Decline_NoEffect(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"copper"}
	s.Players[0].Coins = 0

	engine.RequestDecision(s, 0, "moneylender", 0,
		engine.TrashFromHandPrompt{Min: 0, Max: 1, CardFilter: []engine.CardID{"copper"}}, nil)

	_, _, err := engine.Apply(s, engine.ResolveDecision{
		PlayerIdx: 0, DecisionID: s.PendingDecision.ID,
		Answer: engine.CardListAnswer{Cards: nil},
	}, testLookup)
	require.NoError(t, err)
	require.Equal(t, 0, s.Players[0].Coins)
	require.Contains(t, s.Players[0].Hand, engine.CardID("copper"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/engine/cards/ -run TestMoneylender -v`
Expected: FAIL.

- [ ] **Step 3: Implement Moneylender**

Create `dominion-grpc/internal/engine/cards/kingdom_moneylender.go`:

```go
package cards

import "github.com/nutthawit-l/dominion-grpc/internal/engine"

var Moneylender = &engine.Card{
	ID:    "moneylender",
	Name:  "Moneylender",
	Cost:  4,
	Types: []engine.CardType{engine.TypeAction},
	OnPlay: func(s *engine.GameState, p int) []engine.Event {
		if engine.IndexOf(s.Players[p].Hand, "copper") < 0 {
			return nil
		}
		return engine.RequestDecision(s, p, "moneylender", 0,
			engine.TrashFromHandPrompt{Min: 0, Max: 1, CardFilter: []engine.CardID{"copper"}}, nil)
	},
	OnResolve: func(s *engine.GameState, p int, d *engine.Decision, answer engine.Answer, lookup engine.CardLookup) ([]engine.Event, error) {
		cards := answer.(engine.CardListAnswer).Cards
		if len(cards) == 0 {
			return nil, nil
		}
		events := engine.TrashFromHand(s, p, cards)
		events = append(events, engine.AddCoins(s, p, 3)...)
		return events, nil
	},
}

func init() {
	DefaultRegistry.Register(Moneylender)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/engine/cards/ -run TestMoneylender -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/engine/cards/kingdom_moneylender.go internal/engine/cards/kingdom_moneylender_test.go
git commit -m "feat(cards): add Moneylender — may trash Copper for +3 coins"
```

---

### Task 13: Poacher

**Files:**
- Create: `dominion-grpc/internal/engine/cards/kingdom_poacher.go`
- Create: `dominion-grpc/internal/engine/cards/kingdom_poacher_test.go`

- [ ] **Step 1: Write failing tests**

Create `dominion-grpc/internal/engine/cards/kingdom_poacher_test.go`:

```go
package cards

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/nutthawit-l/dominion-grpc/internal/engine"
)

func TestPoacher_OnPlay_ZeroEmptyPiles_NoDecision(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"poacher"}
	s.Players[0].Deck = []engine.CardID{"copper"}
	s.Players[0].Actions = 1
	s.Supply.Piles["silver"] = 10
	s.Supply.Piles["gold"] = 10

	_, _, err := engine.Apply(s, engine.PlayCard{PlayerIdx: 0, Card: "poacher"}, testLookup)
	require.NoError(t, err)
	require.Nil(t, s.PendingDecision)
	require.Equal(t, 1, s.Players[0].Coins)
	require.Equal(t, 1, s.Players[0].Actions) // +1 -1 = 1
}

func TestPoacher_OnPlay_OneEmptyPile_DiscardsOne(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"poacher"}
	s.Players[0].Deck = []engine.CardID{"copper"}
	s.Players[0].Actions = 1
	s.Supply.Piles["silver"] = 0 // empty
	s.Supply.Piles["gold"] = 10

	_, _, err := engine.Apply(s, engine.PlayCard{PlayerIdx: 0, Card: "poacher"}, testLookup)
	require.NoError(t, err)
	require.NotNil(t, s.PendingDecision)

	prompt, ok := s.PendingDecision.Prompt.(engine.DiscardFromHandPrompt)
	require.True(t, ok)
	require.Equal(t, 1, prompt.Min)
	require.Equal(t, 1, prompt.Max)
}

func TestPoacher_OnResolve_Discards(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"copper", "estate"}

	engine.RequestDecision(s, 0, "poacher", 0,
		engine.DiscardFromHandPrompt{Min: 1, Max: 1}, nil)

	_, _, err := engine.Apply(s, engine.ResolveDecision{
		PlayerIdx: 0, DecisionID: s.PendingDecision.ID,
		Answer: engine.CardListAnswer{Cards: []engine.CardID{"estate"}},
	}, testLookup)
	require.NoError(t, err)
	require.Equal(t, []engine.CardID{"copper"}, s.Players[0].Hand)
	require.Contains(t, s.Players[0].Discard, engine.CardID("estate"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/engine/cards/ -run TestPoacher -v`
Expected: FAIL.

- [ ] **Step 3: Implement Poacher**

Create `dominion-grpc/internal/engine/cards/kingdom_poacher.go`:

```go
package cards

import "github.com/nutthawit-l/dominion-grpc/internal/engine"

var Poacher = &engine.Card{
	ID:    "poacher",
	Name:  "Poacher",
	Cost:  4,
	Types: []engine.CardType{engine.TypeAction},
	OnPlay: func(s *engine.GameState, p int) []engine.Event {
		events := engine.DrawCards(s, p, 1)
		events = append(events, engine.AddActions(s, p, 1)...)
		events = append(events, engine.AddCoins(s, p, 1)...)

		emptyPiles := 0
		for _, n := range s.Supply.Piles {
			if n <= 0 {
				emptyPiles++
			}
		}
		if emptyPiles == 0 {
			return events
		}
		events = append(events, engine.RequestDecision(s, p, "poacher", 0,
			engine.DiscardFromHandPrompt{Min: emptyPiles, Max: emptyPiles}, nil)...)
		return events
	},
	OnResolve: func(s *engine.GameState, p int, d *engine.Decision, answer engine.Answer, lookup engine.CardLookup) ([]engine.Event, error) {
		cards := answer.(engine.CardListAnswer).Cards
		return engine.DiscardFromHand(s, p, cards), nil
	},
}

func init() {
	DefaultRegistry.Register(Poacher)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/engine/cards/ -run TestPoacher -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/engine/cards/kingdom_poacher.go internal/engine/cards/kingdom_poacher_test.go
git commit -m "feat(cards): add Poacher — +1 card/action/coin, discard per empty pile"
```

---

### Task 14: Remodel

**Files:**
- Create: `dominion-grpc/internal/engine/cards/kingdom_remodel.go`
- Create: `dominion-grpc/internal/engine/cards/kingdom_remodel_test.go`

- [ ] **Step 1: Write failing tests**

Create `dominion-grpc/internal/engine/cards/kingdom_remodel_test.go`:

```go
package cards

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/nutthawit-l/dominion-grpc/internal/engine"
)

func TestRemodel_OnPlay_SetsTrashPrompt(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"remodel", "copper", "estate"}
	s.Players[0].Actions = 1

	_, _, err := engine.Apply(s, engine.PlayCard{PlayerIdx: 0, Card: "remodel"}, testLookup)
	require.NoError(t, err)
	require.NotNil(t, s.PendingDecision)
	require.Equal(t, 0, s.PendingDecision.Step)

	prompt, ok := s.PendingDecision.Prompt.(engine.TrashFromHandPrompt)
	require.True(t, ok)
	require.Equal(t, 1, prompt.Min)
	require.Equal(t, 1, prompt.Max)
}

func TestRemodel_OnPlay_EmptyHand_NoDecision(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"remodel"}
	s.Players[0].Actions = 1

	_, _, err := engine.Apply(s, engine.PlayCard{PlayerIdx: 0, Card: "remodel"}, testLookup)
	require.NoError(t, err)
	require.Nil(t, s.PendingDecision) // hand empty after remodel moved to in-play
}

func TestRemodel_Step0_TrashThenGainPrompt(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"estate", "copper"} // estate costs 2
	s.Supply.Piles["silver"] = 10 // silver costs 3

	engine.RequestDecision(s, 0, "remodel", 0,
		engine.TrashFromHandPrompt{Min: 1, Max: 1}, nil)

	_, _, err := engine.Apply(s, engine.ResolveDecision{
		PlayerIdx: 0, DecisionID: s.PendingDecision.ID,
		Answer: engine.CardListAnswer{Cards: []engine.CardID{"estate"}},
	}, testLookup)
	require.NoError(t, err)
	require.Contains(t, s.Trash, engine.CardID("estate"))
	require.NotNil(t, s.PendingDecision)
	require.Equal(t, 1, s.PendingDecision.Step)

	prompt, ok := s.PendingDecision.Prompt.(engine.GainFromSupplyPrompt)
	require.True(t, ok)
	require.Equal(t, 4, prompt.MaxCost) // estate costs 2 + 2 = 4
}

func TestRemodel_Step1_GainsCard(t *testing.T) {
	s := newActionPhaseState()
	s.Supply.Piles["silver"] = 10

	engine.RequestDecision(s, 0, "remodel", 1,
		engine.GainFromSupplyPrompt{MaxCost: 4, Dest: engine.GainToDiscard},
		map[string]any{"trashed_cost": 2})

	_, _, err := engine.Apply(s, engine.ResolveDecision{
		PlayerIdx: 0, DecisionID: s.PendingDecision.ID,
		Answer: engine.CardChoiceAnswer{Card: "silver"},
	}, testLookup)
	require.NoError(t, err)
	require.Contains(t, s.Players[0].Discard, engine.CardID("silver"))
	require.Nil(t, s.PendingDecision)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/engine/cards/ -run TestRemodel -v`
Expected: FAIL.

- [ ] **Step 3: Implement Remodel**

Create `dominion-grpc/internal/engine/cards/kingdom_remodel.go`:

```go
package cards

import (
	"fmt"

	"github.com/nutthawit-l/dominion-grpc/internal/engine"
)

var Remodel = &engine.Card{
	ID:    "remodel",
	Name:  "Remodel",
	Cost:  4,
	Types: []engine.CardType{engine.TypeAction},
	OnPlay: func(s *engine.GameState, p int) []engine.Event {
		if len(s.Players[p].Hand) == 0 {
			return nil
		}
		return engine.RequestDecision(s, p, "remodel", 0,
			engine.TrashFromHandPrompt{Min: 1, Max: 1}, nil)
	},
	OnResolve: func(s *engine.GameState, p int, d *engine.Decision, answer engine.Answer, lookup engine.CardLookup) ([]engine.Event, error) {
		switch d.Step {
		case 0:
			cards := answer.(engine.CardListAnswer).Cards
			if len(cards) != 1 {
				return nil, fmt.Errorf("remodel: must trash exactly 1 card")
			}
			trashed := cards[0]
			events := engine.TrashFromHand(s, p, cards)
			card, ok := lookup(trashed)
			if !ok {
				return nil, fmt.Errorf("remodel: unknown trashed card %q", trashed)
			}
			trashedCost := card.Cost
			events = append(events, engine.RequestDecision(s, p, "remodel", 1,
				engine.GainFromSupplyPrompt{MaxCost: trashedCost + 2, Dest: engine.GainToDiscard},
				map[string]any{"trashed_cost": trashedCost})...)
			return events, nil

		case 1:
			choice := answer.(engine.CardChoiceAnswer)
			card, ok := lookup(choice.Card)
			if !ok {
				return nil, fmt.Errorf("remodel: unknown card %q", choice.Card)
			}
			maxCost := d.Context["trashed_cost"].(int) + 2
			if card.Cost > maxCost {
				return nil, fmt.Errorf("remodel: card %q costs %d, max %d", choice.Card, card.Cost, maxCost)
			}
			return engine.GainCard(s, p, choice.Card, engine.GainToDiscard), nil
		}
		return nil, fmt.Errorf("remodel: unexpected step %d", d.Step)
	},
}

func init() {
	DefaultRegistry.Register(Remodel)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/engine/cards/ -run TestRemodel -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/engine/cards/kingdom_remodel.go internal/engine/cards/kingdom_remodel_test.go
git commit -m "feat(cards): add Remodel — trash a card, gain one costing up to 2 more"
```

---

### Task 15: Mine

**Files:**
- Create: `dominion-grpc/internal/engine/cards/kingdom_mine.go`
- Create: `dominion-grpc/internal/engine/cards/kingdom_mine_test.go`

- [ ] **Step 1: Write failing tests**

Create `dominion-grpc/internal/engine/cards/kingdom_mine_test.go`:

```go
package cards

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/nutthawit-l/dominion-grpc/internal/engine"
)

func TestMine_OnPlay_NoTreasureInHand_NoDecision(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"mine", "estate"}
	s.Players[0].Actions = 1

	_, _, err := engine.Apply(s, engine.PlayCard{PlayerIdx: 0, Card: "mine"}, testLookup)
	require.NoError(t, err)
	require.Nil(t, s.PendingDecision)
}

func TestMine_OnPlay_TreasureInHand_SetsPrompt(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"mine", "copper", "silver"}
	s.Players[0].Actions = 1

	_, _, err := engine.Apply(s, engine.PlayCard{PlayerIdx: 0, Card: "mine"}, testLookup)
	require.NoError(t, err)
	require.NotNil(t, s.PendingDecision)

	prompt, ok := s.PendingDecision.Prompt.(engine.TrashFromHandPrompt)
	require.True(t, ok)
	require.Equal(t, 0, prompt.Min) // optional
	require.Equal(t, 1, prompt.Max)
	require.Equal(t, []engine.CardType{engine.TypeTreasure}, prompt.TypeFilter)
}

func TestMine_Step0_TrashCopper_Step1_GainSilverToHand(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"copper"}
	s.Supply.Piles["silver"] = 10

	engine.RequestDecision(s, 0, "mine", 0,
		engine.TrashFromHandPrompt{Min: 0, Max: 1, TypeFilter: []engine.CardType{engine.TypeTreasure}}, nil)

	_, _, err := engine.Apply(s, engine.ResolveDecision{
		PlayerIdx: 0, DecisionID: s.PendingDecision.ID,
		Answer: engine.CardListAnswer{Cards: []engine.CardID{"copper"}},
	}, testLookup)
	require.NoError(t, err)
	require.Contains(t, s.Trash, engine.CardID("copper"))
	require.NotNil(t, s.PendingDecision)
	require.Equal(t, 1, s.PendingDecision.Step)

	prompt, ok := s.PendingDecision.Prompt.(engine.GainFromSupplyPrompt)
	require.True(t, ok)
	require.Equal(t, 3, prompt.MaxCost) // copper costs 0 + 3 = 3
	require.Equal(t, engine.GainToHand, prompt.Dest)
	require.Equal(t, []engine.CardType{engine.TypeTreasure}, prompt.TypeFilter)

	_, _, err = engine.Apply(s, engine.ResolveDecision{
		PlayerIdx: 0, DecisionID: s.PendingDecision.ID,
		Answer: engine.CardChoiceAnswer{Card: "silver"},
	}, testLookup)
	require.NoError(t, err)
	require.Contains(t, s.Players[0].Hand, engine.CardID("silver"))
	require.Nil(t, s.PendingDecision)
}

func TestMine_Step0_Decline_NoEffect(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"copper"}

	engine.RequestDecision(s, 0, "mine", 0,
		engine.TrashFromHandPrompt{Min: 0, Max: 1, TypeFilter: []engine.CardType{engine.TypeTreasure}}, nil)

	_, _, err := engine.Apply(s, engine.ResolveDecision{
		PlayerIdx: 0, DecisionID: s.PendingDecision.ID,
		Answer: engine.CardListAnswer{Cards: nil},
	}, testLookup)
	require.NoError(t, err)
	require.Contains(t, s.Players[0].Hand, engine.CardID("copper"))
	require.Nil(t, s.PendingDecision)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/engine/cards/ -run TestMine -v`
Expected: FAIL.

- [ ] **Step 3: Implement Mine**

Create `dominion-grpc/internal/engine/cards/kingdom_mine.go`:

```go
package cards

import (
	"fmt"

	"github.com/nutthawit-l/dominion-grpc/internal/engine"
)

var Mine = &engine.Card{
	ID:    "mine",
	Name:  "Mine",
	Cost:  5,
	Types: []engine.CardType{engine.TypeAction},
	OnPlay: func(s *engine.GameState, p int) []engine.Event {
		hasTreasure := false
		for _, c := range s.Players[p].Hand {
			card, ok := DefaultRegistry.Lookup(c)
			if ok && card.HasType(engine.TypeTreasure) {
				hasTreasure = true
				break
			}
		}
		if !hasTreasure {
			return nil
		}
		return engine.RequestDecision(s, p, "mine", 0,
			engine.TrashFromHandPrompt{Min: 0, Max: 1, TypeFilter: []engine.CardType{engine.TypeTreasure}}, nil)
	},
	OnResolve: func(s *engine.GameState, p int, d *engine.Decision, answer engine.Answer, lookup engine.CardLookup) ([]engine.Event, error) {
		switch d.Step {
		case 0:
			cards := answer.(engine.CardListAnswer).Cards
			if len(cards) == 0 {
				return nil, nil // declined
			}
			trashed := cards[0]
			events := engine.TrashFromHand(s, p, cards)
			card, ok := lookup(trashed)
			if !ok {
				return nil, fmt.Errorf("mine: unknown card %q", trashed)
			}
			trashedCost := card.Cost
			events = append(events, engine.RequestDecision(s, p, "mine", 1,
				engine.GainFromSupplyPrompt{
					MaxCost:    trashedCost + 3,
					TypeFilter: []engine.CardType{engine.TypeTreasure},
					Dest:       engine.GainToHand,
				},
				map[string]any{"trashed_cost": trashedCost})...)
			return events, nil

		case 1:
			choice := answer.(engine.CardChoiceAnswer)
			card, ok := lookup(choice.Card)
			if !ok {
				return nil, fmt.Errorf("mine: unknown card %q", choice.Card)
			}
			maxCost := d.Context["trashed_cost"].(int) + 3
			if card.Cost > maxCost {
				return nil, fmt.Errorf("mine: card %q costs %d, max %d", choice.Card, card.Cost, maxCost)
			}
			if !card.HasType(engine.TypeTreasure) {
				return nil, fmt.Errorf("mine: card %q is not a treasure", choice.Card)
			}
			return engine.GainCard(s, p, choice.Card, engine.GainToHand), nil
		}
		return nil, fmt.Errorf("mine: unexpected step %d", d.Step)
	},
}

func init() {
	DefaultRegistry.Register(Mine)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/engine/cards/ -run TestMine -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/engine/cards/kingdom_mine.go internal/engine/cards/kingdom_mine_test.go
git commit -m "feat(cards): add Mine — may trash Treasure, gain Treasure costing up to 3 more to hand"
```

---

### Task 16: Artisan

**Files:**
- Create: `dominion-grpc/internal/engine/cards/kingdom_artisan.go`
- Create: `dominion-grpc/internal/engine/cards/kingdom_artisan_test.go`

- [ ] **Step 1: Write failing tests**

Create `dominion-grpc/internal/engine/cards/kingdom_artisan_test.go`:

```go
package cards

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/nutthawit-l/dominion-grpc/internal/engine"
)

func TestArtisan_OnPlay_SetsGainPrompt(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"artisan"}
	s.Players[0].Actions = 1
	s.Supply.Piles["silver"] = 10

	_, _, err := engine.Apply(s, engine.PlayCard{PlayerIdx: 0, Card: "artisan"}, testLookup)
	require.NoError(t, err)
	require.NotNil(t, s.PendingDecision)
	require.Equal(t, 0, s.PendingDecision.Step)

	prompt, ok := s.PendingDecision.Prompt.(engine.GainFromSupplyPrompt)
	require.True(t, ok)
	require.Equal(t, 5, prompt.MaxCost)
	require.Equal(t, engine.GainToHand, prompt.Dest)
}

func TestArtisan_Step0_GainToHand_Step1_PutOnDeck(t *testing.T) {
	s := newActionPhaseState()
	s.Players[0].Hand = []engine.CardID{"copper"}
	s.Supply.Piles["silver"] = 10

	engine.RequestDecision(s, 0, "artisan", 0,
		engine.GainFromSupplyPrompt{MaxCost: 5, Dest: engine.GainToHand}, nil)

	_, _, err := engine.Apply(s, engine.ResolveDecision{
		PlayerIdx: 0, DecisionID: s.PendingDecision.ID,
		Answer: engine.CardChoiceAnswer{Card: "silver"},
	}, testLookup)
	require.NoError(t, err)
	require.Contains(t, s.Players[0].Hand, engine.CardID("silver"))
	require.NotNil(t, s.PendingDecision)
	require.Equal(t, 1, s.PendingDecision.Step)

	_, ok := s.PendingDecision.Prompt.(engine.PutOnDeckPrompt)
	require.True(t, ok)

	_, _, err = engine.Apply(s, engine.ResolveDecision{
		PlayerIdx: 0, DecisionID: s.PendingDecision.ID,
		Answer: engine.CardChoiceAnswer{Card: "copper"},
	}, testLookup)
	require.NoError(t, err)
	require.NotContains(t, s.Players[0].Hand, engine.CardID("copper"))
	require.Equal(t, engine.CardID("copper"), s.Players[0].Deck[len(s.Players[0].Deck)-1])
	require.Nil(t, s.PendingDecision)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/engine/cards/ -run TestArtisan -v`
Expected: FAIL.

- [ ] **Step 3: Implement Artisan**

Create `dominion-grpc/internal/engine/cards/kingdom_artisan.go`:

```go
package cards

import (
	"fmt"

	"github.com/nutthawit-l/dominion-grpc/internal/engine"
)

var Artisan = &engine.Card{
	ID:    "artisan",
	Name:  "Artisan",
	Cost:  6,
	Types: []engine.CardType{engine.TypeAction},
	OnPlay: func(s *engine.GameState, p int) []engine.Event {
		return engine.RequestDecision(s, p, "artisan", 0,
			engine.GainFromSupplyPrompt{MaxCost: 5, Dest: engine.GainToHand}, nil)
	},
	OnResolve: func(s *engine.GameState, p int, d *engine.Decision, answer engine.Answer, lookup engine.CardLookup) ([]engine.Event, error) {
		switch d.Step {
		case 0:
			choice := answer.(engine.CardChoiceAnswer)
			card, ok := lookup(choice.Card)
			if !ok {
				return nil, fmt.Errorf("artisan: unknown card %q", choice.Card)
			}
			if card.Cost > 5 {
				return nil, fmt.Errorf("artisan: card %q costs %d, max 5", choice.Card, card.Cost)
			}
			events := engine.GainCard(s, p, choice.Card, engine.GainToHand)
			events = append(events, engine.RequestDecision(s, p, "artisan", 1,
				engine.PutOnDeckPrompt{}, nil)...)
			return events, nil

		case 1:
			choice := answer.(engine.CardChoiceAnswer)
			return engine.PutOnDeck(s, p, []engine.CardID{choice.Card}), nil
		}
		return nil, fmt.Errorf("artisan: unexpected step %d", d.Step)
	},
}

func init() {
	DefaultRegistry.Register(Artisan)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/engine/cards/ -run TestArtisan -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/engine/cards/kingdom_artisan.go internal/engine/cards/kingdom_artisan_test.go
git commit -m "feat(cards): add Artisan — gain card costing up to 5 to hand, put one from hand on deck"
```

---

## Stage D: Bot Strategies + Integration Tests

### Task 17: Update safeRefusal for prompt types

**Files:**
- Modify: `dominion-grpc/internal/bot/strategy.go`

- [ ] **Step 1: Update `safeRefusal` to return valid answers per prompt type**

Update `dominion-grpc/internal/bot/strategy.go`, replacing the existing `safeRefusal`:

```go
// safeRefusal returns the minimum legal answer for a decision. Used by
// strategies that do not handle a particular prompt type.
func safeRefusal(cs *ClientState, d *pb.Decision) *pb.ResolveDecision {
	r := &pb.ResolveDecision{DecisionId: d.Id, PlayerIdx: d.PlayerIdx}
	switch d.Prompt.(type) {
	case *pb.Decision_DiscardFromHand:
		p := d.GetDiscardFromHand()
		cards := pickFirstN(cs, int(p.Min))
		r.Answer = &pb.ResolveDecision_CardList{CardList: &pb.CardListAnswer{Cards: cards}}
	case *pb.Decision_TrashFromHand:
		r.Answer = &pb.ResolveDecision_CardList{CardList: &pb.CardListAnswer{Cards: nil}}
	case *pb.Decision_GainFromSupply:
		card := cheapestInSupply(cs, d.GetGainFromSupply())
		r.Answer = &pb.ResolveDecision_CardChoice{CardChoice: &pb.CardChoiceAnswer{Card: card}}
	case *pb.Decision_ChooseFromDiscard:
		r.Answer = &pb.ResolveDecision_CardChoice{CardChoice: &pb.CardChoiceAnswer{None: true}}
	case *pb.Decision_PutOnDeck:
		card := firstInHand(cs)
		r.Answer = &pb.ResolveDecision_CardChoice{CardChoice: &pb.CardChoiceAnswer{Card: card}}
	case *pb.Decision_MayPlayAction:
		r.Answer = &pb.ResolveDecision_YesNo{YesNo: &pb.YesNoAnswer{Yes: false}}
	default:
		r.Answer = &pb.ResolveDecision_CardList{CardList: &pb.CardListAnswer{}}
	}
	return r
}

func pickFirstN(cs *ClientState, n int) []string {
	me := cs.MyPlayer()
	if me == nil || n <= 0 {
		return nil
	}
	if n > len(me.Hand) {
		n = len(me.Hand)
	}
	return me.Hand[:n]
}

func cheapestInSupply(cs *ClientState, p *pb.GainFromSupplyPrompt) string {
	if cs.Snapshot == nil {
		return "copper"
	}
	best := ""
	bestCost := int(p.MaxCost) + 1
	for _, pile := range cs.Snapshot.Supply {
		if pile.Count <= 0 {
			continue
		}
		cost := cardCost(pile.CardId)
		if cost <= int(p.MaxCost) && cost < bestCost {
			best = pile.CardId
			bestCost = cost
		}
	}
	if best == "" {
		return "copper"
	}
	return best
}

func firstInHand(cs *ClientState) string {
	me := cs.MyPlayer()
	if me == nil || len(me.Hand) == 0 {
		return ""
	}
	return me.Hand[0]
}

// cardCost returns the known cost of a card by ID. This is a simple
// lookup for the base set; it avoids importing the engine package.
func cardCost(id string) int {
	switch id {
	case "copper", "curse":
		return 0
	case "estate":
		return 2
	case "silver", "cellar", "chapel":
		return 3
	case "harbinger", "vassal", "workshop":
		return 3
	case "moneylender", "poacher", "remodel", "smithy":
		return 4
	case "mine", "laboratory", "market", "festival":
		return 5
	case "gold", "artisan", "council_room":
		return 6
	case "duchy":
		return 5
	case "province":
		return 8
	}
	return 0
}
```

- [ ] **Step 2: Update BigMoney and SmithyBM `Resolve` calls**

Update the `Resolve` methods in `bigmoney.go` and `smithy_bm.go` to pass `cs`:

```go
func (BigMoney) Resolve(cs *ClientState, d *pb.Decision) *pb.ResolveDecision {
	return safeRefusal(cs, d)
}
```

```go
func (SmithyBM) Resolve(cs *ClientState, d *pb.Decision) *pb.ResolveDecision {
	return safeRefusal(cs, d)
}
```

- [ ] **Step 3: Verify build and existing tests**

Run: `go test ./internal/bot/ -run TestBotVsBot_BigMoney -v`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add internal/bot/strategy.go internal/bot/bigmoney.go internal/bot/smithy_bm.go
git commit -m "feat(bot): update safeRefusal to handle all Tier 2 prompt types"
```

---

### Task 18: ChapelBM strategy

**Files:**
- Create: `dominion-grpc/internal/bot/chapel_bm.go`
- Create: `dominion-grpc/internal/bot/chapel_bm_test.go`

- [ ] **Step 1: Write failing tests**

Create `dominion-grpc/internal/bot/chapel_bm_test.go`:

```go
package bot

import (
	"testing"

	"github.com/stretchr/testify/require"
	pb "github.com/nutthawit-l/dominion-grpc/gen/go/dominion/v1"
)

func TestChapelBM_BuysChapelOnEarlyTurn(t *testing.T) {
	cs := &ClientState{
		Me: 0, Phase: pb.Phase_PHASE_BUY, MyTurnsTaken: 1,
		Snapshot: &pb.GameStateSnapshot{
			Players: []*pb.PlayerView{
				{PlayerIdx: 0, Hand: nil, Buys: 1, Coins: 2, Actions: 0},
			},
			Supply: []*pb.SupplyPile{
				{CardId: "chapel", Count: 10},
				{CardId: "province", Count: 8},
			},
		},
		CurrentPlayer: 0,
	}
	strat := NewChapelBM()
	act := strat.PickAction(cs)
	require.NotNil(t, act)
	buy := act.GetBuyCard()
	require.NotNil(t, buy)
	require.Equal(t, "chapel", buy.CardId)
}

func TestChapelBM_DoesNotBuySecondChapel(t *testing.T) {
	cs := &ClientState{
		Me: 0, Phase: pb.Phase_PHASE_BUY, MyTurnsTaken: 2,
		Snapshot: &pb.GameStateSnapshot{
			Players: []*pb.PlayerView{
				{PlayerIdx: 0, Hand: nil, Buys: 1, Coins: 2, Actions: 0},
			},
			Supply: []*pb.SupplyPile{
				{CardId: "chapel", Count: 9}, // 1 already bought
				{CardId: "province", Count: 8},
			},
		},
		CurrentPlayer: 0,
	}
	strat := NewChapelBM()
	strat.chapelOwned = true
	act := strat.PickAction(cs)
	// Should not buy chapel — should end phase or buy silver if coins allow.
	if act != nil && act.GetBuyCard() != nil {
		require.NotEqual(t, "chapel", act.GetBuyCard().CardId)
	}
}

func TestChapelBM_Resolve_TrashesEstatesFirst(t *testing.T) {
	cs := &ClientState{
		Me: 0,
		Snapshot: &pb.GameStateSnapshot{
			Players: []*pb.PlayerView{
				{PlayerIdx: 0, Hand: []string{"estate", "copper", "estate", "copper"}},
			},
		},
	}
	strat := NewChapelBM()
	d := &pb.Decision{
		Id: "d1", PlayerIdx: 0,
		Prompt: &pb.Decision_TrashFromHand{TrashFromHand: &pb.TrashFromHandPrompt{
			Min: 0, Max: 4,
		}},
	}
	r := strat.Resolve(cs, d)
	cl := r.GetCardList()
	require.NotNil(t, cl)
	// Should trash both estates.
	estateCount := 0
	for _, c := range cl.Cards {
		if c == "estate" {
			estateCount++
		}
	}
	require.Equal(t, 2, estateCount)
}

func TestChapelBM_Resolve_KeepsThreeCoppers(t *testing.T) {
	cs := &ClientState{
		Me: 0,
		Snapshot: &pb.GameStateSnapshot{
			Players: []*pb.PlayerView{
				{PlayerIdx: 0, Hand: []string{"copper", "copper", "copper", "copper"}},
			},
		},
	}
	strat := NewChapelBM()
	// Starting: 7 coppers. Trash threshold: keep 3. Can trash up to 4.
	// So should trash 4 coppers (7-4=3, at threshold).
	d := &pb.Decision{
		Id: "d1", PlayerIdx: 0,
		Prompt: &pb.Decision_TrashFromHand{TrashFromHand: &pb.TrashFromHandPrompt{
			Min: 0, Max: 4,
		}},
	}
	r := strat.Resolve(cs, d)
	cl := r.GetCardList()
	require.NotNil(t, cl)
	require.Equal(t, 4, len(cl.Cards))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/bot/ -run TestChapelBM -v`
Expected: FAIL — `NewChapelBM` undefined.

- [ ] **Step 3: Implement ChapelBM**

Create `dominion-grpc/internal/bot/chapel_bm.go`:

```go
package bot

import (
	pb "github.com/nutthawit-l/dominion-grpc/gen/go/dominion/v1"
)

// ChapelBM is Chapel + Big Money. Buys 1 Chapel early, trashes Estates
// and excess Coppers, then follows Big Money. Keeps at least 3 Coppers.
type ChapelBM struct {
	chapelOwned  bool
	trashedCount map[string]int
}

func NewChapelBM() *ChapelBM {
	return &ChapelBM{trashedCount: map[string]int{}}
}

func (c *ChapelBM) Name() string { return "chapel_bm" }

func (c *ChapelBM) PickAction(cs *ClientState) *pb.Action {
	me := cs.MyPlayer()
	if me == nil {
		return endPhase(cs.Me)
	}

	switch cs.Phase {
	case pb.Phase_PHASE_ACTION:
		if me.Actions >= 1 && handContains(me.Hand, "chapel") && c.hasTrashableCards(me) {
			return playCard(cs.Me, "chapel")
		}
		return endPhase(cs.Me)

	case pb.Phase_PHASE_BUY:
		for _, card := range me.Hand {
			if isTreasure(card) {
				return playCard(cs.Me, card)
			}
		}
		if me.Buys <= 0 {
			return endPhase(cs.Me)
		}
		provincesLeft := supplyCount(cs.Snapshot, "province")
		endgame := provincesLeft <= 4
		switch {
		case me.Coins >= 8:
			return buyCard(cs.Me, "province")
		case me.Coins >= 6:
			return buyCard(cs.Me, "gold")
		case me.Coins >= 5 && endgame:
			return buyCard(cs.Me, "duchy")
		case me.Coins >= 2 && !c.chapelOwned && cs.MyTurnsTaken <= 2:
			c.chapelOwned = true
			return buyCard(cs.Me, "chapel")
		case me.Coins >= 3:
			return buyCard(cs.Me, "silver")
		}
		return endPhase(cs.Me)
	}
	return endPhase(cs.Me)
}

func (c *ChapelBM) Resolve(cs *ClientState, d *pb.Decision) *pb.ResolveDecision {
	if d.GetTrashFromHand() != nil && d.CardId == "chapel" {
		return c.resolveChapel(cs, d)
	}
	return safeRefusal(cs, d)
}

func (c *ChapelBM) resolveChapel(cs *ClientState, d *pb.Decision) *pb.ResolveDecision {
	me := cs.MyPlayer()
	prompt := d.GetTrashFromHand()
	max := int(prompt.Max)

	var toTrash []string
	coppersRemaining := 7 - c.trashedCount["copper"]
	const copperThreshold = 3

	// Trash estates first.
	for _, card := range me.Hand {
		if len(toTrash) >= max {
			break
		}
		if card == "estate" {
			toTrash = append(toTrash, card)
		}
	}
	// Then trash coppers down to threshold.
	for _, card := range me.Hand {
		if len(toTrash) >= max {
			break
		}
		if card == "copper" && coppersRemaining > copperThreshold {
			toTrash = append(toTrash, card)
			coppersRemaining--
		}
	}

	// Track what we trashed.
	for _, card := range toTrash {
		c.trashedCount[card]++
	}

	return &pb.ResolveDecision{
		DecisionId: d.Id, PlayerIdx: d.PlayerIdx,
		Answer: &pb.ResolveDecision_CardList{CardList: &pb.CardListAnswer{Cards: toTrash}},
	}
}

func (c *ChapelBM) hasTrashableCards(me *pb.PlayerView) bool {
	coppersRemaining := 7 - c.trashedCount["copper"]
	for _, card := range me.Hand {
		if card == "estate" {
			return true
		}
		if card == "copper" && coppersRemaining > 3 {
			return true
		}
	}
	return false
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/bot/ -run TestChapelBM -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/bot/chapel_bm.go internal/bot/chapel_bm_test.go
git commit -m "feat(bot): add ChapelBM strategy — Chapel + Big Money with copper threshold of 3"
```

---

### Task 19: RemodelBM strategy

**Files:**
- Create: `dominion-grpc/internal/bot/remodel_bm.go`
- Create: `dominion-grpc/internal/bot/remodel_bm_test.go`

- [ ] **Step 1: Write failing tests**

Create `dominion-grpc/internal/bot/remodel_bm_test.go`:

```go
package bot

import (
	"testing"

	"github.com/stretchr/testify/require"
	pb "github.com/nutthawit-l/dominion-grpc/gen/go/dominion/v1"
)

func TestRemodelBM_BuysRemodelOnEarlyTurn(t *testing.T) {
	cs := &ClientState{
		Me: 0, Phase: pb.Phase_PHASE_BUY, MyTurnsTaken: 2,
		Snapshot: &pb.GameStateSnapshot{
			Players: []*pb.PlayerView{
				{PlayerIdx: 0, Hand: nil, Buys: 1, Coins: 4, Actions: 0},
			},
			Supply: []*pb.SupplyPile{
				{CardId: "remodel", Count: 10},
				{CardId: "province", Count: 8},
			},
		},
		CurrentPlayer: 0,
	}
	strat := NewRemodelBM()
	act := strat.PickAction(cs)
	require.NotNil(t, act)
	buy := act.GetBuyCard()
	require.NotNil(t, buy)
	require.Equal(t, "remodel", buy.CardId)
}

func TestRemodelBM_Resolve_Step0_TrashesEstate(t *testing.T) {
	cs := &ClientState{
		Me: 0,
		Snapshot: &pb.GameStateSnapshot{
			Players: []*pb.PlayerView{
				{PlayerIdx: 0, Hand: []string{"estate", "copper", "silver"}},
			},
		},
	}
	strat := NewRemodelBM()
	d := &pb.Decision{
		Id: "d1", PlayerIdx: 0, CardId: "remodel", Step: 0,
		Prompt: &pb.Decision_TrashFromHand{TrashFromHand: &pb.TrashFromHandPrompt{
			Min: 1, Max: 1,
		}},
	}
	r := strat.Resolve(cs, d)
	cl := r.GetCardList()
	require.NotNil(t, cl)
	require.Equal(t, []string{"estate"}, cl.Cards)
}

func TestRemodelBM_Resolve_Step1_GainsMostExpensive(t *testing.T) {
	cs := &ClientState{
		Me: 0,
		Snapshot: &pb.GameStateSnapshot{
			Players: []*pb.PlayerView{
				{PlayerIdx: 0},
			},
			Supply: []*pb.SupplyPile{
				{CardId: "silver", Count: 10},
				{CardId: "gold", Count: 10},
				{CardId: "estate", Count: 8},
			},
		},
	}
	strat := NewRemodelBM()
	d := &pb.Decision{
		Id: "d2", PlayerIdx: 0, CardId: "remodel", Step: 1,
		Prompt: &pb.Decision_GainFromSupply{GainFromSupply: &pb.GainFromSupplyPrompt{
			MaxCost: 4,
		}},
	}
	r := strat.Resolve(cs, d)
	cc := r.GetCardChoice()
	require.NotNil(t, cc)
	require.Equal(t, "silver", cc.Card) // silver costs 3, within max 4
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/bot/ -run TestRemodelBM -v`
Expected: FAIL.

- [ ] **Step 3: Implement RemodelBM**

Create `dominion-grpc/internal/bot/remodel_bm.go`:

```go
package bot

import (
	pb "github.com/nutthawit-l/dominion-grpc/gen/go/dominion/v1"
)

// RemodelBM is Remodel + Big Money. Buys 1 Remodel early, remodels
// Estates into better cards, otherwise follows Big Money.
type RemodelBM struct {
	remodelOwned bool
}

func NewRemodelBM() *RemodelBM {
	return &RemodelBM{}
}

func (r *RemodelBM) Name() string { return "remodel_bm" }

func (r *RemodelBM) PickAction(cs *ClientState) *pb.Action {
	me := cs.MyPlayer()
	if me == nil {
		return endPhase(cs.Me)
	}

	switch cs.Phase {
	case pb.Phase_PHASE_ACTION:
		if me.Actions >= 1 && handContains(me.Hand, "remodel") {
			return playCard(cs.Me, "remodel")
		}
		return endPhase(cs.Me)

	case pb.Phase_PHASE_BUY:
		for _, card := range me.Hand {
			if isTreasure(card) {
				return playCard(cs.Me, card)
			}
		}
		if me.Buys <= 0 {
			return endPhase(cs.Me)
		}
		provincesLeft := supplyCount(cs.Snapshot, "province")
		endgame := provincesLeft <= 4
		switch {
		case me.Coins >= 8:
			return buyCard(cs.Me, "province")
		case me.Coins >= 6:
			return buyCard(cs.Me, "gold")
		case me.Coins >= 5 && endgame:
			return buyCard(cs.Me, "duchy")
		case me.Coins >= 4 && !r.remodelOwned && cs.MyTurnsTaken <= 4:
			r.remodelOwned = true
			return buyCard(cs.Me, "remodel")
		case me.Coins >= 3:
			return buyCard(cs.Me, "silver")
		}
		return endPhase(cs.Me)
	}
	return endPhase(cs.Me)
}

func (r *RemodelBM) Resolve(cs *ClientState, d *pb.Decision) *pb.ResolveDecision {
	if d.CardId == "remodel" {
		return r.resolveRemodel(cs, d)
	}
	return safeRefusal(cs, d)
}

func (r *RemodelBM) resolveRemodel(cs *ClientState, d *pb.Decision) *pb.ResolveDecision {
	me := cs.MyPlayer()

	switch d.Step {
	case 0: // trash
		// Prefer trashing estate, then cheapest card.
		best := ""
		bestCost := 999
		for _, card := range me.Hand {
			if card == "estate" {
				best = "estate"
				break
			}
			cost := cardCost(card)
			if best == "" || cost < bestCost {
				best = card
				bestCost = cost
			}
		}
		return &pb.ResolveDecision{
			DecisionId: d.Id, PlayerIdx: d.PlayerIdx,
			Answer: &pb.ResolveDecision_CardList{CardList: &pb.CardListAnswer{
				Cards: []string{best},
			}},
		}

	case 1: // gain — most expensive within limit
		prompt := d.GetGainFromSupply()
		maxCost := int(prompt.MaxCost)
		best := ""
		bestCost := -1
		// Prefer Province > Gold > Silver > anything else.
		priorities := []string{"province", "gold", "silver", "duchy"}
		for _, target := range priorities {
			cost := cardCost(target)
			if cost <= maxCost && supplyCount(cs.Snapshot, target) > 0 {
				best = target
				break
			}
			_ = cost
		}
		if best == "" {
			// Fallback: most expensive available.
			for _, pile := range cs.Snapshot.Supply {
				if pile.Count <= 0 {
					continue
				}
				cost := cardCost(pile.CardId)
				if cost <= maxCost && cost > bestCost {
					best = pile.CardId
					bestCost = cost
				}
			}
		}
		if best == "" {
			best = "copper"
		}
		return &pb.ResolveDecision{
			DecisionId: d.Id, PlayerIdx: d.PlayerIdx,
			Answer: &pb.ResolveDecision_CardChoice{CardChoice: &pb.CardChoiceAnswer{
				Card: best,
			}},
		}
	}

	return safeRefusal(cs, d)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/bot/ -run TestRemodelBM -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/bot/remodel_bm.go internal/bot/remodel_bm_test.go
git commit -m "feat(bot): add RemodelBM strategy — Remodel + Big Money"
```

---

### Task 20: ChapelBM done-criterion sweep + integration test updates

**Files:**
- Modify: `dominion-grpc/internal/bot/integration_test.go`

- [ ] **Step 1: Add ChapelBM vs BigMoney sweep test**

Add to `dominion-grpc/internal/bot/integration_test.go`:

```go
// Chapel+BigMoney with a supply limited to Chapel is known to run roughly
// even with pure Big Money: deck thinning helps but losing Estates costs
// VP. This sweep is a regression check that ChapelBM stays competitive,
// not that it strictly outperforms.
func TestBotVsBot_ChapelBM_CompetitiveWith_BigMoney(t *testing.T) {
	if testing.Short() {
		t.Skip("integration sweep — skipped under -short")
	}

	const games = 200
	const threshold = 0.48

	srv := newTestServer(t)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	wins := 0
	for seed := int64(0); seed < games; seed++ {
		chapelSeat := int(seed % 2)
		bmSeat := 1 - chapelSeat

		names := make([]string, 2)
		names[chapelSeat] = "chapel_bm"
		names[bmSeat] = "bigmoney"

		a := bot.NewClient(srv.URL)
		b := bot.NewClient(srv.URL)
		game, err := a.CreateGame(ctx, names, seed, []string{"chapel"})
		require.NoError(t, err)

		strategies := map[int]bot.Strategy{
			chapelSeat: bot.NewChapelBM(),
			bmSeat:     bot.BigMoney{},
		}

		grp, gctx := errgroup.WithContext(ctx)
		grp.Go(func() error { return bot.Run(gctx, a, game.GameId, 0, strategies[0]) })
		grp.Go(func() error { return bot.Run(gctx, b, game.GameId, 1, strategies[1]) })
		require.NoError(t, grp.Wait(), "seed=%d", seed)

		winners := finalWinners(t, srv, game.GameId)
		if len(winners) == 1 && winners[0] == chapelSeat {
			wins++
		}
	}

	rate := float64(wins) / float64(games)
	require.GreaterOrEqualf(t, rate, threshold,
		"ChapelBM win rate %.2f below threshold %.2f over %d games", rate, threshold, games)
}
```

- [ ] **Step 2: Add a basic RemodelBM integration test**

Add to `dominion-grpc/internal/bot/integration_test.go`:

```go
func TestBotVsBot_RemodelBM(t *testing.T) {
	srv := newTestServer(t)

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	a := bot.NewClient(srv.URL)
	b := bot.NewClient(srv.URL)

	game, err := a.CreateGame(ctx, []string{"remodel_bm", "bigmoney"}, 42, []string{"remodel"})
	require.NoError(t, err)

	grp, gctx := errgroup.WithContext(ctx)
	grp.Go(func() error { return bot.Run(gctx, a, game.GameId, 0, bot.NewRemodelBM()) })
	grp.Go(func() error { return bot.Run(gctx, b, game.GameId, 1, bot.BigMoney{}) })
	require.NoError(t, grp.Wait())
}
```

- [ ] **Step 3: Run the single-game RemodelBM test first**

Run: `go test ./internal/bot/ -run TestBotVsBot_RemodelBM -v -timeout 60s`
Expected: PASS — game completes without errors.

- [ ] **Step 4: Run the ChapelBM sweep**

Run: `go test ./internal/bot/ -run TestBotVsBot_ChapelBM_CompetitiveWith -v -timeout 10m`
Expected: PASS — ChapelBM wins >= 48% of 200 games.

- [ ] **Step 5: Run all tests**

Run: `go test ./... -timeout 10m`
Expected: ALL PASS.

- [ ] **Step 6: Commit**

```bash
git add internal/bot/integration_test.go
git commit -m "feat(bot): add ChapelBM competitive-parity sweep (200 games, ≥48%) and RemodelBM integration test"
```

---

## Summary

| Stage | Tasks | What it delivers |
|---|---|---|
| A | 1-3 | Decision system: Prompt/Answer types, RequestDecision, OnResolve, Apply wiring, PlayCardFromZone, new primitives |
| B | 4-5 | Proto prompt/answer messages, service layer translation |
| C | 6-16 | 10 kingdom cards: Cellar, Chapel, Harbinger, Vassal, Workshop, Moneylender, Poacher, Remodel, Mine, Artisan |
| D | 17-20 | Updated safeRefusal, ChapelBM, RemodelBM, done-criterion sweep |

Total: **20 tasks**, each independently committable and testable.
