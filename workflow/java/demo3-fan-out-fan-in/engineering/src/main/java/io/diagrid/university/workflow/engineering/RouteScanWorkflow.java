package io.diagrid.university.workflow.engineering;

import io.dapr.durabletask.Task;
import io.dapr.workflows.Workflow;
import io.dapr.workflows.WorkflowStub;
import java.util.List;

// Fan-out/fan-in: schedule all the activities first, without calling await() on each one, so
// they run at the same time. Then wait for all of them with allOf (the fan-in).
// Because Dapr runs the stub again from the top (a replay), the code must be deterministic: no
// clock, random numbers, I/O or Thread.sleep here. Those belong in activities.
public class RouteScanWorkflow implements Workflow {

    record Jump(String jumpId) {
    }

    record SectorScan(String array, int hazard) {
    }

    record RouteScanResult(int routeRisk, String verdict) {
    }

    @Override
    public WorkflowStub create() {
        return ctx -> {
            // Fan-out: callActivity returns a task straight away, nothing has finished yet.
            List<Task<SectorScan>> scans = List.of("alpha", "beta", "gamma", "delta", "epsilon").stream()
                    .map(array -> ctx.callActivity("ScanSectorActivity", array, SectorScan.class))
                    .toList();

            // Fan-in: continue when every scan has finished. The results keep the order of the list.
            List<SectorScan> results = ctx.allOf(scans).await();

            int routeRisk = results.stream().mapToInt(SectorScan::hazard).max().orElse(0);
            ctx.complete(new RouteScanResult(routeRisk, routeRisk < 50 ? "CLEAR" : "HAZARDOUS"));
        };
    }
}
