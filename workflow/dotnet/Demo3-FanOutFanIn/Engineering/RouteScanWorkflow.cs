using Dapr.Workflow;

// Fan-out/fan-in: schedule all the activities first, without awaiting them one by one, so they
// run at the same time. Then wait for all of them with Task.WhenAll (the fan-in).
// Because Dapr replays RunAsync from the top, it must be deterministic: no DateTime.Now,
// Random, I/O or Task.Delay here. Those belong in activities.
class RouteScanWorkflow : Workflow<Jump, RouteScanResult>
{
    static readonly string[] Arrays = ["alpha", "beta", "gamma", "delta", "epsilon"];

    public override async Task<RouteScanResult> RunAsync(WorkflowContext context, Jump jump)
    {
        // Fan-out: CallActivityAsync returns a task straight away. ToArray() starts all five.
        var scans = Arrays
            .Select(array => context.CallActivityAsync<SectorScan>(nameof(ScanSectorActivity), array))
            .ToArray();

        // Fan-in: continue when every scan has finished.
        var results = await Task.WhenAll(scans);

        var routeRisk = results.Max(scan => scan.Hazard);
        return new RouteScanResult(routeRisk, routeRisk < 50 ? "CLEAR" : "HAZARDOUS");
    }
}

// The workflow's input, the activity's output and the workflow's output. The property order is
// the JSON key order.
record Jump(string JumpId);

record SectorScan(string Array, int Hazard);

record RouteScanResult(int RouteRisk, string Verdict);
