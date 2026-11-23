import logging
from datetime import timedelta

import dapr.ext.workflow as wf

logger = logging.getLogger("engineering")

# The workflow runtime hosts the workflows and activities registered below. app.py starts it.
wfr = wf.WorkflowRuntime()

LEGS = 10


# Management: a jump long enough to pause, resume, terminate and purge by hand. It has 10 legs.
# Each leg is an activity followed by a 5-second durable timer.
# Because Dapr replays this function from the top, it must be deterministic: no clock, random
# numbers, I/O or sleep here. Those belong in activities.
@wfr.workflow(name="LongRangeJumpWorkflow")
def long_range_jump_workflow(ctx: wf.DaprWorkflowContext, jump: dict):
    for leg in range(1, LEGS + 1):
        yield ctx.call_activity(engage_leg_activity, input={"jumpId": jump["jumpId"], "number": leg, "total": LEGS})

        # A durable timer is stored by Dapr, not held in memory. While the workflow is paused,
        # the timer still fires, but the workflow only continues after it is resumed.
        yield ctx.create_timer(timedelta(seconds=5))
    return {"status": "JUMPED", "arrivedAt": jump["destination"]}


@wfr.activity(name="EngageLegActivity")
def engage_leg_activity(ctx: wf.WorkflowActivityContext, leg: dict) -> None:
    logger.info("engineering %s leg %d/%d complete", leg["jumpId"], leg["number"], leg["total"])
