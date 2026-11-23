using Dapr.Workflow;

class ScanSectorActivity(ILogger<ScanSectorActivity> logger) : WorkflowActivity<string, SectorScan>
{
    public override async Task<SectorScan> RunAsync(WorkflowActivityContext context, string array)
    {
        await Task.Delay(TimeSpan.FromSeconds(2));
        // Fixed scores, so every run and every language logs the same lines.
        var hazard = array switch
        {
            "alpha" => 12,
            "beta" => 7,
            "gamma" => 31,
            "delta" => 4,
            _ => 18,
        };
        logger.LogInformation("engineering sensor array {Array} scanned hazard={Hazard}", array, hazard);
        return new SectorScan(array, hazard);
    }
}
