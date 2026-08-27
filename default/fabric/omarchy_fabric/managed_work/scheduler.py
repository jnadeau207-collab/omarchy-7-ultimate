"""Pure bounded schedule validation and missed-run reconciliation."""

from __future__ import annotations

import math
from datetime import datetime, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from .errors import ManagedWorkError
from .validation import closed_object, enum_value, integer, stable_id, timestamp

MAX_CALENDAR_SCAN_DAYS = 50_000


def normalize_trigger(value: Any) -> dict[str, Any]:
    base = closed_object(
        value,
        field="automation trigger",
        required={"kind"},
        optional={"seconds", "anchor", "topic", "timeZone", "hour", "minute", "weekdays", "dstPolicy"},
    )
    kind = enum_value(base["kind"], field="trigger kind", choices={"interval", "calendar", "event"})
    if kind == "interval":
        data = closed_object(base, field="interval trigger", required={"kind", "seconds", "anchor"})
        return {
            "kind": kind,
            "seconds": integer(data["seconds"], field="interval seconds", minimum=60, maximum=31_536_000),
            "anchor": timestamp(data["anchor"], field="interval anchor"),
        }
    if kind == "event":
        data = closed_object(base, field="event trigger", required={"kind", "topic"})
        return {"kind": kind, "topic": stable_id(data["topic"], field="event topic")}
    data = closed_object(
        base,
        field="calendar trigger",
        required={"kind", "timeZone", "hour", "minute", "weekdays", "dstPolicy"},
    )
    if not isinstance(data["timeZone"], str) or len(data["timeZone"]) > 128:
        raise ManagedWorkError("schedule.time-zone", "The calendar time zone is invalid.")
    try:
        ZoneInfo(data["timeZone"])
    except ZoneInfoNotFoundError as error:
        raise ManagedWorkError("schedule.time-zone", "The calendar time zone is not installed.") from error
    weekdays = data["weekdays"]
    if not isinstance(weekdays, list) or not weekdays or len(weekdays) > 7:
        raise ManagedWorkError("schedule.weekdays", "Calendar weekdays must be a non-empty array.")
    normalized_weekdays = sorted(
        {integer(day, field="calendar weekday", minimum=0, maximum=6) for day in weekdays}
    )
    if len(normalized_weekdays) != len(weekdays):
        raise ManagedWorkError("schedule.weekdays", "Calendar weekdays must not contain duplicates.")
    return {
        "kind": kind,
        "timeZone": data["timeZone"],
        "hour": integer(data["hour"], field="calendar hour", minimum=0, maximum=23),
        "minute": integer(data["minute"], field="calendar minute", minimum=0, maximum=59),
        "weekdays": normalized_weekdays,
        "dstPolicy": enum_value(
            data["dstPolicy"],
            field="DST policy",
            choices={"wall-clock-first", "wall-clock-second", "skip-invalid"},
        ),
    }


def normalize_policy(value: Any) -> dict[str, Any]:
    data = closed_object(
        value,
        field="automation policy",
        required={
            "missedRun",
            "coalescing",
            "maxCatchUp",
            "concurrency",
            "maxConcurrent",
            "retry",
            "limits",
            "signedOut",
        },
    )
    retry = closed_object(data["retry"], field="retry policy", required={"maxAttempts", "backoffSeconds"})
    limits = closed_object(data["limits"], field="automation limits", required={"timeSeconds", "costMicrounits"})
    signed_out = enum_value(data["signedOut"], field="signed-out policy", choices={"pause"})
    return {
        "missedRun": enum_value(data["missedRun"], field="missed-run policy", choices={"skip", "run-once", "catch-up"}),
        "coalescing": enum_value(data["coalescing"], field="coalescing policy", choices={"earliest", "latest", "all"}),
        "maxCatchUp": integer(data["maxCatchUp"], field="maximum catch-up", minimum=1, maximum=32),
        "concurrency": enum_value(data["concurrency"], field="concurrency policy", choices={"forbid", "replace", "allow"}),
        "maxConcurrent": integer(data["maxConcurrent"], field="maximum concurrency", minimum=1, maximum=8),
        "retry": {
            "maxAttempts": integer(retry["maxAttempts"], field="retry attempts", minimum=0, maximum=10),
            "backoffSeconds": integer(retry["backoffSeconds"], field="retry backoff", minimum=1, maximum=86_400),
        },
        "limits": {
            "timeSeconds": integer(limits["timeSeconds"], field="automation time limit", minimum=1, maximum=604_800),
            "costMicrounits": integer(limits["costMicrounits"], field="automation cost limit", minimum=0, maximum=10**15),
        },
        "signedOut": signed_out,
    }


