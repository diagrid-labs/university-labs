import type { WorkflowActivityContext, WorkflowContext } from "@dapr/dapr";

export interface Jump {
  jumpId: string;
  destination: string;
}

// The input of EngageLegActivity.
interface Leg {
  jumpId: string;
  number: number;
  total: number;
}

const LEGS = 10;

// Management: a jump long enough to pause, resume, terminate and purge by hand. It has 10 legs.
// Each leg is an activity followed by a 5-second durable timer.
// Because Dapr replays this generator from the top, it must be deterministic: no Date.now(),
// Math.random(), I/O or timers here. Those belong in activities.
// Activities are called by their registered name: passing the function would use its JS name.
export async function* longRangeJumpWorkflow(ctx: WorkflowContext, jump: Jump) {
  for (let number = 1; number <= LEGS; number++) {
    const leg: Leg = { jumpId: jump.jumpId, number, total: LEGS };
    yield ctx.callActivity("EngageLegActivity", leg);

    // A durable timer is stored by Dapr, not held in memory. While the workflow is paused, the
    // timer still fires, but the workflow only continues after it is resumed. The argument is in
    // seconds.
    yield ctx.createTimer(5);
  }
  return { status: "JUMPED", arrivedAt: jump.destination };
}

export async function engageLegActivity(_ctx: WorkflowActivityContext, leg: Leg) {
  console.log(`engineering ${leg.jumpId} leg ${leg.number}/${leg.total} complete`);
}
