using Dapr.Workflow;

// A monitor: check the core temperature, wait, check again, without a loop that stays alive.
// Each run of RunAsync is one check. Between checks it sleeps on a durable timer and then
// continues as new.
// Because Dapr replays RunAsync from the top, it must be deterministic: no DateTime.Now,
// Random, I/O or Task.Delay here. Those belong in activities.
class CoreStabilityWorkflow : Workflow<Jump, CoreStability?>
{
    public override async Task<CoreStability?> RunAsync(WorkflowContext context, Jump jump)
    {
        var coreTempK = await context.CallActivityAsync<int>(nameof(ReadCoreTempActivity), jump.Check);

        if (coreTempK <= 1000)
        {
            return new CoreStability(true, jump.Check, coreTempK);
        }

        // The guard every monitor needs: give up after 10 checks.
        if (jump.Check == 10)
        {
            return new CoreStability(false, jump.Check, coreTempK);
        }

        // A durable timer is stored by Dapr, not held in memory. Stop the app during the wait and
        // the timer keeps running; the workflow continues when the app is back.
        await context.CreateTimer(TimeSpan.FromSeconds(5));

        // Continue-as-new restarts the workflow with new input and an empty history. A loop inside
        // one run would grow the history with every check.
        context.ContinueAsNew(new Jump(jump.JumpId, jump.Check + 1));
        return null;
    }
}

// The workflow's input and output. The property order is the JSON key order.
record Jump(string JumpId, int Check);

record CoreStability(bool Stable, int Checks, int CoreTempK);
