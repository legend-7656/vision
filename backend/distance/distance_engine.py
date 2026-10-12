
def estimate_distance(detection, image_width, image_height):
    """
    Experimental apparent-size estimate.

    This is NOT a measurement of actual distance.
    It only categorizes the object's relative image size.
    """

    x1, y1, x2, y2 = detection["bbox"]

    box_width = max(0.0, x2 - x1)
    box_height = max(0.0, y2 - y1)

    width_ratio = box_width / image_width if image_width else 0.0
    height_ratio = box_height / image_height if image_height else 0.0

    # Use the larger dimension to estimate apparent image size.
    apparent_ratio = max(width_ratio, height_ratio)

    if apparent_ratio >= 0.50:
        distance_category = "very_close_appearing"
    elif apparent_ratio >= 0.25:
        distance_category = "close_appearing"
    elif apparent_ratio >= 0.10:
        distance_category = "medium_apparent_size"
    else:
        distance_category = "small_or_far_appearing"

    return {
        **detection,
        "apparent_size_ratio": round(apparent_ratio, 4),
        "distance_category": distance_category,
        "distance_estimate_m": None,
    }
