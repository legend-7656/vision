
def analyze_context(detection, image_width, image_height):
    x1, y1, x2, y2 = detection["bbox"]

    center_x = ((x1 + x2) / 2) / image_width if image_width else 0
    center_y = ((y1 + y2) / 2) / image_height if image_height else 0

    box_area = max(0, x2 - x1) * max(0, y2 - y1)
    image_area = image_width * image_height
    relative_area = box_area / image_area if image_area else 0

    if center_x < 0.33:
        position = "left"
    elif center_x > 0.67:
        position = "right"
    else:
        position = "center"

    if center_y < 0.33:
        vertical_position = "upper"
    elif center_y > 0.67:
        vertical_position = "lower"
    else:
        vertical_position = "middle"

    if relative_area > 0.25:
        apparent_size = "large"
    elif relative_area > 0.08:
        apparent_size = "medium"
    else:
        apparent_size = "small"

    class_name = detection["class_name"]

    return {
        **detection,
        "position": position,
        "vertical_position": vertical_position,
        "apparent_size": apparent_size,
        "relative_area": round(relative_area, 4),
        "context_description": (
            f"{class_name} at {position}, {vertical_position}; "
            f"appears {apparent_size} in the image"
        ),
    }
