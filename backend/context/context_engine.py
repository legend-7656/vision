
def analyze_context(detection, image_width, image_height):
    x1, y1, x2, y2 = detection["bbox"]

    center_x = ((x1 + x2) / 2) / image_width
    center_y = ((y1 + y2) / 2) / image_height

    box_area = max(0, x2 - x1) * max(0, y2 - y1)
    image_area = image_width * image_height
    relative_area = box_area / image_area if image_area else 0

    # Image position is a rough visual cue, not a distance measurement.
    if center_x < 0.33:
        position = "left"
    elif center_x > 0.67:
        position = "right"
    else:
        position = "center"

    if relative_area > 0.25:
        apparent_size = "large"
    elif relative_area > 0.08:
        apparent_size = "medium"
    else:
        apparent_size = "small"

    return {
        **detection,
        "position": position,
        "apparent_size": apparent_size,
        "relative_area": round(relative_area, 4),
    }
