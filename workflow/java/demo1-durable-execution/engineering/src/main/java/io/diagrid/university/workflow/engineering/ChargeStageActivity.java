package io.diagrid.university.workflow.engineering;

import io.dapr.workflows.WorkflowActivity;
import io.dapr.workflows.WorkflowActivityContext;
import java.util.concurrent.TimeUnit;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

// An activity does the real work, and may be slow or have side effects. Dapr runs it at least
// once: a stage that was running during a crash runs again from the start.
public class ChargeStageActivity implements WorkflowActivity {

    private static final Logger log = LoggerFactory.getLogger(ChargeStageActivity.class);

    record ChargeStage(String jumpId, int stage) {
    }

    @Override
    public Object run(WorkflowActivityContext ctx) {
        ChargeStage charge = ctx.getInput(ChargeStage.class);
        try {
            TimeUnit.SECONDS.sleep(3);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
        log.info("engineering charge stage {}/{} complete for {}",
                charge.stage(), ChargeWarpCoreWorkflow.STAGES, charge.jumpId());
        return null;
    }
}
