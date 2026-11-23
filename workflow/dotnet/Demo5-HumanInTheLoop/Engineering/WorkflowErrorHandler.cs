using Microsoft.AspNetCore.Diagnostics;

// Turns any failed workflow call into the error body, in one place, so the endpoints only
// describe the happy path.
class WorkflowErrorHandler(ILogger<WorkflowErrorHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext context, Exception exception, CancellationToken cancellationToken)
    {
        logger.LogWarning("engineering workflow call failed: {Error}", exception.Message);
        context.Response.StatusCode = StatusCodes.Status500InternalServerError;
        await context.Response.WriteAsJsonAsync(new { error = "WORKFLOW_ERROR" }, cancellationToken);
        return true;
    }
}
