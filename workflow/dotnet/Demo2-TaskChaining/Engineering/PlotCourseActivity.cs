using System.Globalization;
using Dapr.Workflow;

class PlotCourseActivity(ILogger<PlotCourseActivity> logger) : WorkflowActivity<string, Course>
{
    public override async Task<Course> RunAsync(WorkflowActivityContext context, string destination)
    {
        await Task.Delay(TimeSpan.FromSeconds(1));
        var course = new Course(destination, 217, 4.2);
        logger.LogInformation("engineering course plotted to {Destination} heading={Heading} distanceLy={DistanceLy}",
            course.Destination, course.Heading, course.DistanceLy.ToString("0.0", CultureInfo.InvariantCulture));
        return course;
    }
}
