package io.diagrid.university.workflow.engineering;

import io.dapr.workflows.WorkflowActivity;
import io.dapr.workflows.WorkflowActivityContext;
import java.time.Instant;
import java.util.concurrent.TimeUnit;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class EngageJumpActivity implements WorkflowActivity {

    private static final Logger log = LoggerFactory.getLogger(EngageJumpActivity.class);

    @Override
    public Object run(WorkflowActivityContext ctx) {
        JumpWorkflow.Engage input = ctx.getInput(JumpWorkflow.Engage.class);
        try {
            TimeUnit.SECONDS.sleep(1);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
        // Stardate: 78000.0 at 2026-01-01T00:00:00Z, one unit per hour after that. It reads the
        // clock, which is fine in an activity but never in the workflow.
        double stardate = Math.round((78000.0 + (Instant.now().getEpochSecond() - 1767225600L) / 3600.0) * 10.0) / 10.0;
        log.info("engineering jump complete, arrived at {}", input.course().destination());
        return new JumpWorkflow.JumpResult(input.course().destination(), stardate);
    }
}
