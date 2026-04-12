# Section 3 — Primer for newcomers to protobuf / gRPC / Connect

**Audience:** You, the user of this project, coming in with no prior protobuf or gRPC experience.
**Purpose:** Read this side-by-side with Section 3 of the design spec. Every subsection of the spec is re-explained here from first principles, with a focus on *why* the design looks the way it does.
**Not a replacement for:** The Proto3 language guide, the Buf quickstart, or the Connect-Go getting-started. Those are authoritative. This doc is the "translation layer" between those tutorials and our specific spec.

---

## 0. The five-minute mental model

Before touching any of the spec, hold these five ideas in your head:

1. **Protobuf is a schema language.** You describe data shapes and RPC endpoints in `.proto` files. A tool (`buf generate`) turns those files into real code — Go structs and Go functions on the server, TypeScript classes and fetch-wrappers on the client. The `.proto` file is the **single source of truth**; both sides are generated from it so they can't disagree.

2. **gRPC is a "call a function on another machine" protocol.** You define a service (`GameService`) with methods (`CreateGame`, `SubmitAction`, …). On the server you implement those methods like normal Go functions. On the client you call them like normal Go (or TS) functions. The generated code handles serialization, HTTP, errors, and streams behind the scenes.

3. **Connect is a modern gRPC implementation that also speaks plain HTTP+JSON.** Classic gRPC requires HTTP/2 and is painful in browsers. Connect speaks three wire formats — gRPC, gRPC-Web, and its own Connect protocol — over HTTP/1.1 or HTTP/2. Same `.proto` file, same generated code, just more friendly at the edges. That's why we chose `connectrpc.com/connect` instead of raw `google.golang.org/grpc`.

4. **Every RPC is one of four shapes.** The shape controls how many messages flow each way:
   - **Unary:** one request, one response. Like a normal function call. (`CreateGame`, `SubmitAction`.)
   - **Server-streaming:** one request, *many* responses. Client asks once, server keeps pushing updates until it decides to stop. (`StreamGameEvents`.)
   - **Client-streaming:** many requests, one response. (Not used in this project.)
   - **Bidirectional streaming:** many each way. (Not used in this project.)

5. **Server-authoritative means the server owns the truth.** The client never computes whether an action is legal, never mutates "its own copy" of game state, and never trusts anything it computed locally. It sends "I want to do X" and the server either applies it and broadcasts the result, or returns an error. Every client (bot, React app, future mobile app) ends up with an *identical* view of the game because they all reduce the same event stream from the same authoritative source.

If those five ideas feel solid, the rest of Section 3 is just details fitting into this skeleton.

---

## 1. "One service, three RPCs" — what's actually going on

The spec shows this block:

```proto
service GameService {
  rpc CreateGame(CreateGameRequest) returns (CreateGameResponse);
  rpc StreamGameEvents(StreamGameEventsRequest) returns (stream GameEvent);
  rpc SubmitAction(SubmitActionRequest) returns (SubmitActionResponse);
}
```

Let's decode each line.

### `service GameService { ... }`
You're declaring a *service* named `GameService`. After `buf generate`, this becomes:

- **On the Go server side:** a Go *interface* you implement. Something like:
  ```go
  type GameServiceHandler interface {
      CreateGame(context.Context, *connect.Request[pb.CreateGameRequest]) (*connect.Response[pb.CreateGameResponse], error)
      StreamGameEvents(context.Context, *connect.Request[pb.StreamGameEventsRequest], *connect.ServerStream[pb.GameEvent]) error
      SubmitAction(context.Context, *connect.Request[pb.SubmitActionRequest]) (*connect.Response[pb.SubmitActionResponse], error)
  }
  ```
  Your job in `internal/service/game_service.go` is to write a Go struct that satisfies this interface. Each method receives the request, calls the engine, and returns a response.

- **On the Go bot client side:** a ready-to-call *client struct*:
  ```go
  client := gamev1connect.NewGameServiceClient(httpClient, "http://localhost:8080")
  resp, err := client.CreateGame(ctx, connect.NewRequest(&pb.CreateGameRequest{ Players: []string{"bigmoney", "smithy_bm"} }))
  ```
  You call it like any normal Go function. Connect handles the HTTP request, protobuf marshalling, and error translation under the hood.

