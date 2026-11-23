import type { WorkflowActivityContext, WorkflowContext } from "@dapr/dapr";
import { setTimeout } from "node:timers/promises";

export interface Jump {
  jumpId: string;
  destination: string;
}

// The payload of the "jump-authorized" event.
export interface Authorization {
  approved: boolean;
  officer: string;
}

// The input and output of PlotCourseActivity and EngageJumpActivity.
interface Course {
  destination: string;
  heading: number;
  distanceLy: number;
}

interface Engage {
  course: Course;
  warpFactor: number;
}

// Human in the loop: plot the course, then wait for the captain. While it waits, the workflow
// costs nothing: no thread, no timer in memory. The app can even be restarted.
// Because Dapr replays this generator from the top, it must be deterministic: no Date.now(),
// Math.random(), I/O or timers here. Those belong in activities.
// Activities are called by their registered name: passing the function would use its JS name.
export async function* authorizedJumpWorkflow(ctx: WorkflowContext, jump: Jump) {
  const course: Course = yield ctx.callActivity("PlotCourseActivity", jump.destination);

  // During a replay this line runs again, so only log when the code is not replaying.
  if (!ctx.isReplaying()) {
    console.log(`engineering ${jump.jumpId} awaiting captain's authorization`);
  }

  // Wait for the external event "jump-authorized", raised by POST /jumps/{jumpId}/authorize.
  // With a timeout, the wait rejects when nobody answers in time.
  let authorization: Authorization;
  try {
    authorization = yield ctx.waitForExternalEvent("jump-authorized", { timeoutInSeconds: 60 });
  } catch {
    if (!ctx.isReplaying()) {
      console.log(`engineering ${jump.jumpId} jump aborted, no authorization`);
    }
    return { status: "ABORTED_NO_AUTHORIZATION" };
  }

  if (!authorization.approved) {
    if (!ctx.isReplaying()) {
      console.log(`engineering ${jump.jumpId} jump denied by ${authorization.officer}`);
    }
    return { status: "DENIED", authorizedBy: authorization.officer };
  }

  // Engage with a fixed warp factor: this demo has no warp core charging step.
  const engage: Engage = { course, warpFactor: 6 };
  yield ctx.callActivity("EngageJumpActivity", engage);
  return { status: "JUMPED", authorizedBy: authorization.officer };
}

export async function plotCourseActivity(_ctx: WorkflowActivityContext, destination: string): Promise<Course> {
  await setTimeout(1000);
  const course = { destination, heading: 217, distanceLy: 4.2 };
  console.log(
    `engineering course plotted to ${destination} heading=${course.heading} distanceLy=${course.distanceLy.toFixed(1)}`,
  );
  return course;
}

export async function engageJumpActivity(_ctx: WorkflowActivityContext, engage: Engage) {
  await setTimeout(1000);
  // Stardate: 78000.0 at 2026-01-01T00:00:00Z, one unit per hour after that. It reads the
  // clock, which is fine in an activity but never in the workflow.
  const stardate = Math.round((78000.0 + (Math.floor(Date.now() / 1000) - 1767225600) / 3600.0) * 10) / 10;
  console.log(`engineering jump complete, arrived at ${engage.course.destination}`);
  return { arrivedAt: engage.course.destination, stardate };
}
