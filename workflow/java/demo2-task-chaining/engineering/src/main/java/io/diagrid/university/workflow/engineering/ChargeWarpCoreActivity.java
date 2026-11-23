package io.diagrid.university.workflow.engineering;

import io.dapr.workflows.WorkflowActivity;
import io.dapr.workflows.WorkflowActivityContext;
import java.util.concurrent.TimeUnit;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class ChargeWarpCoreActivity implements WorkflowActivity {

    private static final Logger log = LoggerFactory.getLogger(ChargeWarpCoreActivity.class);

    @Override
    public Object run(WorkflowActivityContext ctx) {
        JumpWorkflow.Course course = ctx.getInput(JumpWorkflow.Course.class);
        try {
            TimeUnit.SECONDS.sleep(1);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
        JumpWorkflow.WarpCore warpCore = new JumpWorkflow.WarpCore(6);
        log.info("engineering warp core charged to warp {}", warpCore.warpFactor());
        return warpCore;
    }
}
