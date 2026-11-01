# Console Errors and Terminal Lifecycle

## Application Error Boundary

[main](../../../apps/console/src/main.rs), [App::run](../../../apps/console/src/app.rs),
and [EventHandler::next](../../../apps/console/src/event.rs) use color-eyre
Results. main installs the reporting hook; App::run propagates drawing and
event-receive failures with ?. Follow this existing application boundary when
extending Console instead of silently treating a failed operation as success.

This is application behavior, not an implemented shared-library error API.
The library currently has no domain error hierarchy to copy.

## Restore Before Returning a Run Error

The terminal entry point keeps the run result until after restoration:

```rust
let result = App::new().run(terminal).await;
ratatui::restore();
result
```

Keep restoration on this returned-error path. Replacing the captured result
with an early ? at that point would skip the explicit restore call.

This source sequence describes normal return and returned errors. Inspect the
installed library panic handling separately before changing panic behavior;
the explicit restore call alone does not prove handling of every termination
path.

## Receive and Send Behavior

EventHandler::next converts a closed receiver into a report using:

```rust
self.receiver
    .recv()
    .await
    .ok_or_eyre("Failed to receive event")
```

That conversion is not a producer-health protocol. EventHandler also owns a
sender, and the producer JoinHandle is discarded; producer termination is not
automatically surfaced as an App error.

The current send methods intentionally ignore send failure: an application
action retains its receiver through the handler, while producer sends can race
receiver shutdown. Keep this narrow local rationale separate from network or
durable delivery, where ignoring failure would have different consequences.

## Known Gaps, Not Guarantees

EventTask::run forwards only successful input items and does not turn reader
errors into application error events. Its returned Result is not observed
through a retained JoinHandle. Do not document centralized background-error
propagation, durable acknowledgement, or automatic retry based on this code.

Address those behaviors only in a task that authorizes the required code
change. A spec refresh records the limits; it does not fix them implicitly.
