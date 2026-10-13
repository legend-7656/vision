
# Preliminary webcam calibration.
# Use only after confirming the paper measurement.
FOCAL_LENGTH_PX = 1090.0

# Approximate real-world widths in meters.
# Actual object dimensions vary.
KNOWN_WIDTHS = {
    "stop sign": 0.75,
    "laptop": 0.35,
    "book": 0.20,
    "car": 1.80,
    "motorcycle": 0.8,
    "bicycle": 0.6,
    "bus": 2.5,
    "truck": 2.5,
    "train": 3.0,

    # People and animals
    "person": 0.45,
    "dog": 0.4,
    "cat": 0.2,
    "horse": 0.7,
    "sheep": 0.5,
    "cow": 0.8,
    "elephant": 2.0,
    "bear": 0.8,
    "zebra": 0.8,
    "giraffe": 1.0,

    # Furniture
    "chair": 0.45,
    "couch": 1.8,
    "bed": 1.5,
    "dining table": 1.2,
    "bench": 1.2,

    # Signs and common objects
    "stop sign": 0.75,
    "traffic light": 0.3,
    "fire hydrant": 0.25,
    "backpack": 0.3,
    "suitcase": 0.45,
    "handbag": 0.3,
    "umbrella": 1.0,
    "bottle": 0.07,
    "cup": 0.08,
    "book": 0.20,
    "laptop": 0.35,
    "keyboard": 0.45,
    "mouse": 0.07,
    "cell phone": 0.08,
    "tv": 1.0,
    "microwave": 0.5,
    "oven": 0.6,
    "refrigerator": 0.8,
    "potted plant": 0.4,
    "suitcase": 0.45,
}


def estimate_distance(detection, image_width, image_height):
    x1, y1, x2, y2 = detection["bbox"]

    box_width = max(0.0, x2 - x1)
    box_height = max(0.0, y2 - y1)

    width_ratio = box_width / image_width if image_width else 0.0
    height_ratio = box_height / image_height if image_height else 0.0
    apparent_ratio = max(width_ratio, height_ratio)

    if apparent_ratio >= 0.50:
        category = "very_close_appearing"
    elif apparent_ratio >= 0.25:
        category = "close_appearing"
    elif apparent_ratio >= 0.10:
        category = "medium_apparent_size"
    else:
        category = "small_or_far_appearing"

    class_name = detection["class_name"].lower()
    known_width = KNOWN_WIDTHS.get(class_name)

    distance_m = None

    if known_width is not None and box_width > 0:
        distance_m = round(
            (known_width * FOCAL_LENGTH_PX) / box_width,
            2,
        )

    return {
        **detection,
        "apparent_size_ratio": round(apparent_ratio, 4),
        "distance_category": category,
        "distance_estimate_m": distance_m,
    }
