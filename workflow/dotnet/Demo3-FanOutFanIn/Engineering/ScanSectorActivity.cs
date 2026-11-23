using Dapr.Workflow;

class ScanSectorActivity(ILogger<ScanSectorActivity> logger) : WorkflowActivity<string, SectorScan>
{
    // Fixed scores, so every run and every language logs the same lines.
    static readonly Dictionary<string, int> Hazards = new()
    {
        ["alpha"] = 12, ["beta"] = 7, ["gamma"] = 31, ["delta"] = 4, ["epsilon"] = 18,
    };

    public override async Task<SectorScan> RunAsync(WorkflowActivityContext context, string array)
    {
        await Task.Delay(TimeSpan.FromSeconds(2));
        var hazard = Hazards[array];
        logger.LogInformation("engineering sensor array {Array} scanned hazard={Hazard}", array, hazard);
        return new SectorScan(array, hazard);
    }
}
