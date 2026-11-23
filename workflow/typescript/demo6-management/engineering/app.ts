import { DaprWorkflowClient, WorkflowRuntime, WorkflowRuntimeStatus } from "@dapr/dapr";
import express, { type NextFunction, type Request, type Response } from "express";
import { randomUUID } from "node:crypto";
import { engageLegActivity, longRangeJumpWorkflow, type Jump } from "./workflow.ts";

// Both fields are optional. A missing, null or empty destination becomes Vesper Reach.
interface JumpRequest {
  jumpId?: string | null;
  destination?: string | null;
}

// The runtime connects to the sidecar and runs the workflow and activity code it is sent. Each
// one is registered under an explicit name, the same in every language of this track.
const workflowRuntime = new WorkflowRuntime()
  .registerWorkflowByName("LongRangeJumpWorkflow", longRangeJumpWorkflow)
  .registerActivityWithName("EngageLegActivity", engageLegActivity);
// The client starts and inspects workflows.
const workflowClient = new DaprWorkflowClient();

const app = express();
app.use(express.json());

app.post("/jumps", async (req: Request, res: Response) => {
  const body: JumpRequest = req.body ?? {};
  const jumpId = body.jumpId || `jump-${randomUUID().slice(0, 8)}`;
  const destination = body.destination || "Vesper Reach";
  const jump: Jump = { jumpId, destination };
  // The jump ID becomes the workflow instance ID. The call returns as soon as the sidecar has
  // scheduled the workflow; the workflow itself runs in the background.
  await workflowClient.scheduleNewWorkflow("LongRangeJumpWorkflow", jump, jumpId);
  res.status(202).json({ jumpId });
});

app.get("/jumps/:jumpId", async (req: Request<{ jumpId: string }>, res: Response) => {
  const { jumpId } = req.params;
  // The sidecar reads the workflow's state from the state store.
  const state = await workflowClient.getWorkflowState(jumpId, true);
  if (!state) {
    res.status(404).json({ error: "JUMP_NOT_FOUND" });
    return;
  }
  // WorkflowRuntimeStatus is a numeric enum; look up its name. In-between statuses show as
  // RUNNING, so the learner only sees five statuses.
  let status = WorkflowRuntimeStatus[state.runtimeStatus];
  if (["PENDING", "CONTINUED_AS_NEW", "STALLED"].includes(status)) {
    status = "RUNNING";
  }
  res.json({ jumpId, status, output: state.getOutput() ?? null });
});

// Pause, resume and terminate read the state first. Dapr 1.19.1 stalls a finished instance that
// receives a control call, so those calls are not made for one. Answers 404 or 409 and returns
// true when the jump is unknown or finished.
async function rejectFinished(jumpId: string, res: Response): Promise<boolean> {
  const state = await workflowClient.getWorkflowState(jumpId, false);
  if (!state) {
    res.status(404).json({ error: "JUMP_NOT_FOUND" });
    return true;
  }
  if (["COMPLETED", "FAILED", "TERMINATED"].includes(WorkflowRuntimeStatus[state.runtimeStatus])) {
    res.status(409).json({ error: "JUMP_FINISHED" });
    return true;
  }
  return false;
}

// Each management endpoint is one call on the workflow client.
app.post("/jumps/:jumpId/pause", async (req: Request<{ jumpId: string }>, res: Response) => {
  const { jumpId } = req.params;
  if (await rejectFinished(jumpId, res)) {
    return;
  }
  await workflowClient.suspendWorkflow(jumpId);
  res.status(202).end();
});

app.post("/jumps/:jumpId/resume", async (req: Request<{ jumpId: string }>, res: Response) => {
  const { jumpId } = req.params;
  if (await rejectFinished(jumpId, res)) {
    return;
  }
  await workflowClient.resumeWorkflow(jumpId);
  res.status(202).end();
});

app.post("/jumps/:jumpId/terminate", async (req: Request<{ jumpId: string }>, res: Response) => {
  const { jumpId } = req.params;
  if (await rejectFinished(jumpId, res)) {
    return;
  }
  await workflowClient.terminateWorkflow(jumpId);
  res.status(202).end();
});

// Purge removes the history of a finished jump. A running jump can't be purged: the call throws
// and the error handler answers 500.
app.delete("/jumps/:jumpId", async (req: Request<{ jumpId: string }>, res: Response) => {
  const { jumpId } = req.params;
  if (!(await workflowClient.getWorkflowState(jumpId, false))) {
    res.status(404).json({ error: "JUMP_NOT_FOUND" });
    return;
  }
  await workflowClient.purgeWorkflow(jumpId);
  res.status(204).end();
});

// One error handler for every route: Express 5 passes errors thrown in async handlers here.
// Errors Express raises itself, such as a malformed JSON body, carry their own status and go to
// Express's default handler. Anything else is a failed workflow call and becomes the agreed 500.
app.use((err: Error & { status?: number }, _req: Request, res: Response, next: NextFunction) => {
  if (err.status) {
    next(err);
    return;
  }
  console.warn(`engineering workflow call failed: ${err.message}`);
  res.status(500).json({ error: "WORKFLOW_ERROR" });
});

// Start the runtime before taking requests, so a jump can run as soon as it is scheduled.
await workflowRuntime.start();
app.listen(5301, "127.0.0.1");
