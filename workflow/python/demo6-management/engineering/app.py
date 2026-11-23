import json
import logging
import uuid
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Annotated, Any

import grpc
from dapr.ext.workflow.aio import DaprWorkflowClient
from fastapi import Depends, FastAPI, Request
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel, ConfigDict
from pydantic.alias_generators import to_camel

from workflow import long_range_jump_workflow, wfr

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("engineering")
# The workflow SDK logs every step at INFO. Keep only its warnings, so the demo's lines stand out.
logging.getLogger("durabletask-worker").setLevel(logging.WARNING)
logging.getLogger("durabletask-client").setLevel(logging.WARNING)


# Fields are snake_case in Python and camelCase in JSON (jump_id <-> jumpId).
class CamelModel(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, validate_by_name=True)


class JumpRequest(CamelModel):
    jump_id: str | None = None
    # A missing, null or empty destination becomes Vesper Reach in the endpoint.
    destination: str | None = None


class JumpStarted(CamelModel):
    jump_id: str


class JumpStatus(CamelModel):
    jump_id: str
    status: str
    output: Any


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    # The runtime opens a gRPC stream to the sidecar and runs the workflow and activity code
    # the sidecar sends it. The client starts and inspects workflows.
    wfr.start()
    app.state.workflow_client = DaprWorkflowClient()
    yield
    wfr.shutdown()


app = FastAPI(lifespan=lifespan)


def get_workflow_client(request: Request) -> DaprWorkflowClient:
    return request.app.state.workflow_client


WorkflowClientDep = Annotated[DaprWorkflowClient, Depends(get_workflow_client)]


# A failed workflow call surfaces as a gRPC error. One handler turns it into the same 500 for
# every endpoint, so the endpoints only describe the happy path.
@app.exception_handler(grpc.RpcError)
async def workflow_failed(_: Request, error: grpc.RpcError) -> JSONResponse:
    # The client raises grpc.aio.AioRpcError; details() is its one-line message.
    logger.warning("engineering workflow call failed: %s", error.details())
    return JSONResponse({"error": "WORKFLOW_ERROR"}, status_code=500)


@app.post("/jumps", status_code=202, response_model=JumpStarted)
async def start_jump(client: WorkflowClientDep, body: JumpRequest | None = None):
    jump_id = (body and body.jump_id) or f"jump-{uuid.uuid4().hex[:8]}"
    destination = (body and body.destination) or "Vesper Reach"
    # The jump ID becomes the workflow instance ID. The call returns as soon as the sidecar has
    # scheduled the workflow; the workflow itself runs in the background.
    await client.schedule_new_workflow(
        long_range_jump_workflow, input={"jumpId": jump_id, "destination": destination}, instance_id=jump_id
    )
    return JumpStarted(jump_id=jump_id)


@app.get("/jumps/{jump_id}", response_model=JumpStatus)
async def get_jump(jump_id: str, client: WorkflowClientDep):
    # The sidecar reads the workflow's state from the state store.
    state = await client.get_workflow_state(jump_id)
    if state is None:
        return JSONResponse({"error": "JUMP_NOT_FOUND"}, status_code=404)
    status = state.runtime_status.name
    # In-between statuses show as RUNNING, so the learner only sees five statuses.
    if status in ("PENDING", "CONTINUED_AS_NEW", "STALLED"):
        status = "RUNNING"
    output = json.loads(state.serialized_output) if state.serialized_output else None
    return JumpStatus(jump_id=jump_id, status=status, output=output)


# Pause, resume and terminate read the state first. Dapr 1.19.1 stalls a finished instance that
# receives a control call, so those calls are not made for one.
async def reject_finished(client: DaprWorkflowClient, jump_id: str) -> JSONResponse | None:
    state = await client.get_workflow_state(jump_id)
    if state is None:
        return JSONResponse({"error": "JUMP_NOT_FOUND"}, status_code=404)
    if state.runtime_status.name in ("COMPLETED", "FAILED", "TERMINATED"):
        return JSONResponse({"error": "JUMP_FINISHED"}, status_code=409)
    return None


# Each management endpoint is one call on the workflow client.
@app.post("/jumps/{jump_id}/pause")
async def pause_jump(jump_id: str, client: WorkflowClientDep):
    if rejected := await reject_finished(client, jump_id):
        return rejected
    await client.pause_workflow(jump_id)
    return Response(status_code=202)


@app.post("/jumps/{jump_id}/resume")
async def resume_jump(jump_id: str, client: WorkflowClientDep):
    if rejected := await reject_finished(client, jump_id):
        return rejected
    await client.resume_workflow(jump_id)
    return Response(status_code=202)


@app.post("/jumps/{jump_id}/terminate")
async def terminate_jump(jump_id: str, client: WorkflowClientDep):
    if rejected := await reject_finished(client, jump_id):
        return rejected
    await client.terminate_workflow(jump_id)
    return Response(status_code=202)


# Purge removes the history of a finished jump. A running jump can't be purged: the call fails
# and the error handler answers 500.
@app.delete("/jumps/{jump_id}")
async def purge_jump(jump_id: str, client: WorkflowClientDep):
    if await client.get_workflow_state(jump_id) is None:
        return JSONResponse({"error": "JUMP_NOT_FOUND"}, status_code=404)
    await client.purge_workflow(jump_id)
    return Response(status_code=204)
