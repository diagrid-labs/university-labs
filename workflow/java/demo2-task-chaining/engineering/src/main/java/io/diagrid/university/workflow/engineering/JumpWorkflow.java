package io.diagrid.university.workflow.engineering;

import io.dapr.workflows.Workflow;
import io.dapr.workflows.WorkflowStub;

// Task chaining: run the activities one after the other, and pass each activity's result on as
// the next activity's input. Every await() is a checkpoint, so after a crash the chain carries
// on with the first activity that has not finished.
// Because Dapr runs the stub again from the top (a replay), the code must be deterministic: no
// clock, random numbers, I/O or Thread.sleep here. Those belong in activities.
public class JumpWorkflow implements Workflow {

    record Jump(String jumpId, String destination) {
    }

    record Course(String destination, int heading, double distanceLy) {
    }

    record WarpCore(int warpFactor) {
    }

    record NavArray(boolean aligned) {
    }

    record Engage(Course course, int warpFactor) {
    }

    record JumpResult(String arrivedAt, double stardate) {
    }

    @Override
    public WorkflowStub create() {
        return ctx -> {
            Jump jump = ctx.getInput(Jump.class);
            Course course = ctx.callActivity("PlotCourseActivity", jump.destination(), Course.class).await();
            WarpCore warpCore = ctx.callActivity("ChargeWarpCoreActivity", course, WarpCore.class).await();
            ctx.callActivity("AlignNavArrayActivity", warpCore.warpFactor(), NavArray.class).await();
            // The result of the last activity is the workflow's output.
            ctx.complete(ctx.callActivity("EngageJumpActivity",
                    new Engage(course, warpCore.warpFactor()), JumpResult.class).await());
        };
    }
}
