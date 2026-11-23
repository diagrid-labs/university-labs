using Dapr.Workflow;

class ReadCoreTempActivity(ILogger<ReadCoreTempActivity> logger) : WorkflowActivity<int, int>
{
    public override Task<int> RunAsync(WorkflowActivityContext context, int check)
    {
        // A fixed sequence, so every run and every language logs the same lines.
        var coreTempK = 1240 - 60 * (check - 1);
        logger.LogInformation("engineering core temperature check {Check}: {CoreTempK}K", check, coreTempK);
        return Task.FromResult(coreTempK);
    }
}
