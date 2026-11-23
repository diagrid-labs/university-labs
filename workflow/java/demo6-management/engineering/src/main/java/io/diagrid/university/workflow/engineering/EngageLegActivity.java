package io.diagrid.university.workflow.engineering;

import io.dapr.workflows.WorkflowActivity;
import io.dapr.workflows.WorkflowActivityContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class EngageLegActivity implements WorkflowActivity {

    private static final Logger log = LoggerFactory.getLogger(EngageLegActivity.class);

    @Override
    public Object run(WorkflowActivityContext ctx) {
        LongRangeJumpWorkflow.Leg leg = ctx.getInput(LongRangeJumpWorkflow.Leg.class);
        log.info("engineering {} leg {}/{} complete", leg.jumpId(), leg.number(), leg.total());
        return null;
    }
}
