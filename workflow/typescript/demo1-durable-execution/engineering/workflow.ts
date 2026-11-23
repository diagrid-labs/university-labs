import type { WorkflowActivityContext, WorkflowContext } from "@dapr/dapr";
import { setTimeout as sleep } from "node:timers/promises";

const STAGES = 5;

export interface Jump {
  jumpId: string;
}

interface ChargeStage {
  jumpId: string;
  stage: number;
}

// A workflow is code that Dapr makes durable. After every completed activity the sidecar saves
// the workflow's history in the state store. After a crash Dapr runs this generator again from
// the top (a replay) and feeds it the saved results, so finished stages are not repeated.
// Because of that replay the function must be deterministic: no Date.now(), Math.random(), I/O
// or timers here. Those belong in activities.
export async function* chargeWarpCoreWorkflow(ctx: WorkflowContext, jump: Jump) {
  // During a replay this line runs again, so only log when the code is not replaying.
  if (!ctx.isReplaying()) {
    console.log(`engineering ${jump.jumpId} charge sequence started`);
  }

  for (let stage = 1; stage <= STAGES; stage++) {
    const charge: ChargeStage = { jumpId: jump.jumpId, stage };
    // Each yield is a checkpoint: the activity's result is stored in the workflow history.
    // On a replay a stage that already finished returns its stored result straight away.
    // Call the activity by its registered name: passing the function would use its JS name.
    yield ctx.callActivity("ChargeStageActivity", charge);
  }

  return { jumpId: jump.jumpId, coreCharged: true };
}

// An activity does the real work, and may be slow or have side effects. Dapr runs it at least
// once: a stage that was running during a crash runs again from the start.
export async function chargeStageActivity(_ctx: WorkflowActivityContext, charge: ChargeStage): Promise<void> {
  await sleep(3000);
  console.log(`engineering charge stage ${charge.stage}/${STAGES} complete for ${charge.jumpId}`);
}
