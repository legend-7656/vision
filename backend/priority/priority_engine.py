
import time

# Track-aware alert cooldown memory.
_last_alert_time = {}
ALERT_COOLDOWN_SECONDS = 5

HIGH_PRIORITY = {
    "car",
    "truck",
    "bus",
    "motorcycle",
    "bicycle",
    "train",
}

MEDIUM_PRIORITY = {
    "person",
    "chair",
    "bench",
    "dog",
    "cat",
    "stop sign",
    "traffic light",
}


def prioritize_detection(detection):
    name = detection["class_name"].lower()
    confidence = detection["confidence"]
    size = detection["apparent_size"]
    position = detection["position"]

    if confidence < 0.35:
        priority = "low"
    elif name in HIGH_PRIORITY:
        priority = "high"
    elif name in MEDIUM_PRIORITY:
        priority = "medium"
    else:
        priority = "low"

    if size == "large" and position == "center" and confidence >= 0.5:
        if priority == "medium":
            priority = "high"

    return {
        **detection,
        "priority": priority,
    }


def create_alerts(detections):
    now = time.monotonic()
    alerts = []

    rank = {"high": 0, "medium": 1, "low": 2}
    prioritized = sorted(
        (prioritize_detection(d) for d in detections),
        key=lambda d: rank[d["priority"]],
    )

    for detection in prioritized:
        if detection["priority"] == "low":
            continue

        track_id = detection.get("track_id")

        if track_id is not None:
            # Separate cooldowns for distinct tracked objects.
            key = ("track", track_id)
        else:
            # Fallback when the tracker cannot assign an ID.
            key = (
                "class_position",
                detection["class_name"],
                detection["position"],
            )

        previous = _last_alert_time.get(key, 0)

        if now - previous < ALERT_COOLDOWN_SECONDS:
            continue

        _last_alert_time[key] = now

        alerts.append({
            "object": detection["class_name"],
            "priority": detection["priority"],
            "track_id": track_id,
            "message": (
                f"{detection['class_name']} "
                f"on your {detection['position']}"
            ),
        })

    return prioritized, alerts
