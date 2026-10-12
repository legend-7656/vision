
import time

# Per-process memory for a simple alert cooldown.
_last_alert_time = {}
ALERT_COOLDOWN_SECONDS = 5

# Initial experimental rules, not a validated safety classifier.
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

    # A large object near the center may warrant more attention,
    # but this does not establish collision risk.
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

        # Cooldown is per class and approximate position.
        key = (
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
            "message": (
                f"{detection['class_name']} "
                f"on your {detection['position']}"
            ),
        })

    return prioritized, alerts
