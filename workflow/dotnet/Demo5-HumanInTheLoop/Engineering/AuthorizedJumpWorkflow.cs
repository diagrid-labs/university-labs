using System.Text.Json.Serialization;
using Dapr.Workflow;

// Human in the loop: plot the course, then wait for the captain. While it waits, the workflow
// costs nothing: no thread, no timer in memory. The app can even be restarted.
// Because Dapr replays RunAsync from the top, it must be deterministic: no DateTime.Now,
// Random, I/O or Task.Delay here. Those belong in activities.
class AuthorizedJumpWorkflow : Workflow<Jump, JumpOutcome>
{
    public override async Task<JumpOutcome> RunAsync(WorkflowContext context, Jump jump)
    {
        var course = await context.CallActivityAsync<Course>(nameof(PlotCourseActivity), jump.Destination);

        // The context logger skips the replays, so this line appears once per jump.
        var logger = context.CreateReplaySafeLogger<AuthorizedJumpWorkflow>();
        logger.LogInformation("engineering {JumpId} awaiting captain's authorization", jump.JumpId);

        // Wait for the external event "jump-authorized", raised by POST /jumps/{jumpId}/authorize.
        // With a timeout, the wait throws a TaskCanceledException when nobody answers in time.
        Authorization authorization;
        try
        {
            authorization = await context.WaitForExternalEventAsync<Authorization>("jump-authorized", TimeSpan.FromSeconds(60));
        }
        catch (TaskCanceledException)
        {
            logger.LogInformation("engineering {JumpId} jump aborted, no authorization", jump.JumpId);
            return new JumpOutcome("ABORTED_NO_AUTHORIZATION", null);
        }

        if (!authorization.Approved)
        {
            logger.LogInformation("engineering {JumpId} jump denied by {Officer}", jump.JumpId, authorization.Officer);
            return new JumpOutcome("DENIED", authorization.Officer);
        }

        // Engage with a fixed warp factor: this demo has no warp core charging step.
        await context.CallActivityAsync<JumpResult>(nameof(EngageJumpActivity), new Engage(course, 6));
        return new JumpOutcome("JUMPED", authorization.Officer);
    }
}

// The workflow's input, the event's payload and the workflow's output. The property order is the
// JSON key order. A null AuthorizedBy is left out of the output.
record Jump(string JumpId, string Destination);

record Authorization(bool Approved, string? Officer);

record JumpOutcome(string Status, [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? AuthorizedBy);

// The input and output of PlotCourseActivity and EngageJumpActivity.
record Course(string Destination, int Heading, double DistanceLy);

record Engage(Course Course, int WarpFactor);

record JumpResult(string ArrivedAt, double Stardate);
