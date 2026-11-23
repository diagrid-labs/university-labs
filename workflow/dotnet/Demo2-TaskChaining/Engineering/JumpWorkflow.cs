using Dapr.Workflow;

// Task chaining: run the activities one after the other, and pass each activity's result on as
// the next activity's input. Every await is a checkpoint, so after a crash the chain carries on
// with the first activity that has not finished.
// Because Dapr replays RunAsync from the top, it must be deterministic: no DateTime.Now,
// Random, I/O or Task.Delay here. Those belong in activities.
class JumpWorkflow : Workflow<Jump, JumpResult>
{
    public override async Task<JumpResult> RunAsync(WorkflowContext context, Jump jump)
    {
        var course = await context.CallActivityAsync<Course>(nameof(PlotCourseActivity), jump.Destination);
        var warpCore = await context.CallActivityAsync<WarpCore>(nameof(ChargeWarpCoreActivity), course);
        await context.CallActivityAsync<NavArray>(nameof(AlignNavArrayActivity), warpCore.WarpFactor);
        // The result of the last activity is the workflow's output.
        return await context.CallActivityAsync<JumpResult>(nameof(EngageJumpActivity),
            new Engage(course, warpCore.WarpFactor));
    }
}

// The workflow's input, and each activity's input and output. The property order is the JSON key order.
record Jump(string JumpId, string Destination);

record Course(string Destination, int Heading, double DistanceLy);

record WarpCore(int WarpFactor);

record NavArray(bool Aligned);

record Engage(Course Course, int WarpFactor);

record JumpResult(string ArrivedAt, double Stardate);
