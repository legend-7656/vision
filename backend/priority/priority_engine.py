
import time

_last_alert_time = {}
ALERT_COOLDOWN_SECONDS = 5

HIGH_PRIORITY = {
    "car", "truck", "bus", "motorcycle",
    "bicycle", "train",
}

MEDIUM_PRIORITY = {
    "person", "chair", "bench", "dog",
    "cat", "stop sign", "traffic light",
}


def prioritize_detection(detection):
    name = detection["class_name"].lower()
    confidence = detection["confidence"]
    size = detection.get("apparent_size", "small")
    position = detection.get("position", "center")

    if confidence < 0.35:
        priority = "low"
    elif name in HIGH_PRIORITY:
        priority = "high"
    elif name in MEDIUM_PRIORITY:
        priority = "medium"
    else:
        priority = "low"

    if (
        priority == "medium"
        and size == "large"
        and position == "center"
        and confidence >= 0.5
    ):
        priority = "high"

    return {**detection, "priority": priority}


def create_alerts(detections):
    now = time.monotonic()
    rank = {"high": 0, "medium": 1, "low": 2}

    prioritized = sorted(
        (prioritize_detection(d) for d in detections),
        key=lambda d: rank[d["priority"]],
    )

    # Group far-appearing detections by class and direction.
    groups = {}

    for detection in prioritized:
        if detection["priority"] == "low":
            continue

        name = detection["class_name"].lower()
        position = detection.get("position", "center")
        category = detection.get("distance_category", "")
        distance = detection.get("distance_estimate_m")

        is_far = (
            category == "small_or_far_appearing"
            or (
                isinstance(distance, (int, float))
                and distance >= 10
            )
        )

        if is_far:
            key = ("far_group", name, position)
        else:
            track_id = detection.get("track_id")
            if track_id is not None:
                key = ("track", name, track_id)
            else:
                # Fallback for detections without tracking IDs.
                key = (
                    "single",
                    name,
                    position,
                    tuple(round(v, 1) for v in detection["bbox"]),
                )

        groups.setdefault(key, []).append(detection)

    alerts = []

    for key, items in groups.items():
        previous = _last_alert_time.get(key, 0)

        if now - previous < ALERT_COOLDOWN_SECONDS:
            continue

        _last_alert_time[key] = now

        first = items[0]
        name = first["class_name"].lower()
        position = first.get("position", "center")
        count = len(items)

        group_priority = min(
            (d["priority"] for d in items),
            key=lambda p: rank[p],
        )

        if key[0] == "far_group" and count > 1:
            message = f"Multiple {name}s on your {position}"
        elif group_priority == "high":
            message = f"Caution! {name} on your {position}"
        else:
            message = f"{name} on your {position}"

        alerts.append({
            "object": name,
            "count": count,
            "priority": group_priority,
            "position": position,
            "track_ids": [
                d["track_id"]
                for d in items
                if d.get("track_id") is not None
            ],
            "message": message,
        })

    return prioritized, alerts
