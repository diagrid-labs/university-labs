package io.diagrid.university.workflow.engineering;

import io.dapr.workflows.client.DaprWorkflowClient;
import io.dapr.workflows.client.WorkflowState;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/jumps")
class JumpController {

    // Both fields are optional. Demo 1 accepts a destination and ignores it; later demos fly there.
    record JumpRequest(String jumpId, String destination) {
        JumpRequest {
            destination = destination != null ? destination : "Vesper Reach";
        }
    }

    record JumpStarted(String jumpId) {
    }

    record JumpStatus(String jumpId, String status, Object output) {
    }

    private final DaprWorkflowClient workflowClient;

    JumpController(DaprWorkflowClient workflowClient) {
        this.workflowClient = workflowClient;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.ACCEPTED)
    JumpStarted startJump(@RequestBody(required = false) JumpRequest request) {
        String jumpId = request != null && request.jumpId() != null
                ? request.jumpId()
                : "jump-" + UUID.randomUUID().toString().substring(0, 8);
        // The jump ID becomes the workflow instance ID. The call returns as soon as the sidecar
        // has scheduled the workflow; the workflow itself runs in the background.
        workflowClient.scheduleNewWorkflow("ChargeWarpCoreWorkflow", new ChargeWarpCoreWorkflow.Jump(jumpId), jumpId);
        return new JumpStarted(jumpId);
    }

    @GetMapping("/{jumpId}")
    JumpStatus getJump(@PathVariable String jumpId) {
        // The sidecar reads the workflow's state from the state store. For an unknown ID the Java
        // SDK returns an empty state, without an instance ID, rather than null.
        WorkflowState state = workflowClient.getWorkflowState(jumpId, true);
        if (state.getWorkflowId().isEmpty()) {
            throw new ApiErrors.JumpNotFoundException();
        }
        // In-between statuses show as RUNNING, so the learner only sees five statuses.
        String status = switch (state.getRuntimeStatus()) {
            case PENDING, CONTINUED_AS_NEW -> "RUNNING";
            default -> state.getRuntimeStatus().name();
        };
        return new JumpStatus(jumpId, status, state.readOutputAs(Object.class));
    }
}
