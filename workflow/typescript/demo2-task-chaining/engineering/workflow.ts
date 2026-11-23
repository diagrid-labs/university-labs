import type { WorkflowActivityContext, WorkflowContext } from "@dapr/dapr";
import { setTimeout as sleep } from "node:timers/promises";

export interface Jump {
  jumpId: string;
  destination: string;
}

interface Course {
  destination: string;
  heading: number;
  distanceLy: number;
}

interface Engage {
  course: Course;
  warpFactor: number;
}

interface JumpResult {
  arrivedAt: string;
  stardate: number;
}

// Task chaining: run the activities one after the other, and pass each activity's result on as
// the next activity's input. Every yield is a checkpoint, so after a crash the chain carries on
// with the first activity that has not finished.
// Because Dapr replays this generator from the top, it must be deterministic: no Date.now(),
// Math.random(), I/O or timers here. Those belong in activities.
// Activities are called by their registered name: passing the function would use its JS name.
export async function* jumpWorkflow(ctx: WorkflowContext, jump: Jump) {
  const course: Course = yield ctx.callActivity("PlotCourseActivity", jump.destination);
  const warpCore: { warpFactor: number } = yield ctx.callActivity("ChargeWarpCoreActivity", course);
  yield ctx.callActivity("AlignNavArrayActivity", warpCore.warpFactor);
  const engage: Engage = { course, warpFactor: warpCore.warpFactor };
  // The result of the last activity is the workflow's output.
  const arrival: JumpResult = yield ctx.callActivity("EngageJumpActivity", engage);
  return arrival;
}

export async function plotCourseActivity(_ctx: WorkflowActivityContext, destination: string): Promise<Course> {
  await sleep(1000);
  const course = { destination, heading: 217, distanceLy: 4.2 };
  console.log(
    `engineering course plotted to ${destination} heading=${course.heading} distanceLy=${course.distanceLy.toFixed(1)}`,
  );
  return course;
}

export async function chargeWarpCoreActivity(_ctx: WorkflowActivityContext, _course: Course) {
  await sleep(1000);
  const warpFactor = 6;
  console.log(`engineering warp core charged to warp ${warpFactor}`);
  return { warpFactor };
}

export async function alignNavArrayActivity(_ctx: WorkflowActivityContext, _warpFactor: number) {
  await sleep(1000);
  console.log("engineering nav array aligned");
  return { aligned: true };
}

export async function engageJumpActivity(_ctx: WorkflowActivityContext, engage: Engage) {
  await sleep(1000);
  // Stardate: 78000.0 at 2026-01-01T00:00:00Z, one unit per hour after that. It reads the
  // clock, which is fine in an activity but never in the workflow.
  const stardate = Math.round((78000.0 + (Math.floor(Date.now() / 1000) - 1767225600) / 3600.0) * 10) / 10;
  console.log(`engineering jump complete, arrived at ${engage.course.destination}`);
  return { arrivedAt: engage.course.destination, stardate };
}
