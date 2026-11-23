import logging
from datetime import timedelta

import dapr.ext.workflow as wf

logger = logging.getLogger("engineering")

# The workflow runtime hosts the workflows and activities registered below. app.py starts it.
wfr = wf.WorkflowRuntime()


# A monitor: check the core temperature, wait, check again, without a loop that stays alive.
# Each run of this function is one check. Between checks it sleeps on a durable timer and then
# continues as new.
# Because Dapr replays this function from the top, it must be deterministic: no clock, random
# numbers, I/O or sleep here. Those belong in activities.
@wfr.workflow(name="CoreStabilityWorkflow")
def core_stability_workflow(ctx: wf.DaprWorkflowContext, jump: dict):
    check = jump["check"]
    core_temp_k = yield ctx.call_activity(read_core_temp_activity, input=check)

    if core_temp_k <= 1000:
        return {"stable": True, "checks": check, "coreTempK": core_temp_k}

    # The guard every monitor needs: give up after 10 checks.
    if check == 10:
        return {"stable": False, "checks": check, "coreTempK": core_temp_k}

    # A durable timer is stored by Dapr, not held in memory. Stop the app during the wait and
    # the timer keeps running; the workflow continues when the app is back.
    yield ctx.create_timer(timedelta(seconds=5))

    # Continue-as-new restarts the workflow with new input and an empty history. A loop inside
    # one run would grow the history with every check.
    ctx.continue_as_new({"jumpId": jump["jumpId"], "check": check + 1})


@wfr.activity(name="ReadCoreTempActivity")
def read_core_temp_activity(ctx: wf.WorkflowActivityContext, check: int) -> int:
    # A fixed sequence, so every run and every language logs the same lines.
    core_temp_k = 1240 - 60 * (check - 1)
    logger.info("engineering core temperature check %d: %dK", check, core_temp_k)
    return core_temp_k
