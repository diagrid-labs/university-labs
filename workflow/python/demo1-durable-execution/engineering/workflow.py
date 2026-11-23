import logging
import time

import dapr.ext.workflow as wf

logger = logging.getLogger("engineering")

# The workflow runtime hosts the workflows and activities registered below. app.py starts it.
wfr = wf.WorkflowRuntime()

STAGES = 5


# A workflow is code that Dapr makes durable. After every completed activity the sidecar saves
# the workflow's history in the state store. After a crash Dapr runs this function again from
# the top (a replay) and feeds it the saved results, so finished stages are not repeated.
# Because of that replay the function must be deterministic: no clock, random numbers, I/O or
# sleep here. Those belong in activities.
@wfr.workflow(name="ChargeWarpCoreWorkflow")
def charge_warp_core_workflow(ctx: wf.DaprWorkflowContext, jump: dict):
    jump_id = jump["jumpId"]
    # During a replay this line runs again, so only log when the code is not replaying.
    if not ctx.is_replaying:
        logger.info("engineering %s charge sequence started", jump_id)

    for stage in range(1, STAGES + 1):
        # Each yield is a checkpoint: the activity's result is stored in the workflow history.
        # On a replay a stage that already finished returns its stored result straight away.
        yield ctx.call_activity(charge_stage_activity, input={"jumpId": jump_id, "stage": stage})

    return {"jumpId": jump_id, "coreCharged": True}


# An activity does the real work, and may be slow or have side effects. Dapr runs it at least
# once: a stage that was running during a crash runs again from the start.
@wfr.activity(name="ChargeStageActivity")
def charge_stage_activity(ctx: wf.WorkflowActivityContext, charge: dict) -> None:
    time.sleep(3)
    logger.info("engineering charge stage %d/%d complete for %s", charge["stage"], STAGES, charge["jumpId"])
