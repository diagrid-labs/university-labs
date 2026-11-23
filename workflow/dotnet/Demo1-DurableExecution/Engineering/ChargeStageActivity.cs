using Dapr.Workflow;

// An activity does the real work, and may be slow or have side effects. Dapr runs it at least
// once: a stage that was running during a crash runs again from the start.
class ChargeStageActivity(ILogger<ChargeStageActivity> logger) : WorkflowActivity<ChargeStage, object?>
{
    public override async Task<object?> RunAsync(WorkflowActivityContext context, ChargeStage charge)
    {
        await Task.Delay(TimeSpan.FromSeconds(3));
        logger.LogInformation("engineering charge stage {Stage}/{Stages} complete for {JumpId}",
            charge.Stage, ChargeWarpCoreWorkflow.Stages, charge.JumpId);
        return null;
    }
}

record ChargeStage(string JumpId, int Stage);
