using Dapr.Workflow;

class EngageJumpActivity(ILogger<EngageJumpActivity> logger) : WorkflowActivity<Engage, JumpResult>
{
    public override async Task<JumpResult> RunAsync(WorkflowActivityContext context, Engage engage)
    {
        await Task.Delay(TimeSpan.FromSeconds(1));
        // Stardate: 78000.0 at 2026-01-01T00:00:00Z, one unit per hour after that. It reads the
        // clock, which is fine in an activity but never in the workflow.
        var unixSeconds = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var stardate = Math.Round(78000.0 + (unixSeconds - 1767225600) / 3600.0, 1);
        logger.LogInformation("engineering jump complete, arrived at {Destination}", engage.Course.Destination);
        return new JumpResult(engage.Course.Destination, stardate);
    }
}
