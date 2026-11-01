# Console Event Flow

## Startup and Ownership

[main](../../../apps/console/src/main.rs) enters a Tokio runtime before creating
App. App::default creates EventHandler, whose constructor immediately spawns
the producer task. Constructing EventHandler therefore requires an active
Tokio runtime; its Default implementation has the same requirement.

[App](../../../apps/console/src/app.rs) owns the running flag, counter, and
event receiver. [ui.rs](../../../apps/console/src/ui.rs) implements Widget for
&App, so rendering reads state through a borrow rather than owning the input
loop or mutating the counter.

## Input to State

[Event and AppEvent](../../../apps/console/src/event.rs) define the local
message vocabulary:

```text
EventTask: terminal input / interval tick
    -> EventHandler receiver
    -> App::run
       -> key press -> App::handle_key_events -> queued AppEvent
       -> AppEvent dispatch -> state mutation
    -> next render through Widget for &App
```

Key handling queues an action; it does not mutate the counter immediately.
App::run accepts key Press events, dispatches typed actions, and redraws at the
start of each loop iteration. The tick interval is not a maximum render rate:
input and application events also cause loop iterations. App::tick is currently
a no-op.

Keep new Console actions in the existing event vocabulary and App dispatch
path when extending this scaffold. Keep terminal reading in the producer and
rendering in ui.rs rather than creating parallel input loops inside widgets.

## Concrete State Behavior

The current increment implementation in app.rs is:

```rust
pub fn increment_counter(&mut self) {
    self.counter = self.counter.saturating_add(1);
}
```

Decrement uses saturating_sub on the same u8 counter. Preserve saturation when
making an unrelated Console change; wrapping or panicking arithmetic changes
the existing behavior. Quit sets the running flag to false.

## Producer Lifecycle and Limits

EventTask::run uses Tokio select over receiver closure, the interval, and
successful Crossterm events. Dropping the receiver permits the producer's
closed branch to stop it. This is a local shutdown mechanism, not a persisted
execution or cancellation protocol.

The current channel is unbounded and the spawned JoinHandle is not retained.
These are scaffold limitations, not recommended backpressure or supervision
patterns for durable work. Do not claim that queued events survive process
exit or that task failure is automatically observed. See
[error handling](error-handling.md) for the actual failure boundaries.
