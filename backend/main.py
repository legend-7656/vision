from fastapi import FastAPI, File, UploadFile
from PIL import Image
from io import BytesIO

app = FastAPI(title="ContextAid API")


@app.get("/")
def root():
    return {
        "project": "ContextAid",
        "status": "running"
    }


@app.post("/detect")
async def detect(file: UploadFile = File(...)):
    image_bytes = await file.read()

    image = Image.open(BytesIO(image_bytes))

    return {
        "filename": file.filename,
        "width": image.width,
        "height": image.height,
        "message": "Image received successfully"
    }