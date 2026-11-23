package io.diagrid.university.workflow.engineering;

import io.dapr.workflows.client.DaprWorkflowClient;
import io.dapr.workflows.runtime.WorkflowRuntime;
import io.dapr.workflows.runtime.WorkflowRuntimeBuilder;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.ApplicationListener;
import org.springframework.context.annotation.Bean;

@SpringBootApplication
public class EngineeringApplication {

    public static void main(String[] args) {
        SpringApplication.run(EngineeringApplication.class, args);
    }

    // One workflow client per app: it starts and inspects workflows over a gRPC connection to the
    // sidecar. DaprWorkflowClient is AutoCloseable, so Spring closes it on shutdown.
    @Bean
    DaprWorkflowClient daprWorkflowClient() {
        return new DaprWorkflowClient();
    }

    // The workflow runtime connects to the sidecar and runs the workflow and activity code it is
    // sent. WorkflowRuntime is AutoCloseable, so Spring closes it on shutdown. Register each one
    // under an explicit name: by default Java uses the fully qualified class name, and every
    // language in this track uses the same short names. The runtime creates the workflow and
    // activity objects by reflection, which is why those classes are public.
    @Bean
    WorkflowRuntime workflowRuntime() {
        return new WorkflowRuntimeBuilder()
                .registerWorkflow("LongRangeJumpWorkflow", LongRangeJumpWorkflow.class)
                .registerActivity("EngageLegActivity", EngageLegActivity.class)
                .build();
    }

    // Start the runtime once the app is ready. false: don't block, keep listening for work in the
    // background.
    @Bean
    ApplicationListener<ApplicationReadyEvent> startWorkflowRuntime(WorkflowRuntime workflowRuntime) {
        return event -> workflowRuntime.start(false);
    }
}
