import logging
import time
from datetime import timedelta

import dapr.ext.workflow as wf

logger = logging.getLogger("engineering")

# The workflow runtime hosts the workflows and activities registered below. app.py starts it.
wfr = wf.WorkflowRuntime()


# Human in the loop: plot the course, then wait for the captain. While it waits, the workflow
# costs nothing: no thread, no timer in memory. The app can even be restarted.
# Because Dapr replays this function from the top, it must be deterministic: no clock, random
# numbers, I/O or sleep here. Those belong in activities.
@wfr.workflow(name="AuthorizedJumpWorkflow")
def authorized_jump_workflow(ctx: wf.DaprWorkflowContext, jump: dict):
    jump_id = jump["jumpId"]
    course = yield ctx.call_activity(plot_course_activity, input=jump["destination"])

    # During a replay this line runs again, so only log when the code is not replaying.
    if not ctx.is_replaying:
        logger.info("engineering %s awaiting captain's authorization", jump_id)

    # Wait for the external event "jump-authorized", raised by POST /jumps/{jumpId}/authorize.
    # With a timeout, the wait raises a TimeoutError when nobody answers in time.
    try:
        authorization = yield ctx.wait_for_external_event("jump-authorized", timeout=timedelta(seconds=60))
    except TimeoutError:
        if not ctx.is_replaying:
            logger.info("engineering %s jump aborted, no authorization", jump_id)
        return {"status": "ABORTED_NO_AUTHORIZATION"}

    officer = authorization["officer"]
    if not authorization["approved"]:
        if not ctx.is_replaying:
            logger.info("engineering %s jump denied by %s", jump_id, officer)
        return {"status": "DENIED", "authorizedBy": officer}

    # Engage with a fixed warp factor: this demo has no warp core charging step.
    yield ctx.call_activity(engage_jump_activity, input={"course": course, "warpFactor": 6})
    return {"status": "JUMPED", "authorizedBy": officer}


@wfr.activity(name="PlotCourseActivity")
def plot_course_activity(ctx: wf.WorkflowActivityContext, destination: str) -> dict:
    time.sleep(1)
    course = {"destination": destination, "heading": 217, "distanceLy": 4.2}
    logger.info(
        "engineering course plotted to %s heading=%d distanceLy=%.1f",
        destination, course["heading"], course["distanceLy"],
    )
    return course


@wfr.activity(name="EngageJumpActivity")
def engage_jump_activity(ctx: wf.WorkflowActivityContext, engage: dict) -> dict:
    time.sleep(1)
    # Stardate: 78000.0 at 2026-01-01T00:00:00Z, one unit per hour after that. It reads the
    # clock, which is fine in an activity but never in the workflow.
    stardate = round(78000.0 + (int(time.time()) - 1767225600) / 3600.0, 1)
    arrived_at = engage["course"]["destination"]
    logger.info("engineering jump complete, arrived at %s", arrived_at)
    return {"arrivedAt": arrived_at, "stardate": stardate}
