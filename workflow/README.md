# Dapr Workflow demos

Demo apps for the Dapr University Workflow 101 track, in .NET, Python, Java and TypeScript. The story: the bridge of the *ISV Meridian* orders a **warp jump**, and the ship's **engineering** console runs it as a Dapr workflow. Each demo shows one thing workflows give you:

- **Durable execution:** a workflow survives a crash and carries on from the last completed step.
- **Task chaining, fan-out/fan-in and monitor:** the common workflow patterns.
- **Human in the loop:** a workflow that waits for an external event.
- **Management:** pause, resume, terminate and purge a running workflow.

A workflow is ordinary code in your app. The Dapr sidecar runs it: it schedules each step, saves the workflow's history in a state store, and replays the code from that history when the app comes back after a crash. Your app hosts the workflow and its activities, and calls the sidecar through the Dapr Workflow SDK.

In Instruqt the sandbox setup script prepares everything below for you. Use this guide to run the demos on your own machine.

## Prerequisites

- [Dapr CLI](https://docs.dapr.io/getting-started/install-dapr-cli/) 1.19.1 and a completed `dapr init --runtime-version 1.19.1` (Docker required). The demos keep workflow state in the Redis container that `dapr init` starts.
- `lsof`, which the smoke-test scripts use to stop the demo apps
- The runtime for the language you want to run:
  - .NET SDK 10
  - Python 3.12 or later with [uv](https://docs.astral.sh/uv/)
  - Java 17 with Maven (the Java demos use Spring Boot 4.0.8)
  - Node.js 24. Run `npm install` once in each TypeScript demo's `engineering` folder before the first `dapr run`.

The shell commands below assume a POSIX shell (Git Bash, WSL, macOS or Linux). The track itself runs on a Linux sandbox.

Every demo uses the same app ID and ports in every language, so run one demo at a time:

| App | App port | Dapr HTTP port | Dapr gRPC port |
|---|---|---|---|
| `engineering` | 5301 | 3530 | 50330 |

The workflow SDKs talk to the sidecar over gRPC, which is why each `dapr.yaml` also sets the gRPC port.

## The demos

| Challenge | .NET folder | Python, Java and TypeScript folder | What it shows |
|---|---|---|---|
| 1 | `Demo1-DurableExecution` | `demo1-durable-execution` | A five-stage warp-core charge that survives a crash: stop the app halfway, start it again, and it continues with the next stage. |
| 2 | `Demo2-TaskChaining` | `demo2-task-chaining` | Four activities in sequence, each one's output the next one's input: plot the course, charge the warp core, align the nav array, engage. |
| 3 | `Demo3-FanOutFanIn` | `demo3-fan-out-fan-in` | Five sensor arrays scan the route in parallel; the workflow waits for all of them and combines the results. |
| 4 | `Demo4-Monitor` | `demo4-monitor` | The workflow checks the core temperature until it is stable, with a durable timer and continue-as-new between checks. |
| 5 | `Demo5-HumanInTheLoop` | `demo5-human-in-the-loop` | The workflow waits for the captain's authorization, an external event, with a timeout. |
| 6 | `Demo6-Management` | `demo6-management` | A long jump you pause, resume, terminate and purge through the SDK's workflow client. |

Folder names follow each language's conventions: .NET uses PascalCase (`Demo1-DurableExecution/Engineering`), Python, Java and TypeScript use kebab-case (`demo1-durable-execution/engineering`).

Every demo runs the same way. Pick the folder for your language and the demo you want, for example Demo 1:

```bash
cd workflow/dotnet/Demo1-DurableExecution   # Python: workflow/python/demo1-durable-execution, Java: workflow/java/demo1-durable-execution, TypeScript: workflow/typescript/demo1-durable-execution
dapr run -f .
```

Stop it with Ctrl+C, which stops both the app and its sidecar. Run the `curl` commands in a second terminal. The first run of a Java demo is slow while Maven downloads dependencies.

Each language's `resources/statestore.yaml` points at the `dapr init` Redis and sets `actorStateStore: "true"`: Dapr Workflow is built on actors, and keeps each workflow's history in the actor state store. The app never uses the component's name.

### The endpoints

The apps expose a few HTTP endpoints so you can drive the workflows with `curl`. Each one is a thin shell around the SDK's workflow client. Every demo has these two:

| Method and route | What it does |
|---|---|
| `POST /jumps` | Starts a workflow. Body: `{"jumpId": "jump-001", "destination": "Vesper Reach"}`. Both fields are optional: `jumpId` defaults to a generated ID such as `jump-3f9c2a1b`, `destination` to `Vesper Reach`. `jumpId` becomes the workflow instance ID. Answers `202 {"jumpId": "jump-001"}`. |
| `GET /jumps/{jumpId}` | Answers `{"jumpId": …, "status": …, "output": …}`. `status` is `RUNNING`, `COMPLETED`, `FAILED`, `TERMINATED` or `SUSPENDED`, and `output` is the workflow's result, or `null` while it runs. An unknown ID answers `404 {"error": "JUMP_NOT_FOUND"}`. |

When a call to Dapr fails, the endpoint answers `500 {"error": "WORKFLOW_ERROR"}` and the app logs a warning that starts with `engineering workflow call failed:`.

The apps log the same lines in every language. Each language adds its own prefix (`INFO:engineering:` in Python, a timestamp and logger name in Java, `info: <class>` on the line above in .NET), and the TypeScript SDK also logs a few lines of its own for every workflow step. The expected output below shows the lines without those extras.

### Fresh IDs and leftover workflows

Workflow state lives in Redis, which every language and demo shares, and every demo uses the app ID `engineering`. Two things follow from that.

**Reusing a jump ID.** The `curl` commands below use readable IDs such as `jump-001`. Starting a jump with the ID of one that has finished (`COMPLETED`, `FAILED` or `TERMINATED`) starts it over: the old history and result are replaced. Starting one with the ID of a jump that is still running answers `500 {"error": "WORKFLOW_ERROR"}` and the app logs:

```text
engineering workflow call failed: ... an active workflow with ID 'jump-001' already exists
```

Use a new ID, or leave out `jumpId` and let the app generate one.

**Leftover workflows.** A jump that is still running when you stop a demo is picked up again by the next `engineering` app you start, even one from another demo that doesn't have that workflow. So end each demo with the clean-up step below. It uses the Dapr CLI's `dapr workflow` commands, which talk to the running sidecar, so run it while the demo is still running:

```bash
# List every jump of the engineering app and its status.
dapr workflow list -a engineering
# Terminate each jump that is still RUNNING or SUSPENDED, for example:
dapr workflow terminate jump-001 -a engineering
# Remove the history of every finished jump.
dapr workflow purge --all -a engineering
```

Only terminate jumps that are still running or suspended. On Dapr 1.19.1, terminating a jump that has already finished leaves it in a stalled state, and `purge --all` then fails for it. If that happens, `dapr workflow purge --all --force -a engineering` removes it.

### Demo 1: durable execution

`ChargeWarpCoreWorkflow` charges the warp core in five stages. It calls one activity, `ChargeStageActivity`, five times in a plain loop. Each stage takes about three seconds and then logs a line. When all five are done, the workflow returns `{"jumpId": "jump-001", "coreCharged": true}`.

Two building blocks of every workflow app show up here:

- **The workflow** (`ChargeWarpCoreWorkflow`) decides what happens in which order. It doesn't do the work itself.
- **An activity** (`ChargeStageActivity`) does the work: it can be slow, call other services or write to a database.

Run the demo, then start a jump in a second terminal:

```bash
curl -s -X POST http://localhost:5301/jumps -H 'Content-Type: application/json' -d '{"jumpId": "jump-001"}'
```

```json
{"jumpId":"jump-001"}
```

`engineering` logs:

```text
engineering jump-001 charge sequence started
engineering charge stage 1/5 complete for jump-001
engineering charge stage 2/5 complete for jump-001
```

Now crash the ship. **Right after stage 2 completes, press Ctrl+C** in the terminal that runs the demo. That stops the app and its sidecar while stage 3 is running. Then start it again:

```bash
dapr run -f .
```

Don't send another `curl`. Within a few seconds of the app being ready, the log carries on:

```text
engineering charge stage 3/5 complete for jump-001
engineering charge stage 4/5 complete for jump-001
engineering charge stage 5/5 complete for jump-001
```

Check the jump:

```bash
curl -s http://localhost:5301/jumps/jump-001
```

```json
{"jumpId":"jump-001","status":"COMPLETED","output":{"jumpId":"jump-001","coreCharged":true}}
```

What happened:

- **Completed stages didn't run again.** Every time an activity finishes, the sidecar records its result in the workflow's history in the state store. Each `await` (or `yield` in Python and TypeScript) on an activity is a checkpoint. Stages 1 and 2 were in the history before the crash, so they were not repeated.
- **The stage that was running did run again.** Stage 3 had not reported back when the app stopped, so after the restart the sidecar sent it to the app again. Activities run at least once, so they should be safe to repeat. In Python you may even see `stage 3/5 complete` during the shutdown: the activity finished, but its result never reached the sidecar, so it still runs again.
- **The workflow code itself ran again, from the top.** After the restart the sidecar replayed `ChargeWarpCoreWorkflow` to rebuild where it was. On a replay the SDK hands the stored results of stages 1 and 2 straight back instead of running those activities. The `charge sequence started` line is written with a replay-safe logger (or an `is replaying` check), so it doesn't appear a second time even though that line of code ran again.

Because the workflow code is replayed, it must be **deterministic**: every replay has to make the same calls in the same order. So the workflow never reads the clock, makes random numbers, does I/O or sleeps. The three-second wait is inside the activity, which is where that kind of work belongs.

The app also has no database code. The state store component is only used by the sidecar, which saves and loads the workflow history.

If you use the [Dapr Dev Dashboard](https://docs.diagrid.io/develop/local-development/dev-dashboard/), a local dev tool, it lists the `engineering` app and its `ChargeWarpCoreWorkflow` runs, read from the same Redis state store.

**Clean up.** `jump-001` has finished, so purge it (or use the steps in [Fresh IDs and leftover workflows](#fresh-ids-and-leftover-workflows)) before you stop the demo:

```bash
dapr workflow purge jump-001 -a engineering
```

### Demo 2: task chaining

`JumpWorkflow` runs four activities in sequence, and each activity's result is the next one's input:

| Step | Activity | Gets | Returns |
|---|---|---|---|
| 1 | `PlotCourseActivity` | the destination | `{"destination": "Vesper Reach", "heading": 217, "distanceLy": 4.2}` |
| 2 | `ChargeWarpCoreActivity` | the course | `{"warpFactor": 6}` |
| 3 | `AlignNavArrayActivity` | the warp factor | `{"aligned": true}` |
| 4 | `EngageJumpActivity` | the course and the warp factor | `{"arrivedAt": "Vesper Reach", "stardate": 85831.8}` |

Each activity takes about a second, so you can watch the chain progress. The workflow's output is the result of the last step. The heading, distance and warp factor are fixed values, so every run and every language logs the same lines. Only the stardate changes: `EngageJumpActivity` computes it from the clock, which is fine in an activity but never in the workflow.

This is the chain pattern: in the workflow code it is just a few lines in a row, with each result passed to the next call. Because every activity result is saved in the workflow's history, a crash between two steps doesn't redo the steps that finished (the Demo 1 lesson, now with different activities).

Run the demo, then start a jump in a second terminal:

```bash
curl -s -X POST http://localhost:5301/jumps -H 'Content-Type: application/json' -d '{"jumpId": "jump-001", "destination": "Vesper Reach"}'
```

```json
{"jumpId":"jump-001"}
```

`engineering` logs, one line about every second:

```text
engineering course plotted to Vesper Reach heading=217 distanceLy=4.2
engineering warp core charged to warp 6
engineering nav array aligned
engineering jump complete, arrived at Vesper Reach
```

After about four seconds:

```bash
curl -s http://localhost:5301/jumps/jump-001
```

```json
{"jumpId":"jump-001","status":"COMPLETED","output":{"arrivedAt":"Vesper Reach","stardate":85831.8}}
```

Your stardate will differ. A whole number may show without the `.0`, depending on the language.

Try the defaults. Leave out the body, or the destination, and the jump flies to Vesper Reach. A `null` or empty destination does the same:

```bash
curl -s -X POST http://localhost:5301/jumps -H 'Content-Type: application/json' -d '{}'
```

```json
{"jumpId":"jump-3f9c2a1b"}
```

Try another destination, and watch it travel down the chain:

```bash
curl -s -X POST http://localhost:5301/jumps -H 'Content-Type: application/json' -d '{"jumpId": "jump-002", "destination": "Calder Station"}'
```

Finally, reuse an ID. While `jump-003` is still running, starting it again fails:

```bash
curl -s -X POST http://localhost:5301/jumps -H 'Content-Type: application/json' -d '{"jumpId": "jump-003"}'
curl -s -X POST http://localhost:5301/jumps -H 'Content-Type: application/json' -d '{"jumpId": "jump-003"}'
```

```json
{"jumpId":"jump-003"}
{"error":"WORKFLOW_ERROR"}
```

Once `jump-003` has completed, the same call answers `202` and the jump starts over: the chain runs again and the old result is replaced.

**Clean up.** Purge the finished jumps (or use the steps in [Fresh IDs and leftover workflows](#fresh-ids-and-leftover-workflows)) before you stop the demo:

```bash
dapr workflow purge --all -a engineering
```

### Demo 3: fan-out/fan-in

`RouteScanWorkflow` scans the route with five sensor arrays at the same time, then combines the results. `ScanSectorActivity` takes the name of an array, scans for 2 seconds and returns a hazard score:

| Array | Hazard |
|---|---|
| `alpha` | 12 |
| `beta` | 7 |
| `gamma` | 31 |
| `delta` | 4 |
| `epsilon` | 18 |

The scores are fixed, so every run and every language gets the same result. This is the fan-out/fan-in pattern:

- **Fan-out:** the workflow schedules all five activity calls without waiting for each one in turn.
- **Fan-in:** it then waits for all of them at once, with the SDK's "when all" (`Task.WhenAll` in .NET, `wf.when_all` in Python, `ctx.allOf` in Java, `ctx.whenAll` in TypeScript), and works out `routeRisk`, the highest score, and a `verdict`: `CLEAR` below 50, otherwise `HAZARDOUS`.

Run the demo, then start a jump in a second terminal. This demo accepts a `destination` like the other demos but ignores it.

```bash
curl -s -X POST http://localhost:5301/jumps -H 'Content-Type: application/json' -d '{"jumpId": "jump-001"}'
```

```json
{"jumpId":"jump-001"}
```

`engineering` logs all five lines at about the same moment, after about two seconds:

```text
engineering sensor array beta scanned hazard=7
engineering sensor array alpha scanned hazard=12
engineering sensor array gamma scanned hazard=31
engineering sensor array epsilon scanned hazard=18
engineering sensor array delta scanned hazard=4
```

```bash
curl -s http://localhost:5301/jumps/jump-001
```

```json
{"jumpId":"jump-001","status":"COMPLETED","output":{"routeRisk":31,"verdict":"CLEAR"}}
```

Two things to notice:

1. **The whole scan takes about 2 seconds, not 10.** Five scans of 2 seconds in a row would take 10 seconds. The runtime runs the five activities in parallel, and the workflow continues as soon as the slowest one is done.
2. **The log order changes from run to run.** The activities run at the same time, so whichever finishes first logs first. Start a second jump (`jump-002`) and compare. The workflow output doesn't change, because the results come back in the order the activities were scheduled, not the order they finished.

**Clean up.** Purge the finished jumps before you stop the demo:

```bash
dapr workflow purge --all -a engineering
```

### Demo 4: monitor

`CoreStabilityWorkflow` checks the warp-core temperature until it is stable. `ReadCoreTempActivity` takes the check number and returns the temperature in kelvin, `1240 - 60 * (check - 1)`, so every run and every language gets the same sequence:

| Check | Temperature |
|---|---|
| 1 | 1240K |
| 2 | 1180K |
| 3 | 1120K |
| 4 | 1060K |
| 5 | 1000K |

Each run of the workflow is one check:

1. It reads the temperature. At 1000K or lower the core is stable and the workflow returns `{"stable": true, ...}`.
2. If not, it waits on a **durable timer** of 5 seconds. The timer is stored by Dapr, not held in the app's memory.
3. Then it calls **continue-as-new** with the next check number. That restarts the workflow with new input and an empty history, so the history stays small however long the monitor runs. A loop inside one workflow run would grow it with every check.
4. The guard every monitor needs: at check 10 the workflow gives up and returns `{"stable": false, ...}`. With this fixed sequence it never triggers.

Run the demo, then start a jump in a second terminal. This demo accepts a `destination` like the other demos but ignores it.

```bash
curl -s -X POST http://localhost:5301/jumps -H 'Content-Type: application/json' -d '{"jumpId": "jump-001"}'
```

```json
{"jumpId":"jump-001"}
```

`engineering` logs one line about every 5 seconds:

```text
engineering core temperature check 1: 1240K
engineering core temperature check 2: 1180K
engineering core temperature check 3: 1120K
engineering core temperature check 4: 1060K
engineering core temperature check 5: 1000K
```

While the monitor runs, the status is `RUNNING`, also in the moments between two checks. The workflow state shows the in-between statuses (`CONTINUED_AS_NEW`, `PENDING`) as `RUNNING` too.

```bash
curl -s http://localhost:5301/jumps/jump-001
```

```json
{"jumpId":"jump-001","status":"COMPLETED","output":{"stable":true,"checks":5,"coreTempK":1000}}
```

**Stop the app during a wait.** Start a new jump (`jump-002`). When `check 2` is logged, stop the demo with `Ctrl+C` while the 5-second timer is waiting, then run `dapr run -f .` again. You don't send any request. Within a few seconds of the app being ready, the workflow continues with check 3. Check 1 and 2 are not repeated, because the timer and the workflow's progress are stored by Dapr, not by the app.

**Clean up.** Purge the finished jumps before you stop the demo:

```bash
dapr workflow purge --all -a engineering
```

### Demo 5: human in the loop

`AuthorizedJumpWorkflow` plots the course and then waits for the captain. It has three steps:

1. It calls `PlotCourseActivity`, the same activity as Demo 2.
2. It logs `engineering jump-001 awaiting captain's authorization`, once.
3. It waits for an **external event** named `jump-authorized`, for at most 60 seconds. The wait uses the SDK's timeout option, so the workflow doesn't need its own timer.

The demo adds one endpoint, which raises that event:

| Method and route | What it does |
|---|---|
| `POST /jumps/{jumpId}/authorize` | Raises the `jump-authorized` event. Body: `{"approved": true, "officer": "Captain Ilsa Varn"}`. Answers `202`. An unknown ID answers `404 {"error": "JUMP_NOT_FOUND"}`. A jump that has finished answers `409 {"error": "JUMP_FINISHED"}` and the event is not raised: on Dapr 1.19.1 an event sent to a finished workflow leaves it in a stalled state. |

There are three outcomes. Try each one with a new jump. While a jump waits, its status is `RUNNING` and nothing runs in the app: no thread and no timer in memory. The workflow only continues when the event arrives or the timeout passes.

**Approved.** Start a jump, wait for the awaiting line, and approve it:

```bash
curl -s -X POST http://localhost:5301/jumps -H 'Content-Type: application/json' -d '{"jumpId": "jump-001"}'
curl -s -X POST http://localhost:5301/jumps/jump-001/authorize -H 'Content-Type: application/json' \
  -d '{"approved": true, "officer": "Captain Ilsa Varn"}'
```

`engineering` logs the awaiting line and, after the approval, `engineering jump complete, arrived at Vesper Reach`:

```bash
curl -s http://localhost:5301/jumps/jump-001
```

```json
{"jumpId":"jump-001","status":"COMPLETED","output":{"status":"JUMPED","authorizedBy":"Captain Ilsa Varn"}}
```

**Denied.** The same, with `"approved": false` on a new jump (`jump-002`). The workflow logs `engineering jump-002 jump denied by Captain Ilsa Varn`, doesn't engage, and returns:

```json
{"jumpId":"jump-002","status":"COMPLETED","output":{"status":"DENIED","authorizedBy":"Captain Ilsa Varn"}}
```

**Timeout.** Start `jump-003` and send nothing. After 60 seconds the wait ends, the workflow logs `engineering jump-003 jump aborted, no authorization` and returns:

```json
{"jumpId":"jump-003","status":"COMPLETED","output":{"status":"ABORTED_NO_AUTHORIZATION"}}
```

Now try to authorize `jump-003` anyway. The jump is finished, so the app answers `409 {"error":"JUMP_FINISHED"}` and the output stays as it was.

**Stop the app during the wait.** Start a new jump (`jump-004`). When the awaiting line is logged, stop the demo with `Ctrl+C`, run `dapr run -f .` again and then authorize the jump. The workflow continues as if nothing happened, and the awaiting line is not logged a second time. The wait, and its 60-second timeout, are stored by Dapr, not by the app.

**Clean up.** Terminate any jump that is still waiting, then purge the finished ones:

```bash
dapr workflow list -a engineering
dapr workflow terminate jump-004 -a engineering
dapr workflow purge --all -a engineering
```

### Demo 6: management

`LongRangeJumpWorkflow` is a jump long enough to manage by hand. It has 10 legs. Each leg is one call to `EngageLegActivity`, which logs `engineering jump-001 leg 4/10 complete`, followed by a 5-second durable timer. A whole jump takes about a minute, and ends with `{"status": "JUMPED", "arrivedAt": "Vesper Reach"}`.

The demo adds four endpoints. Each one is a single call on the SDK's workflow client:

| Method and route | What it does |
|---|---|
| `POST /jumps/{jumpId}/pause` | Suspends the workflow. Answers `202`. |
| `POST /jumps/{jumpId}/resume` | Resumes a suspended workflow. Answers `202`. |
| `POST /jumps/{jumpId}/terminate` | Terminates the workflow. Answers `202`. |
| `DELETE /jumps/{jumpId}` | Purges the workflow's history from the state store. Answers `204`. |

An unknown ID answers `404 {"error": "JUMP_NOT_FOUND"}` on all four. Pause, resume and terminate on a jump that has finished answer `409 {"error": "JUMP_FINISHED"}` and make no call to Dapr: on Dapr 1.19.1 a control call on a finished workflow leaves it in a stalled state.

Start a jump and watch the legs in the `engineering` log:

```bash
curl -s -X POST http://localhost:5301/jumps -H 'Content-Type: application/json' -d '{"jumpId": "jump-001"}'
```

**Pause.** The status becomes `SUSPENDED` and the legs stop. Wait a while and check that no new leg line appears:

```bash
curl -s -X POST http://localhost:5301/jumps/jump-001/pause
curl -s http://localhost:5301/jumps/jump-001
```

```json
{"jumpId":"jump-001","status":"SUSPENDED","output":null}
```

**Resume.** The status is `RUNNING` again and the legs continue with the next one, not from the start:

```bash
curl -s -X POST http://localhost:5301/jumps/jump-001/resume
curl -s http://localhost:5301/jumps/jump-001
```

```json
{"jumpId":"jump-001","status":"RUNNING","output":null}
```

**Purge a running jump.** Purge removes the history, which Dapr only allows for a finished workflow. Try it on `jump-001` while it runs:

```bash
curl -s -X DELETE http://localhost:5301/jumps/jump-001
```

The answer is `500 {"error":"WORKFLOW_ERROR"}`, and the app logs a warning that ends with `orchestration has not yet completed`. The jump is still `RUNNING`.

**Terminate.** Start a second jump, `jump-002`, and terminate it. The status becomes `TERMINATED` and no more legs are logged:

```bash
curl -s -X POST http://localhost:5301/jumps -H 'Content-Type: application/json' -d '{"jumpId": "jump-002"}'
curl -s -X POST http://localhost:5301/jumps/jump-002/terminate
curl -s http://localhost:5301/jumps/jump-002
```

```json
{"jumpId":"jump-002","status":"TERMINATED","output":null}
```

Pausing `jump-002` now answers `409 {"error":"JUMP_FINISHED"}`, and `GET` still answers.

**Purge.** A terminated jump is finished, so it can be purged. The answer is `204`, and the history is gone:

```bash
curl -s -X DELETE http://localhost:5301/jumps/jump-002
curl -s http://localhost:5301/jumps/jump-002
```

```json
{"error":"JUMP_NOT_FOUND"}
```

**The same from the command line.** The endpoints only wrap what the Dapr CLI already does. With the demo running, these commands act on the same workflows:

```bash
dapr workflow list -a engineering
dapr workflow suspend jump-001 -a engineering
dapr workflow resume jump-001 -a engineering
dapr workflow terminate jump-001 -a engineering
dapr workflow purge jump-001 -a engineering
```

The [Dapr Dev Dashboard](https://docs.diagrid.io/develop/local-development/dev-dashboard/), a local dev tool, lists the same `LongRangeJumpWorkflow` runs and their status.

**Clean up.** Terminate `jump-001`, then purge it (the same as the CLI commands above, or the two endpoints):

```bash
curl -s -X POST http://localhost:5301/jumps/jump-001/terminate
curl -s -X DELETE http://localhost:5301/jumps/jump-001
```

Terminate is asynchronous. If the purge answers `500`, check that `jump-001` is `TERMINATED` and try again.

## Smoke tests

`tests/workflow` holds one script per demo. They start the demo, drive it with `curl`, check the logs and the workflow output, and stop it again. Each test uses fresh jump IDs and terminates and purges its jumps before it stops the demo, so Redis is left clean.

```bash
bash tests/workflow/run-all.sh                     # every demo in every language, Java is slow
bash tests/workflow/run-all.sh --demo 1 --lang python
```

The Demo 1 test stops the demo after stage 2, starts it again and checks that the jump completes without repeating stage 1 or the replay-safe log line.

The Demo 2 test checks that the four log lines come in chain order, that the output has the expected shape, that a missing, `null` or empty destination plots to Vesper Reach, and what happens when a jump ID is reused while the jump is running and after it has finished.

The Demo 3 test checks that all five sensor arrays log their hazard score, that the output is `{"routeRisk":31,"verdict":"CLEAR"}`, and that the time from `POST` to `COMPLETED` is under 6 seconds, which five scans in a row (10 seconds or more) couldn't meet.

The Demo 4 test stops the demo during the timer wait after check 2, starts it again and checks that the monitor completes, that checks 1 to 5 are each logged exactly once across the restart, that the status is `RUNNING` the whole time and that the output is `{"stable":true,"checks":5,"coreTempK":1000}`.

The Demo 5 test starts three jumps. It approves one, denies one and leaves one unanswered, and checks the three outputs (`JUMPED`, `DENIED`, `ABORTED_NO_AUTHORIZATION`), that the denied jump doesn't engage and that each jump logs the awaiting line exactly once. It also checks that authorizing an unknown jump answers 404 and that authorizing the timed-out jump answers 409 and leaves its output unchanged. The timeout path makes the test take about a minute per language.

The Demo 6 test pauses a jump, checks that it is `SUSPENDED` and logs no legs for 12 seconds, resumes it and checks that the next leg follows. It purges the running jump and expects `500` with the jump still `RUNNING`. It terminates a second jump, checks that no legs follow and that pause answers `409` while `GET` still answers, purges it (`204`, then `404`), and checks that pause, resume, terminate and purge on an unknown jump answer `404`.
