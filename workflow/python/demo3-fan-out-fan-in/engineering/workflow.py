import logging
import time

import dapr.ext.workflow as wf

logger = logging.getLogger("engineering")

# The workflow runtime hosts the workflows and activities registered below. app.py starts it.
wfr = wf.WorkflowRuntime()


# Fan-out/fan-in: schedule all the activities first, without yielding each one, so they run at
# the same time. Then wait for all of them with when_all (the fan-in).
# Because Dapr replays this function from the top, it must be deterministic: no clock, random
# numbers, I/O or sleep here. Those belong in activities.
@wfr.workflow(name="RouteScanWorkflow")
def route_scan_workflow(ctx: wf.DaprWorkflowContext, jump: dict):
    # Fan-out: call_activity returns a task straight away, nothing has finished yet.
    scans = [
        ctx.call_activity(scan_sector_activity, input=array)
        for array in ("alpha", "beta", "gamma", "delta", "epsilon")
    ]

    # Fan-in: continue when every scan has finished. The results keep the order of the list.
    results = yield wf.when_all(scans)

    route_risk = max(scan["hazard"] for scan in results)
    return {"routeRisk": route_risk, "verdict": "CLEAR" if route_risk < 50 else "HAZARDOUS"}


@wfr.activity(name="ScanSectorActivity")
def scan_sector_activity(ctx: wf.WorkflowActivityContext, array: str) -> dict:
    time.sleep(2)
    # Fixed scores, so every run and every language logs the same lines.
    hazard = {"alpha": 12, "beta": 7, "gamma": 31, "delta": 4, "epsilon": 18}[array]
    logger.info("engineering sensor array %s scanned hazard=%d", array, hazard)
    return {"array": array, "hazard": hazard}
