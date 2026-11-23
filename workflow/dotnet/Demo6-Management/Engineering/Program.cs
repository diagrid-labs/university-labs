using System.Text.Json;
using Dapr.Workflow;

var builder = WebApplication.CreateBuilder(args);
// Adds the workflow runtime, which connects to the sidecar and runs the workflow and activity
// code it is sent, and a DaprWorkflowClient that starts and inspects workflows. The SDK finds
// every Workflow and WorkflowActivity class in the project and registers it under its class
// name (LongRangeJumpWorkflow, EngageLegActivity), so there is no list to keep up to date.
builder.Services.AddDaprWorkflow();
// One exception handler maps a failed workflow call to the error body (see WorkflowErrorHandler).
builder.Services.AddExceptionHandler<WorkflowErrorHandler>();
builder.Services.AddProblemDetails();

var app = builder.Build();
app.UseExceptionHandler();

app.MapPost("/jumps", async (JumpRequest? request, DaprWorkflowClient workflowClient) =>
{
    var jumpId = string.IsNullOrEmpty(request?.JumpId) ? $"jump-{Guid.NewGuid().ToString("N")[..8]}" : request.JumpId;
    var destination = string.IsNullOrEmpty(request?.Destination) ? "Vesper Reach" : request.Destination;
    // The jump ID becomes the workflow instance ID. The call returns as soon as the sidecar has
    // scheduled the workflow; the workflow itself runs in the background.
    await workflowClient.ScheduleNewWorkflowAsync(nameof(LongRangeJumpWorkflow), jumpId, new Jump(jumpId, destination));
    return TypedResults.Json(new JumpStarted(jumpId), statusCode: StatusCodes.Status202Accepted);
});

app.MapGet("/jumps/{jumpId}", async Task<IResult> (string jumpId, DaprWorkflowClient workflowClient) =>
{
    // The sidecar reads the workflow's state from the state store.
    var state = await workflowClient.GetWorkflowStateAsync(jumpId);
    if (!state.Exists)
    {
        return TypedResults.NotFound(new { error = "JUMP_NOT_FOUND" });
    }
    // In-between statuses show as RUNNING, so the learner only sees five statuses.
    var status = state.RuntimeStatus switch
    {
        WorkflowRuntimeStatus.Pending or WorkflowRuntimeStatus.ContinuedAsNew or WorkflowRuntimeStatus.Stalled => "RUNNING",
        var other => other.ToString().ToUpperInvariant(),
    };
    return TypedResults.Ok(new JumpStatus(jumpId, status, state.ReadOutputAs<JsonElement?>()));
});

// Pause, resume and terminate read the state first. Dapr 1.19.1 stalled a finished instance that
// received a control call (fixed in 1.19.2). Keep the guard: a clear 409 beats a
// silent no-op.
async Task<IResult> Control(string jumpId, DaprWorkflowClient workflowClient, Func<Task> call)
{
    var state = await workflowClient.GetWorkflowStateAsync(jumpId);
    if (!state.Exists)
    {
        return TypedResults.NotFound(new { error = "JUMP_NOT_FOUND" });
    }
    if (state.RuntimeStatus is WorkflowRuntimeStatus.Completed or WorkflowRuntimeStatus.Failed or WorkflowRuntimeStatus.Terminated)
    {
        return TypedResults.Conflict(new { error = "JUMP_FINISHED" });
    }
    await call();
    return TypedResults.StatusCode(StatusCodes.Status202Accepted);
}

// Each management endpoint is one call on the workflow client.
app.MapPost("/jumps/{jumpId}/pause", (string jumpId, DaprWorkflowClient workflowClient) =>
    Control(jumpId, workflowClient, () => workflowClient.SuspendWorkflowAsync(jumpId)));

app.MapPost("/jumps/{jumpId}/resume", (string jumpId, DaprWorkflowClient workflowClient) =>
    Control(jumpId, workflowClient, () => workflowClient.ResumeWorkflowAsync(jumpId)));

app.MapPost("/jumps/{jumpId}/terminate", (string jumpId, DaprWorkflowClient workflowClient) =>
    Control(jumpId, workflowClient, () => workflowClient.TerminateWorkflowAsync(jumpId)));

// Purge removes the history of a finished jump. A running jump can't be purged: the call fails
// and the error handler answers 500.
app.MapDelete("/jumps/{jumpId}", async Task<IResult> (string jumpId, DaprWorkflowClient workflowClient) =>
{
    var state = await workflowClient.GetWorkflowStateAsync(jumpId);
    if (!state.Exists)
    {
        return TypedResults.NotFound(new { error = "JUMP_NOT_FOUND" });
    }
    await workflowClient.PurgeInstanceAsync(jumpId);
    return TypedResults.NoContent();
});

app.Run();