- **On the future TS client side:** the same thing in TypeScript:
  ```ts
  const client = createPromiseClient(GameService, transport);
  const resp = await client.createGame({ players: ["human", "bigmoney"] });
  ```

One `.proto` file → three generated surfaces, all in agreement. That's the whole reason we chose this approach.

### `rpc CreateGame(CreateGameRequest) returns (CreateGameResponse);`
This is a *unary* RPC: one request, one response. It's shaped exactly like `func CreateGame(req) resp`. The types `CreateGameRequest` and `CreateGameResponse` are **messages** — protobuf's word for a record/struct. They're defined elsewhere in the `.proto` file.

Why have request/response wrapper messages instead of taking the raw params? Two reasons:
- **Forward compatibility.** If you later want to pass more arguments, you add a field to the request message. Old clients that don't set it still work. If you had taken bare positional params, that would be a breaking change.
- **Protobuf requires it.** The language mandates message types for RPC inputs and outputs. There's no "bare argument" option.

### `rpc StreamGameEvents(StreamGameEventsRequest) returns (stream GameEvent);`
The magic word is `stream`. Put in front of the return type, it means "the server will send *many* `GameEvent` messages back on the same connection." The client calls this once and then receives a sequence of events until the server closes the stream.

In Go, the generated client feels like:
```go
stream, err := client.StreamGameEvents(ctx, connect.NewRequest(&pb.StreamGameEventsRequest{GameId: id}))
for stream.Receive() {
    event := stream.Msg()
    // handle event
}
if err := stream.Err(); err != nil {
    // stream broke
}
```
On the server, you implement the handler by writing a loop that calls `stream.Send(event)` whenever something happens, and returning nil when the game ends (or the client disconnects).

This is how we get "real-time-ish" game updates without the bot (or the future React client) having to poll.

### `rpc SubmitAction(SubmitActionRequest) returns (SubmitActionResponse);`
Another plain unary RPC, but with a twist in *what it does*. The bot calls it to say "I want to play Smithy" or "here's my answer to that decision prompt." The server validates, applies, and returns a simple ack. The actual **results** of the action (new hand, new phase, events for other players) arrive not in the response but on the `StreamGameEvents` stream.

This split is intentional: the response says "yes I accepted it" or "no here's why it was illegal"; the stream says "here is what changed as a result." It means every client sees the same event sequence in the same order, regardless of who submitted the action.

---

## 2. The Action oneof — "why not one RPC per action type?"

This spec block:

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

Needs two newcomer concepts unpacked: **messages with fields**, and **oneof**.

### Messages and fields
A `message` is a protobuf record. Every field has:
- a **type** (`string`, `int32`, another message, enum, etc.),
- a **name** (what you call it in code),
- a **field number** (the `= 1`, `= 2`, … at the end).

The field number is what actually goes on the wire. The name is only for humans and code generation. **Field numbers must never change or be reused** once a schema is in production — doing so breaks every old client that still has the old meaning cached. (Field *names* can be renamed freely, because they're not on the wire. That's often surprising to newcomers.)

### `oneof`
An `oneof` says: "this message contains exactly one of the following fields, and you can tell which one at runtime." It's the protobuf version of a tagged union / sum type / Rust enum with data / TypeScript discriminated union.

In Go, the generated type looks roughly like:
```go
type Action struct {
    // Kind is the oneof; exactly one of the following is non-nil.
    Kind isAction_Kind  // interface with private method
}

type Action_PlayCard struct { PlayCard *PlayCardAction }
type Action_BuyCard  struct { BuyCard  *BuyCardAction  }
// ... etc, each implements isAction_Kind

// To read:
switch k := action.Kind.(type) {
case *Action_PlayCard: /* k.PlayCard is your payload */
case *Action_BuyCard:  /* k.BuyCard is your payload */
// ...
}
```

So when the bot wants to play Smithy, it builds an `Action` whose `Kind` is `*Action_PlayCard{PlayCard: &PlayCardAction{CardId: "smithy"}}`, sticks it in a `SubmitActionRequest`, and sends it.

### Why one RPC + oneof instead of many RPCs?

Alternative design (not chosen):
```proto
rpc PlayCard(PlayCardRequest)   returns (PlayCardResponse);
rpc BuyCard(BuyCardRequest)     returns (BuyCardResponse);
rpc EndPhase(EndPhaseRequest)   returns (EndPhaseResponse);
rpc ResolveCellarDiscard(...)   returns (...);
rpc ResolveChapelTrash(...)     returns (...);
rpc ResolveThroneRoomChoice(...) returns (...);
// ... ~15 more RPCs
```

