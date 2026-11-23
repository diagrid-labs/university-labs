package io.diagrid.university.workflow.engineering;

import io.dapr.workflows.WorkflowActivity;
import io.dapr.workflows.WorkflowActivityContext;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class ScanSectorActivity implements WorkflowActivity {

    private static final Logger log = LoggerFactory.getLogger(ScanSectorActivity.class);

    // Fixed scores, so every run and every language logs the same lines.
    private static final Map<String, Integer> HAZARDS =
            Map.of("alpha", 12, "beta", 7, "gamma", 31, "delta", 4, "epsilon", 18);

    @Override
    public Object run(WorkflowActivityContext ctx) {
        String array = ctx.getInput(String.class);
        try {
            TimeUnit.SECONDS.sleep(2);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
        int hazard = HAZARDS.get(array);
        log.info("engineering sensor array {} scanned hazard={}", array, hazard);
        return new RouteScanWorkflow.SectorScan(array, hazard);
    }
}
