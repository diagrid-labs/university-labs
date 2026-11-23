package io.diagrid.university.workflow.engineering;

import io.dapr.workflows.Workflow;
import io.dapr.workflows.WorkflowStub;
import java.time.Duration;

// Management: a jump long enough to pause, resume, terminate and purge by hand. It has 10 legs.
// Each leg is an activity followed by a 5-second durable timer.
// Because Dapr runs the stub again from the top (a replay), the code must be deterministic: no
// clock, random numbers, I/O or Thread.sleep here. Those belong in activities.
public class LongRangeJumpWorkflow implements Workflow {

    static final int LEGS = 10;

    record Jump(String jumpId, String destination) {
    }

    record JumpOutcome(String status, String arrivedAt) {
    }

    // The input of EngageLegActivity.
    record Leg(String jumpId, int number, int total) {
    }

    @Override
    public WorkflowStub create() {
        return ctx -> {
            Jump jump = ctx.getInput(Jump.class);
            for (int leg = 1; leg <= LEGS; leg++) {
                ctx.callActivity("EngageLegActivity", new Leg(jump.jumpId(), leg, LEGS)).await();

                // A durable timer is stored by Dapr, not held in memory. While the workflow is
                // paused, the timer still fires, but the workflow only continues after it is resumed.
                ctx.createTimer(Duration.ofSeconds(5)).await();
            }
            ctx.complete(new JumpOutcome("JUMPED", jump.destination()));
        };
    }
}
