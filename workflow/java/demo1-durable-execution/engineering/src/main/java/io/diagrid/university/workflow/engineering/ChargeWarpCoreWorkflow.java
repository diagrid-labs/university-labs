package io.diagrid.university.workflow.engineering;

import io.dapr.workflows.Workflow;
import io.dapr.workflows.WorkflowStub;

// A workflow is code that Dapr makes durable. After every completed activity the sidecar saves
// the workflow's history in the state store. After a crash Dapr runs the stub again from the top
// (a replay) and feeds it the saved results, so finished stages are not repeated.
// Because of that replay the code must be deterministic: no clock, random numbers, I/O or
// Thread.sleep here. Those belong in activities.
public class ChargeWarpCoreWorkflow implements Workflow {

    static final int STAGES = 5;

    record Jump(String jumpId) {
    }

    record ChargeResult(String jumpId, boolean coreCharged) {
    }

    @Override
    public WorkflowStub create() {
        return ctx -> {
            Jump jump = ctx.getInput(Jump.class);
            // ctx.getLogger() is replay-safe: it skips its lines while the workflow replays.
            ctx.getLogger().info("engineering {} charge sequence started", jump.jumpId());

            for (int stage = 1; stage <= STAGES; stage++) {
                // Each await() is a checkpoint: the activity's result is stored in the workflow
                // history. On a replay a stage that already finished returns its stored result
                // straight away.
                ctx.callActivity("ChargeStageActivity", new ChargeStageActivity.ChargeStage(jump.jumpId(), stage))
                        .await();
            }

            ctx.complete(new ChargeResult(jump.jumpId(), true));
        };
    }
}
