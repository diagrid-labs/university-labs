package io.diagrid.university.workflow.engineering;

import io.dapr.workflows.client.DaprWorkflowClient;
import io.dapr.workflows.client.WorkflowState;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
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

    // Both fields are optional. A missing, null or empty destination becomes Vesper Reach.
    record JumpRequest(String jumpId, String destination) {
        JumpRequest {
            destination = destination != null && !destination.isEmpty() ? destination : "Vesper Reach";
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
        String jumpId = request != null && request.jumpId() != null && !request.jumpId().isEmpty()
                ? request.jumpId()
                : "jump-" + UUID.randomUUID().toString().substring(0, 8);
        String destination = (request != null ? request : new JumpRequest(null, null)).destination();
        // The jump ID becomes the workflow instance ID. The call returns as soon as the sidecar
        // has scheduled the workflow; the workflow itself runs in the background.
        workflowClient.scheduleNewWorkflow("LongRangeJumpWorkflow", new LongRangeJumpWorkflow.Jump(jumpId, destination), jumpId);
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

    // Pause, resume and terminate read the state first. Dapr 1.19.1 stalls a finished instance that
    // receives a control call, so those calls are not made for one.
    private void requireUnfinished(String jumpId) {
        WorkflowState state = workflowClient.getWorkflowState(jumpId, false);
        if (state.getWorkflowId().isEmpty()) {
            throw new ApiErrors.JumpNotFoundException();
        }
        switch (state.getRuntimeStatus()) {
            case COMPLETED, FAILED, TERMINATED -> throw new ApiErrors.JumpFinishedException();
            default -> {
            }
        }
    }

    // Each management endpoint is one call on the workflow client.
    @PostMapping("/{jumpId}/pause")
    @ResponseStatus(HttpStatus.ACCEPTED)
    void pause(@PathVariable String jumpId) {
        requireUnfinished(jumpId);
        workflowClient.suspendWorkflow(jumpId, null);
    }

    @PostMapping("/{jumpId}/resume")
    @ResponseStatus(HttpStatus.ACCEPTED)
    void resume(@PathVariable String jumpId) {
        requireUnfinished(jumpId);
        workflowClient.resumeWorkflow(jumpId, null);
    }

    @PostMapping("/{jumpId}/terminate")
    @ResponseStatus(HttpStatus.ACCEPTED)
    void terminate(@PathVariable String jumpId) {
        requireUnfinished(jumpId);
        workflowClient.terminateWorkflow(jumpId, null);
    }

    // Purge removes the history of a finished jump. A running jump can't be purged: the call
    // fails and the error handler answers 500.
    @DeleteMapping("/{jumpId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void purge(@PathVariable String jumpId) {
        if (workflowClient.getWorkflowState(jumpId, false).getWorkflowId().isEmpty()) {
            throw new ApiErrors.JumpNotFoundException();
        }
        workflowClient.purgeWorkflow(jumpId);
    }
}
