from fastapi import FastAPI, File, UploadFile
from PIL import Image
from io import BytesIO
from fastapi.middleware.cors import CORSMiddleware
from detection.detector import ObjectDetector
from context.context_engine import analyze_context
from priority.priority_engine import create_alerts
from ocr.ocr_engine import OCREngine

app = FastAPI(title="ContextAid API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

detector = ObjectDetector()
ocr_engine = OCREngine()

@app.get("/")
def root():
    return {
        "project": "ContextAid",
        "status": "running"
    }



@app.post("/detect")
async def detect(file: UploadFile = File(...)):
    image_bytes = await file.read()

    image = Image.open(
        BytesIO(image_bytes)
    ).convert("RGB")

    image_width, image_height = image.size

    recognized_text = ocr_engine.read_text(image)

    raw_detections = detector.detect(image)

    contextual_detections = [
        analyze_context(
            detection,
            image_width,
            image_height,
        )
        for detection in raw_detections
    ]

    detections, alerts = create_alerts(
        contextual_detections
    )

    return {
        "filename": file.filename,
        "image_size": {
            "width": image_width,
            "height": image_height,
        },
        "detections": detections,
        "alerts": alerts,
    
    "recognized_text": recognized_text,
    }