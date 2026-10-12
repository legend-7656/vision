
import easyocr
import numpy as np


class OCREngine:
    def __init__(self):
        # Load the English OCR model once.
        self.reader = easyocr.Reader(["en"], gpu=False)

    def read_text(self, image):
        # Convert the PIL image to a NumPy RGB array.
        image_array = np.array(image.convert("RGB"))

        results = self.reader.readtext(
            image_array,
            detail=1,
        )

        recognized_text = []

        for bbox, text, confidence in results:
            recognized_text.append({
                "text": text,
                "confidence": round(float(confidence), 4),
                "bbox": [
                    [int(point[0]), int(point[1])]
                    for point in bbox
                ],
            })

        return recognized_text
