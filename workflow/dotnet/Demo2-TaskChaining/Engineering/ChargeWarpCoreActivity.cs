using Dapr.Workflow;

class ChargeWarpCoreActivity(ILogger<ChargeWarpCoreActivity> logger) : WorkflowActivity<Course, WarpCore>
{
    public override async Task<WarpCore> RunAsync(WorkflowActivityContext context, Course course)
    {
        await Task.Delay(TimeSpan.FromSeconds(1));
        var warpCore = new WarpCore(6);
        logger.LogInformation("engineering warp core charged to warp {WarpFactor}", warpCore.WarpFactor);
        return warpCore;
    }
}
