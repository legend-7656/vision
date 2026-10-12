
from ultralytics import YOLO


class ObjectDetector:
    def __init__(self, model_path="yolov8n.pt"):
        self.model = YOLO(model_path)

    def detect(self, image):
        # persist=True keeps track identities across successive frames.
        results = self.model.track(
            source=image,
            persist=True,
            tracker="botsort.yaml",
            verbose=False,
        )

        detections = []

        for result in results:
            boxes = result.boxes

            if boxes is None:
                continue

            for box in boxes:
                class_id = int(box.cls[0])
                confidence = float(box.conf[0])
                x1, y1, x2, y2 = box.xyxy[0].tolist()

                # A track ID may be unavailable for some detections.
                track_id = None
                if box.id is not None:
                    track_id = int(box.id[0])

                detections.append({
                    "class_id": class_id,
                    "class_name": result.names[class_id],
                    "confidence": confidence,
                    "bbox": [x1, y1, x2, y2],
                    "track_id": track_id,
                })

        return detections
