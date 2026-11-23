using Dapr.Workflow;

class AlignNavArrayActivity(ILogger<AlignNavArrayActivity> logger) : WorkflowActivity<int, NavArray>
{
    public override async Task<NavArray> RunAsync(WorkflowActivityContext context, int warpFactor)
    {
        await Task.Delay(TimeSpan.FromSeconds(1));
        logger.LogInformation("engineering nav array aligned");
        return new NavArray(true);
    }
}
