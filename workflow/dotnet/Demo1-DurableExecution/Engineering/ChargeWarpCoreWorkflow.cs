using Dapr.Workflow;

// A workflow is code that Dapr makes durable. After every completed activity the sidecar saves
// the workflow's history in the state store. After a crash Dapr runs RunAsync again from the
// top (a replay) and feeds it the saved results, so finished stages are not repeated.
// Because of that replay the method must be deterministic: no DateTime.Now, Random, I/O or
// Task.Delay here. Those belong in activities.
class ChargeWarpCoreWorkflow : Workflow<Jump, ChargeResult>
{
    public const int Stages = 5;

    public override async Task<ChargeResult> RunAsync(WorkflowContext context, Jump jump)
    {
        // During a replay this method runs again. A replay-safe logger skips its lines then.
        var logger = context.CreateReplaySafeLogger<ChargeWarpCoreWorkflow>();
        logger.LogInformation("engineering {JumpId} charge sequence started", jump.JumpId);

        for (var stage = 1; stage <= Stages; stage++)
        {
            // Each await is a checkpoint: the activity's result is stored in the workflow history.
            // On a replay a stage that already finished returns its stored result straight away.
            await context.CallActivityAsync(nameof(ChargeStageActivity), new ChargeStage(jump.JumpId, stage));
        }

        return new ChargeResult(jump.JumpId, CoreCharged: true);
    }
}

// The workflow's input and output. The property order is the JSON key order.
record Jump(string JumpId);

record ChargeResult(string JumpId, bool CoreCharged);
