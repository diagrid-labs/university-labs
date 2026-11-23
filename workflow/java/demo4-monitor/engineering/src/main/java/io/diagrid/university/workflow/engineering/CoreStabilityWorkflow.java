package io.diagrid.university.workflow.engineering;

import io.dapr.workflows.Workflow;
import io.dapr.workflows.WorkflowStub;
import java.time.Duration;

// A monitor: check the core temperature, wait, check again, without a loop that stays alive.
// Each run of this stub is one check. Between checks it sleeps on a durable timer and then
// continues as new.
// Because Dapr runs the stub again from the top (a replay), the code must be deterministic: no
// clock, random numbers, I/O or Thread.sleep here. Those belong in activities.
public class CoreStabilityWorkflow implements Workflow {

    record Jump(String jumpId, int check) {
    }

    record CoreStability(boolean stable, int checks, int coreTempK) {
    }

    @Override
    public WorkflowStub create() {
        return ctx -> {
            Jump jump = ctx.getInput(Jump.class);
            int check = jump.check();
            int coreTempK = ctx.callActivity("ReadCoreTempActivity", check, Integer.class).await();

            if (coreTempK <= 1000) {
                ctx.complete(new CoreStability(true, check, coreTempK));
                return;
            }

            // The guard every monitor needs: give up after 10 checks.
            if (check == 10) {
                ctx.complete(new CoreStability(false, check, coreTempK));
                return;
            }

            // A durable timer is stored by Dapr, not held in memory. Stop the app during the wait
            // and the timer keeps running; the workflow continues when the app is back.
            ctx.createTimer(Duration.ofSeconds(5)).await();

            // Continue-as-new restarts the workflow with new input and an empty history. A loop
            // inside one run would grow the history with every check.
            ctx.continueAsNew(new Jump(jump.jumpId(), check + 1));
        };
    }
}
