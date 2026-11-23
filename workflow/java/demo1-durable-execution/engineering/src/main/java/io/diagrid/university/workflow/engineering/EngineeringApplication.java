package io.diagrid.university.workflow.engineering;

import io.dapr.workflows.client.DaprWorkflowClient;
import io.dapr.workflows.runtime.WorkflowRuntime;
import io.dapr.workflows.runtime.WorkflowRuntimeBuilder;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.annotation.Bean;
import org.springframework.context.event.EventListener;

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
    // sent. Register each one under an explicit name: by default Java uses the fully qualified
    // class name, and every language in this track uses the same short names. The runtime creates
    // the workflow and activity objects by reflection, which is why those classes are public.
    @EventListener(ApplicationReadyEvent.class)
    void startWorkflowRuntime() {
        WorkflowRuntime runtime = new WorkflowRuntimeBuilder()
                .registerWorkflow("ChargeWarpCoreWorkflow", ChargeWarpCoreWorkflow.class)
                .registerActivity("ChargeStageActivity", ChargeStageActivity.class)
                .build();
        // false: don't block, keep listening for work in the background.
        runtime.start(false);
    }
}
