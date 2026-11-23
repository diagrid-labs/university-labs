using Dapr.Workflow;

// Management: a jump long enough to pause, resume, terminate and purge by hand. It has 10 legs.
// Each leg is an activity followed by a 5-second durable timer.
// Because Dapr replays RunAsync from the top, it must be deterministic: no DateTime.Now,
// Random, I/O or Task.Delay here. Those belong in activities.
class LongRangeJumpWorkflow : Workflow<Jump, JumpOutcome>
{
    public const int Legs = 10;

    public override async Task<JumpOutcome> RunAsync(WorkflowContext context, Jump jump)
    {
        for (var leg = 1; leg <= Legs; leg++)
        {
            await context.CallActivityAsync(nameof(EngageLegActivity), new Leg(jump.JumpId, leg, Legs));

            // A durable timer is stored by Dapr, not held in memory. While the workflow is paused,
            // the timer still fires, but the workflow only continues after it is resumed.
            await context.CreateTimer(TimeSpan.FromSeconds(5));
        }
        return new JumpOutcome("JUMPED", jump.Destination);
    }
}

// The workflow's input and output, and the input of EngageLegActivity. The property order is the
// JSON key order.
record Jump(string JumpId, string Destination);

record JumpOutcome(string Status, string ArrivedAt);

record Leg(string JumpId, int Number, int Total);
