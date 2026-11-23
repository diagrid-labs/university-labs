import logging
import time

import dapr.ext.workflow as wf

logger = logging.getLogger("engineering")

# The workflow runtime hosts the workflows and activities registered below. app.py starts it.
wfr = wf.WorkflowRuntime()


# Task chaining: run the activities one after the other, and pass each activity's result on as
# the next activity's input. Every yield is a checkpoint, so after a crash the chain carries on
# with the first activity that has not finished.
# Because Dapr replays this function from the top, it must be deterministic: no clock, random
# numbers, I/O or sleep here. Those belong in activities.
@wfr.workflow(name="JumpWorkflow")
def jump_workflow(ctx: wf.DaprWorkflowContext, jump: dict):
    course = yield ctx.call_activity(plot_course_activity, input=jump["destination"])
    warp_core = yield ctx.call_activity(charge_warp_core_activity, input=course)
    yield ctx.call_activity(align_nav_array_activity, input=warp_core["warpFactor"])
    # The result of the last activity is the workflow's output.
    return (yield ctx.call_activity(
        engage_jump_activity, input={"course": course, "warpFactor": warp_core["warpFactor"]}
    ))


@wfr.activity(name="PlotCourseActivity")
def plot_course_activity(ctx: wf.WorkflowActivityContext, destination: str) -> dict:
    time.sleep(1)
    course = {"destination": destination, "heading": 217, "distanceLy": 4.2}
    logger.info(
        "engineering course plotted to %s heading=%d distanceLy=%.1f",
        destination, course["heading"], course["distanceLy"],
    )
    return course


@wfr.activity(name="ChargeWarpCoreActivity")
def charge_warp_core_activity(ctx: wf.WorkflowActivityContext, course: dict) -> dict:
    time.sleep(1)
    warp_factor = 6
    logger.info("engineering warp core charged to warp %d", warp_factor)
    return {"warpFactor": warp_factor}


@wfr.activity(name="AlignNavArrayActivity")
def align_nav_array_activity(ctx: wf.WorkflowActivityContext, warp_factor: int) -> dict:
    time.sleep(1)
    logger.info("engineering nav array aligned")
    return {"aligned": True}


@wfr.activity(name="EngageJumpActivity")
def engage_jump_activity(ctx: wf.WorkflowActivityContext, engage: dict) -> dict:
    time.sleep(1)
    # Stardate: 78000.0 at 2026-01-01T00:00:00Z, one unit per hour after that. It reads the
    # clock, which is fine in an activity but never in the workflow.
    stardate = round(78000.0 + (int(time.time()) - 1767225600) / 3600.0, 1)
    arrived_at = engage["course"]["destination"]
    logger.info("engineering jump complete, arrived at %s", arrived_at)
    return {"arrivedAt": arrived_at, "stardate": stardate}
