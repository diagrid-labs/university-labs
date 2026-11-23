package io.diagrid.university.workflow.engineering;

import io.dapr.workflows.WorkflowActivity;
import io.dapr.workflows.WorkflowActivityContext;
import java.util.Locale;
import java.util.concurrent.TimeUnit;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class PlotCourseActivity implements WorkflowActivity {

    private static final Logger log = LoggerFactory.getLogger(PlotCourseActivity.class);

    @Override
    public Object run(WorkflowActivityContext ctx) {
        String destination = ctx.getInput(String.class);
        try {
            TimeUnit.SECONDS.sleep(1);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
        AuthorizedJumpWorkflow.Course course = new AuthorizedJumpWorkflow.Course(destination, 217, 4.2);
        log.info("engineering course plotted to {} heading={} distanceLy={}",
                course.destination(), course.heading(), String.format(Locale.ROOT, "%.1f", course.distanceLy()));
        return course;
    }
}
