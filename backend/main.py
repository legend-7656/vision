from fastapi import FastAPI, File, UploadFile
from PIL import Image
from io import BytesIO
from fastapi.middleware.cors import CORSMiddleware
from detection.detector import ObjectDetector


app = FastAPI(title="ContextAid API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

detector = ObjectDetector()


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

    detections = detector.detect(image)

    return {
        "filename": file.filename,
        "detections": detections
    }