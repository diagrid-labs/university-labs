import type { WorkflowActivityContext, WorkflowContext } from "@dapr/dapr";
import { setTimeout } from "node:timers/promises";

export interface Jump {
  jumpId: string;
}

interface SectorScan {
  array: string;
  hazard: number;
}

interface RouteScanResult {
  routeRisk: number;
  verdict: "CLEAR" | "HAZARDOUS";
}

// Fan-out/fan-in: schedule all the activities first, without yielding each one, so they run at
// the same time. Then wait for all of them with ctx.whenAll (the fan-in).
// Because Dapr replays this generator from the top, it must be deterministic: no Date.now(),
// Math.random(), I/O or timers here. Those belong in activities.
// Activities are called by their registered name: passing the function would use its JS name.
export async function* routeScanWorkflow(ctx: WorkflowContext, _jump: Jump) {
  // Fan-out: callActivity returns a task straight away, nothing has finished yet.
  const scans = ["alpha", "beta", "gamma", "delta", "epsilon"].map((array) =>
    ctx.callActivity("ScanSectorActivity", array),
  );

  // Fan-in: continue when every scan has finished. The results keep the order of the list.
  const results: SectorScan[] = yield ctx.whenAll(scans);

  const routeRisk = Math.max(...results.map((scan) => scan.hazard));
  const result: RouteScanResult = { routeRisk, verdict: routeRisk < 50 ? "CLEAR" : "HAZARDOUS" };
  return result;
}

export async function scanSectorActivity(_ctx: WorkflowActivityContext, array: string): Promise<SectorScan> {
  await setTimeout(2000);
  // Fixed scores, so every run and every language logs the same lines.
  const hazards: Record<string, number> = { alpha: 12, beta: 7, gamma: 31, delta: 4, epsilon: 18 };
  const hazard = hazards[array];
  console.log(`engineering sensor array ${array} scanned hazard=${hazard}`);
  return { array, hazard };
}
