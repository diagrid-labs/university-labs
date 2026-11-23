package io.diagrid.university.workflow.engineering;

import io.dapr.workflows.WorkflowActivity;
import io.dapr.workflows.WorkflowActivityContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class ReadCoreTempActivity implements WorkflowActivity {

    private static final Logger log = LoggerFactory.getLogger(ReadCoreTempActivity.class);

    @Override
    public Object run(WorkflowActivityContext ctx) {
        int check = ctx.getInput(Integer.class);
        // A fixed sequence, so every run and every language logs the same lines.
        int coreTempK = 1240 - 60 * (check - 1);
        log.info("engineering core temperature check {}: {}K", check, coreTempK);
        return coreTempK;
    }
}