This is what a naive design looks like. It has problems:
1. **Adds one RPC per card's decision type.** Every new card means touching `service GameService`, which is the one thing you really want to stay stable.
2. **Fragments error handling and logging.** Every handler is its own function, duplicating the "look up the game, check the player's turn, call the engine, translate result" glue.
3. **Doesn't match the engine.** The engine's internal `Action` type is already a union. Mapping one server method per action type means the service layer has to know about every variant, rather than just saying "translate this proto oneof into an engine.Action and call Apply."

With the oneof approach:
- Service layer is **one switch statement** turning proto `Action` into engine `Action`.
- Adding a new card is additive: you add a new field to the oneof (new field number), regenerate, implement it in the engine. No existing clients break.
- Error handling, logging, and metrics are all in one place.

The trade-off: the proto type is slightly less self-documenting (you can't see in the service definition what all the possible actions are). That's fine — Section 3's `Decision` message documents the prompts, and the oneof documents the four action kinds.

---

## 3. Mid-effect decisions — the trickiest conceptual piece

The Dominion rulebook is full of cards that stop mid-effect and ask the player a question. Chapel says "trash *up to 4* from your hand" — the engine can't just resolve the effect, it has to wait for the player to pick which cards. Throne Room says "play an action twice" — but that action might itself ask for a choice, and after that choice the *second* play still has to happen.

Naive solutions all lead to pain:
- **Synchronous callbacks.** Would require the engine to call back into the client mid-RPC. Not possible across a network boundary.
- **One RPC per prompt type.** Leads to the "~15 RPCs" anti-pattern above.
- **Embedding choices in the initial action.** "PlayChapelWithTrashChoices([Estate, Estate, Copper])" — but the player doesn't know what's in their hand until they look, and this completely breaks Throne Room (you don't know the second play's prompt until the first play resolves).

### The chosen solution: pending_decision as a game-state field

The engine's `GameState` has a field:
```proto
Decision pending_decision = N;  // nullable
```

When it's *null*, the game is in its default state. The player whose turn it is can take free actions (PlayCard, BuyCard, EndPhase).

When it's *non-null*, the game is paused mid-effect. Whatever action most recently ran set this field and then stopped executing. The **only** legal next action from the deciding player is a `ResolveDecision` whose `decision_id` matches `pending_decision.id`. Any other action returns an error ("decision pending"). Any free action just isn't legal right now.

This means:
- **Decisions are state, not control flow.** The engine doesn't block waiting for anything. It returns a state with `pending_decision` set, then exits. Later, when `ResolveDecision` arrives, it picks up where it left off.
- **The protocol is stateless in the RPC layer.** No long-running RPC holds the connection. Each RPC is a short round-trip. A client can disconnect, reconnect, and resume — the decision is safely stored server-side in game state.
- **The same mechanism works for every card.** Chapel, Cellar, Throne Room, Witch's victims, Sentry's three-step choice — all use the same `pending_decision` field with different prompt contents.

### The Decision message

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
```

- `id` is a random server-generated string. The client echoes it back when answering. This prevents race conditions: if the client has a stale view and answers an old decision, the server can recognize "that's not the current decision id" and reject.
- The `oneof prompt` is the same union pattern as `Action`, specialized to the kinds of questions Base set cards can ask.

**There are only 6–8 prompt types total.** Every Base set card reuses these. Chapel uses `TrashFromHandPrompt`. Cellar uses `DiscardFromHandPrompt`. Workshop uses `GainFromSupplyPrompt` (with a cost filter). Moneylender uses `YesNoPrompt`. Throne Room uses `PlayActionTwicePrompt` (which internally triggers recursive play and may itself yield more decisions).

### The ResolveDecision message

```proto
message ResolveDecision {
  string decision_id = 1;
  oneof answer {
    CardSelection cards   = 2;
    bool          yes_no  = 3;
    int32         index   = 4;
  }
}
```

Three answer types cover every prompt:
- **`cards`** — "here are the cards I chose." Used by Chapel (trash these), Cellar (discard these), Militia (discard to 3), etc.
- **`yes_no`** — for cards that ask a simple yes/no (Moneylender: "trash a Copper?", Vassal: "play this revealed action?").
- **`index`** — pick one of a numbered list (used when the server presents a list and the client picks by position, e.g., Harbinger).

Notice the symmetry: the Decision says "here's what I'm asking," the ResolveDecision says "here's my answer, referencing decision_id so we agree on *which* question." This is the minimum round-trip needed to survive network delays and reconnects.

---

## 4. Events — the server-streaming contract

```proto
message GameEvent {
  uint64 sequence = 1;
  google.protobuf.Timestamp at = 2;
  oneof kind {
    GameStateSnapshot    snapshot       = 3;
    PlayerActionApplied  action_applied = 4;
    PhaseChanged         phase_changed  = 5;
    TurnStarted          turn_started   = 6;
    DecisionRequested    decision       = 7;
    GameEnded            ended          = 8;
  }
}
```

### Why events and not "just give me the state on every change"?

You *could* define an RPC that returns the full game state on request. The client would call it after every submission. That works, but:

- It's **chatty.** Every action means a second round-trip to fetch new state.
- It's **lossy.** If you miss an intermediate state, you don't know *what happened* — only what changed. "Why did my opponent's deck shrink by 4?" is unanswerable from snapshots alone.
- It's **bad for the game log.** The UI wants to say "Alice played Smithy, drew 3 cards." If all you have is before/after snapshots, you have to infer which event caused which delta. Events make that explicit.

So instead: the server pushes **a log of what happened**, in order. The client reduces the log into a state in its head.

### Sequence numbers and the snapshot-then-delta pattern

- **Every event has a monotonic `sequence` field**, per game. The first event is 1, then 2, then 3, etc. If a client sees `10` followed by `12`, it knows it missed `11` and must reconnect.
- **The first event after subscribing is always a full snapshot.** This means a fresh client doesn't have to reconstruct state from the beginning — it gets the current state handed to it, then just applies incoming deltas going forward.
- **Reconnect = resubscribe.** The client drops the stream, opens a new one, gets a fresh snapshot at whatever the current sequence is, and carries on. It doesn't need to know what it missed — the snapshot contains everything.

This is robust against dropped connections, flaky networks, and even servers restarting (as long as game state survives, which it will once Phase 2 persistence lands).

### The client-side reduction loop

```go
state.Apply(event)
```

The client keeps an internal `ClientState`, and `Apply(event)` mutates it based on the event kind:
- Snapshot → replace the whole state.
- ActionApplied → update the actor's hand/discard/in-play, apply resource changes.
- PhaseChanged → update `state.Phase`.
- DecisionRequested → set `state.PendingDecision`.
- Ended → set `state.Ended`.

This reducer is exactly the same shape the React frontend will need (it's the classic Redux pattern). Writing and testing it once in Go for the bot proves the semantics before the TS version exists.

---

## 5. The symmetric client loop — why bots and UIs share it

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

The newcomer-friendly version: **a client is a reducer plus a decision function.** That's it.

1. **Reducer** — `state.Apply(event)`. Pure function: old state + event → new state. No I/O.
2. **Decision function** — given the current state, produce the next action (or "nothing to do, wait for more events").

The loop alternates: receive → reduce → maybe act → repeat. The bot's "decision function" is a strategy (`BigMoney`, `SmithyBM`). The React app's "decision function" is "render the UI and wait for the user to click something." Both plug into the same shape because both are reducing the same event stream.

The deep reason this works: **the server is authoritative**. The client's job is only to (a) display accurately and (b) submit intent. It's never in charge of deciding what's legal or computing state transitions. So the same loop works for every kind of client — CLI bot, web browser, future mobile app, a debug REPL, anything.

---

## 6. Field numbers, forward compatibility, and `buf breaking`

You'll see weird things like `= 1`, `= 2`, `= 7` in every message. These are **field numbers**. Three rules for newcomers:

1. **Field numbers are permanent.** Once a number is used in a deployed schema, it belongs to that field forever. Never change the number. Never reuse a deleted number for a new field.
2. **Field numbers 1–15 are one-byte-encoded, 16+ are two bytes.** Use low numbers for fields that appear in every message (e.g., `sequence` on `GameEvent`). Use higher numbers for rarely-set fields. (Micro-optimization, not critical early on, but it's the convention.)
3. **`buf breaking` enforces these rules in CI.** It compares the proto schema against `main` and fails the build if you change a number, remove a field, or change a type in a way that would break existing clients. This means you can't accidentally ship a backwards-incompatible change; it'll be caught in PR review.

The same tool (`buf`) also runs `buf lint` (style / naming rules) and `buf generate` (the codegen step that produces `gen/go/` and later `gen/ts/`). Those three commands are the entire interaction with protobuf you'll have day-to-day.

---

## 7. How Section 3 fits into the rest of the spec

- **Section 2 (repo layout)** puts `.proto` files in `proto/dominion/v1/`. Running `buf generate` populates `gen/go/` with Go stubs that the server and bot both import.
- **Section 4 (engine structure)** is on the other side of a translation boundary. The engine has its own `Action` type (Go interface with four implementers) that looks *similar* to the proto `Action` oneof but is decoupled. `internal/service/game_service.go` is the only place that converts between them.
- **Section 5 (card representation)** is pure engine — it has no protobuf dependencies. Cards are internal Go data; they serialize to the protobuf wire types only when a client asks for game state.
- **Section 6 (bot client, coming up next)** is the first concrete consumer of the generated Go client. It proves the contract is implementable without any engine knowledge.

If Section 3 is the **contract**, Sections 4 and 5 are the **server-side engine hidden behind it**, and Section 6 is the **first client that has to live with the contract in practice**. That's the rationale for building in that order.

---

## 8. Minimum reading list for "I want to actually write this"

When you're ready to start touching code, work through these in order:

1. **Proto3 language guide** — https://protobuf.dev/programming-guides/proto3/
   Read: messages, fields, enums, oneof, well-known types (`Timestamp`). Skip: proto2 differences, extensions, `Any`.

2. **Buf quickstart** — https://buf.build/docs/tutorials/getting-started-with-buf-cli
   Read: `buf.yaml`, `buf.gen.yaml`, `buf generate`, `buf lint`, `buf breaking`. You'll know enough to configure our `proto/` directory.

3. **Connect-Go getting started** — https://connectrpc.com/docs/go/getting-started
   Read: setting up a server, implementing a handler, the client API, streaming handlers. Our `internal/service/` is directly modelled on their examples.

4. **Dominion rulebook** — you probably know this already. If not, the Base set 2nd edition PDF is widely available. Critical for understanding why the `Decision` prompt set looks the way it does.

You do not need to read anything about raw gRPC (`google.golang.org/grpc`) — we're not using it. Connect-Go is the only RPC library we touch.

---

## 9. Quick terminology cheat sheet

| Term | What it means in this project |
|---|---|
| **IDL** (Interface Definition Language) | Protobuf `.proto` syntax. |
| **Message** | Protobuf's word for a struct/record. |
| **Service** | A collection of RPC methods. We have one: `GameService`. |
| **RPC** | "Remote procedure call" — a single method on a service. We have three. |
| **Unary** | One-request-one-response RPC. `CreateGame`, `SubmitAction`. |
| **Server-streaming** | One request, many responses streamed back. `StreamGameEvents`. |
| **oneof** | Tagged union. Exactly one field set at a time. |
| **Field number** | The `= N` after each field. On-the-wire identifier. Never change it. |
| **Codegen** | Running `buf generate` to produce language-specific code from `.proto`. |
| **Stub** | The generated code. `gen/go/` for Go, `gen/ts/` for TypeScript. |
| **Handler** | Server-side implementation of an RPC method. Lives in `internal/service/`. |
| **Client stub** | Generated type you call from client code to invoke an RPC. |
| **Connect** | The RPC framework/library we use. `connectrpc.com/connect`. |
| **gRPC** | The protocol family Connect speaks. We don't use the `google.golang.org/grpc` library directly. |
| **BSR** (Buf Schema Registry) | A package registry for `.proto` files. Phase 2 concern, ignore for now. |
| **`pending_decision`** | The game-state field that pauses play until the current player answers. |
| **Sequence number** | Per-game monotonic event counter. Lets clients detect dropped events. |
| **Snapshot** | Full game state event, used as the baseline when a client subscribes or reconnects. |
| **Server-authoritative** | The server is the only source of truth; clients are observers + intent-submitters. |

---

That's the full unpacking of Section 3. Nothing in the spec changes — this doc just explains the *why* behind what's already written. When Section 6 (bot client) builds on top of these concepts, you should be able to recognize each piece as a direct consequence of the contract laid out here.
