package io.diagrid.university.workflow.engineering;

import com.fasterxml.jackson.annotation.JsonInclude;
import io.dapr.durabletask.TaskCanceledException;
import io.dapr.workflows.Workflow;
import io.dapr.workflows.WorkflowStub;
import java.time.Duration;

// Human in the loop: plot the course, then wait for the captain. While it waits, the workflow
// costs nothing: no thread, no timer in memory. The app can even be restarted.
// Because Dapr runs the stub again from the top (a replay), the code must be deterministic: no
// clock, random numbers, I/O or Thread.sleep here. Those belong in activities.
public class AuthorizedJumpWorkflow implements Workflow {

    record Jump(String jumpId, String destination) {
    }

    record Authorization(boolean approved, String officer) {
    }

    // A null authorizedBy is left out of the output.
    @JsonInclude(JsonInclude.Include.NON_NULL)
    record JumpOutcome(String status, String authorizedBy) {
    }

    // The input and output of PlotCourseActivity and EngageJumpActivity.
    record Course(String destination, int heading, double distanceLy) {
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

            // ctx.getLogger() is replay-safe: it skips its lines while the workflow replays.
            ctx.getLogger().info("engineering {} awaiting captain's authorization", jump.jumpId());

            // Wait for the external event "jump-authorized", raised by POST /jumps/{jumpId}/authorize.
            // With a timeout, the wait throws a TaskCanceledException when nobody answers in time.
            Authorization authorization;
            try {
                authorization = ctx.waitForExternalEvent("jump-authorized", Duration.ofSeconds(60), Authorization.class)
                        .await();
            } catch (TaskCanceledException e) {
                ctx.getLogger().info("engineering {} jump aborted, no authorization", jump.jumpId());
                ctx.complete(new JumpOutcome("ABORTED_NO_AUTHORIZATION", null));
                return;
            }

            if (!authorization.approved()) {
                ctx.getLogger().info("engineering {} jump denied by {}", jump.jumpId(), authorization.officer());
                ctx.complete(new JumpOutcome("DENIED", authorization.officer()));
                return;
            }

            // Engage with a fixed warp factor: this demo has no warp core charging step.
            ctx.callActivity("EngageJumpActivity", new Engage(course, 6), JumpResult.class).await();
            ctx.complete(new JumpOutcome("JUMPED", authorization.officer()));
        };
    }
}
