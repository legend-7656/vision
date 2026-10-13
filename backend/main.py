from fastapi import FastAPI, File, UploadFile
from PIL import Image
from io import BytesIO
from fastapi.middleware.cors import CORSMiddleware
from detection.detector import ObjectDetector
from context.context_engine import analyze_context
from priority.priority_engine import create_alerts
from ocr.ocr_engine import OCREngine
from distance.distance_engine import estimate_distance
from fastapi import HTTPException
import logging
from ai.gemini_service import describe_image, GeminiBusyError
import threading

app = FastAPI(title="ContextAid API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

detector = ObjectDetector()
ocr_engine = OCREngine()
model_lock = threading.Lock()  # YOLO/OCR are not safe to run in two threads at once

@app.get("/")
def root():
    return {
        "project": "ContextAid",
        "status": "running"
    }


@app.post("/detect")
def detect(file: UploadFile = File(...), ocr: bool = False):
    try:
        image_bytes = file.file.read()
        image = Image.open(BytesIO(image_bytes)).convert("RGB")
        image_width, image_height = image.size

        with model_lock:
            recognized_text = ocr_engine.read_text(image) if ocr else []
            raw_detections = detector.detect(image)

        contextual_detections = [
            estimate_distance(
                analyze_context(detection, image_width, image_height),
                image_width,
                image_height,
            )
            for detection in raw_detections
        ]

        detections, alerts = create_alerts(contextual_detections)

        return {
            "filename": file.filename,
            "image_size": {"width": image_width, "height": image_height},
            "detections": detections,
            "alerts": alerts,
            "recognized_text": recognized_text,
        }

    except Exception as exc:
        logging.exception("Detection failed")
        raise HTTPException(status_code=500, detail=f"Detection failed: {exc}")

@app.post("/describe")
def describe_scene(file: UploadFile = File(...)):
    try:
        image_bytes = file.file.read()

        if not image_bytes:
            raise HTTPException(
                status_code=400,
                detail="Uploaded image is empty",
            )

        try:
            image = Image.open(BytesIO(image_bytes))
            image.load()
            image = image.convert("RGB")
        except Exception as exc:
            raise HTTPException(
                status_code=415,
                detail=f"Could not decode uploaded image: {exc}",
            )

        try:
            description = describe_image(image)
        except GeminiBusyError:
            raise HTTPException(
                status_code=503,
                detail="Scene description is busy right now. Please try again.",
            )

        return {"scene_description": description}

    except HTTPException:
        raise

    except Exception as exc:
        logging.exception("Gemini scene description failed")
        raise HTTPException(
            status_code=502,
            detail=f"Gemini analysis failed: {type(exc).__name__}: {exc}",
        )