package io.diagrid.university.workflow.engineering;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;

// Turns exceptions into the error bodies of the HTTP contract, in one place, so the controller
// methods only describe the happy path.
@RestControllerAdvice
class ApiErrors {

    private static final Logger log = LoggerFactory.getLogger(ApiErrors.class);

    record ErrorBody(String error) {
    }

    // Thrown for a jump ID the workflow engine doesn't know.
    static class JumpNotFoundException extends RuntimeException {
    }

    // Thrown for a jump that has already finished.
    static class JumpFinishedException extends RuntimeException {
    }

    @ExceptionHandler(JumpNotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    ErrorBody jumpNotFound() {
        return new ErrorBody("JUMP_NOT_FOUND");
    }

    @ExceptionHandler(JumpFinishedException.class)
    @ResponseStatus(HttpStatus.CONFLICT)
    ErrorBody jumpFinished() {
        return new ErrorBody("JUMP_FINISHED");
    }

    // A failed workflow call surfaces as a gRPC StatusRuntimeException from the workflow client.
    @ExceptionHandler(io.grpc.StatusRuntimeException.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    ErrorBody workflowFailed(io.grpc.StatusRuntimeException e) {
        log.warn("engineering workflow call failed: {}", e.getMessage());
        return new ErrorBody("WORKFLOW_ERROR");
    }
}