def first_due(trigger: dict[str, Any], *, created_at: float) -> float | None:
    if trigger["kind"] == "event":
        return None
    if trigger["kind"] == "interval":
        anchor = float(trigger["anchor"])
        if anchor >= created_at:
            return anchor
        seconds = int(trigger["seconds"])
        return anchor + math.ceil((created_at - anchor) / seconds) * seconds
    return next_calendar(trigger, after=created_at, inclusive=True)


def next_calendar(trigger: dict[str, Any], *, after: float, inclusive: bool = False) -> float:
    zone = ZoneInfo(trigger["timeZone"])
    local_start = datetime.fromtimestamp(after, timezone.utc).astimezone(zone)
    start_day = local_start.date()
    for offset in range(MAX_CALENDAR_SCAN_DAYS):
        day = start_day + timedelta(days=offset)
        if day.weekday() not in trigger["weekdays"]:
            continue
        fold = 1 if trigger["dstPolicy"] == "wall-clock-second" else 0
        local = datetime(day.year, day.month, day.day, trigger["hour"], trigger["minute"], tzinfo=zone, fold=fold)
        utc = local.astimezone(timezone.utc)
        round_trip = utc.astimezone(zone)
        if (round_trip.date(), round_trip.hour, round_trip.minute) != (day, trigger["hour"], trigger["minute"]):
            continue
        candidate = utc.timestamp()
        if candidate > after or (inclusive and candidate == after):
            return candidate
    raise ManagedWorkError(
        "schedule.scan-capacity",
        "No calendar occurrence was found within the bounded schedule horizon.",
    )


def next_due(trigger: dict[str, Any], *, after: float) -> float | None:
    if trigger["kind"] == "event":
        return None
    if trigger["kind"] == "interval":
        return after + int(trigger["seconds"])
    return next_calendar(trigger, after=after, inclusive=False)


def reconcile_due(
    trigger: dict[str, Any],
    policy: dict[str, Any],
    *,
    due_at: float | None,
    now: float,
) -> tuple[list[float], float | None, int]:
    """Return selected occurrences, the next future due time, and exact missed count."""

    if trigger["kind"] == "event" or due_at is None or due_at > now:
        return [], due_at, 0
    occurrences: list[float]
    if trigger["kind"] == "interval":
        seconds = int(trigger["seconds"])
        count = int(math.floor((now - due_at) / seconds)) + 1
        latest_due = due_at + (count - 1) * seconds
        missed = [due_at + index * seconds for index in range(min(count, policy["maxCatchUp"]))]
        if policy["coalescing"] == "latest" and count > policy["maxCatchUp"]:
            start = count - policy["maxCatchUp"]
            missed = [due_at + index * seconds for index in range(start, count)]
        occurrences = missed
        future = due_at + count * seconds
    else:
        occurrences = []
        cursor = due_at
        count = 0
        latest: list[float] = []
        while cursor <= now:
            count += 1
            if count > MAX_CALENDAR_SCAN_DAYS:
                raise ManagedWorkError(
                    "schedule.reconcile-capacity",
                    "Missed calendar occurrences exceed the bounded reconciliation horizon.",
                    recovery_actions=("automation.review-schedule",),
                )
            if len(occurrences) < policy["maxCatchUp"]:
                occurrences.append(cursor)
            latest.append(cursor)
            if len(latest) > policy["maxCatchUp"]:
                latest.pop(0)
            cursor = next_calendar(trigger, after=cursor)
        if policy["coalescing"] == "latest":
            occurrences = latest
        future = cursor

    if policy["missedRun"] == "skip":
        selected: list[float] = []
    elif policy["missedRun"] == "run-once":
        selected = [latest_due if trigger["kind"] == "interval" else latest[-1]]
    else:
        selected = occurrences[: policy["maxCatchUp"]]
    return selected, future, count
