package io.diagrid.university.workflow.engineering;

import io.dapr.workflows.WorkflowActivity;
import io.dapr.workflows.WorkflowActivityContext;
import java.util.concurrent.TimeUnit;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class AlignNavArrayActivity implements WorkflowActivity {

    private static final Logger log = LoggerFactory.getLogger(AlignNavArrayActivity.class);

    @Override
    public Object run(WorkflowActivityContext ctx) {
        Integer input = ctx.getInput(Integer.class);
        try {
            TimeUnit.SECONDS.sleep(1);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
        log.info("engineering nav array aligned");
        return new JumpWorkflow.NavArray(true);
    }
}
