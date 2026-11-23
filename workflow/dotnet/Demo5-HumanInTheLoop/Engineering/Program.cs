using System.Text.Json;
using Dapr.Workflow;

var builder = WebApplication.CreateBuilder(args);
// Adds the workflow runtime, which connects to the sidecar and runs the workflow and activity
// code it is sent, and a DaprWorkflowClient that starts and inspects workflows. The SDK finds
// every Workflow and WorkflowActivity class in the project and registers it under its class
// name (AuthorizedJumpWorkflow, PlotCourseActivity, ...), so there is no list to keep up to date.
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
    await workflowClient.ScheduleNewWorkflowAsync(nameof(AuthorizedJumpWorkflow), jumpId, new Jump(jumpId, destination));
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

// Raises the external event the workflow is waiting for.
app.MapPost("/jumps/{jumpId}/authorize", async Task<IResult> (string jumpId, Authorization authorization, DaprWorkflowClient workflowClient) =>
{
    var state = await workflowClient.GetWorkflowStateAsync(jumpId);
    if (!state.Exists)
    {
        return TypedResults.NotFound(new { error = "JUMP_NOT_FOUND" });
    }
    // Dapr 1.19.1 stalled a finished instance that received an event (fixed in 1.19.2).
    // Keep the guard: a clear 409 beats a silent no-op.
    if (state.RuntimeStatus is WorkflowRuntimeStatus.Completed or WorkflowRuntimeStatus.Failed or WorkflowRuntimeStatus.Terminated)
    {
        return TypedResults.Conflict(new { error = "JUMP_FINISHED" });
    }
    await workflowClient.RaiseEventAsync(jumpId, "jump-authorized", authorization);
    return TypedResults.StatusCode(StatusCodes.Status202Accepted);
});

app.Run();
