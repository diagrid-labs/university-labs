using Dapr.Workflow;

class EngageLegActivity(ILogger<EngageLegActivity> logger) : WorkflowActivity<Leg, object?>
{
    public override Task<object?> RunAsync(WorkflowActivityContext context, Leg leg)
    {
        logger.LogInformation("engineering {JumpId} leg {Number}/{Total} complete", leg.JumpId, leg.Number, leg.Total);
        return Task.FromResult<object?>(null);
    }
}
