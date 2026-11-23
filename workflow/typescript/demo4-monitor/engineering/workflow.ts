import type { WorkflowActivityContext, WorkflowContext } from "@dapr/dapr";

export interface Jump {
  jumpId: string;
  check: number;
}

interface CoreStability {
  stable: boolean;
  checks: number;
  coreTempK: number;
}

// A monitor: check the core temperature, wait, check again, without a loop that stays alive.
// Each run of this generator is one check. Between checks it sleeps on a durable timer and then
// continues as new.
// Because Dapr replays this generator from the top, it must be deterministic: no Date.now(),
// Math.random(), I/O or timers here. Those belong in activities.
// Activities are called by their registered name: passing the function would use its JS name.
export async function* coreStabilityWorkflow(ctx: WorkflowContext, jump: Jump) {
  const check = jump.check;
  const coreTempK: number = yield ctx.callActivity("ReadCoreTempActivity", check);

  if (coreTempK <= 1000) {
    const stable: CoreStability = { stable: true, checks: check, coreTempK };
    return stable;
  }

  // The guard every monitor needs: give up after 10 checks.
  if (check === 10) {
    const unstable: CoreStability = { stable: false, checks: check, coreTempK };
    return unstable;
  }

  // A durable timer is stored by Dapr, not held in memory. Stop the app during the wait and
  // the timer keeps running; the workflow continues when the app is back. The argument is in seconds.
  yield ctx.createTimer(5);

  // Continue-as-new restarts the workflow with new input and an empty history. A loop inside
  // one run would grow the history with every check.
  ctx.continueAsNew({ jumpId: jump.jumpId, check: check + 1 } satisfies Jump);
}

export async function readCoreTempActivity(_ctx: WorkflowActivityContext, check: number): Promise<number> {
  // A fixed sequence, so every run and every language logs the same lines.
  const coreTempK = 1240 - 60 * (check - 1);
  console.log(`engineering core temperature check ${check}: ${coreTempK}K`);
  return coreTempK;
}
