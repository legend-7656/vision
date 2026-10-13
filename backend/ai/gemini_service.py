import logging
import os
import random
import time
from pathlib import Path

from dotenv import load_dotenv
from google import genai
from google.genai import errors
from PIL import Image

load_dotenv(Path(__file__).resolve().parents[1] / ".env")

logger = logging.getLogger(__name__)

# HTTP status codes worth retrying: rate limit + temporary server problems.
RETRYABLE_CODES = {429, 500, 503, 504}
ATTEMPTS_PER_MODEL = 3
MAX_IMAGE_SIDE = 1024  # smaller image = faster, cheaper, fewer failures

PROMPT = """
You are helping a visually impaired person understand a camera scene.

Return a concise description in plain English:
1. Describe the overall scene.
2. Identify additional clearly visible objects, including objects
   that a basic object detector might not recognize.
3. Mention visible obstacles only when clearly supported by the image.
4. Do not invent objects or claim uncertain details as facts.
5. Do not guess exact distances, safe paths, or precise left/right
   positions from the image.
6. Use at most 3 short sentences, suitable for text-to-speech.
"""

_client = None


class GeminiBusyError(Exception):
    """Gemini was overloaded or rate-limited even after retries and fallback."""


def _get_client() -> genai.Client:
    """Create the Gemini client once and reuse it."""
    global _client
    if _client is None:
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            raise ValueError("GEMINI_API_KEY is missing from backend/.env")
        _client = genai.Client(api_key=api_key)
    return _client


def _model_chain() -> list[str]:
    """Primary model first, then a lighter fallback model."""
    primary = os.getenv("GEMINI_MODEL", "gemini-flash-latest")
    fallback = os.getenv("GEMINI_FALLBACK_MODEL", "gemini-flash-lite-latest")
    return [primary] if primary == fallback else [primary, fallback]


def _prepare_image(image: Image.Image) -> Image.Image:
    """Shrink large images before upload."""
    image = image.convert("RGB")
    image.thumbnail((MAX_IMAGE_SIDE, MAX_IMAGE_SIDE))
    return image


def describe_image(image: Image.Image) -> str:
    client = _get_client()
    image = _prepare_image(image)

    for model in _model_chain():
        for attempt in range(ATTEMPTS_PER_MODEL):
            try:
                response = client.models.generate_content(
                    model=model,
                    contents=[PROMPT, image],
                )
            except errors.APIError as exc:
                code = getattr(exc, "code", None)

                # Real mistakes (bad key, bad request) should fail immediately.
                if code not in RETRYABLE_CODES:
                    raise

                logger.warning(
                    "Gemini %s returned %s (attempt %d/%d)",
                    model, code, attempt + 1, ATTEMPTS_PER_MODEL,
                )

                # Wait before retrying: ~1s, ~2s (+ a little randomness).
                if attempt < ATTEMPTS_PER_MODEL - 1:
                    time.sleep(2 ** attempt + random.random())
                continue

            description = (response.text or "").strip()
            if not description:
                raise RuntimeError("Gemini returned an empty description")
            return description

        logger.warning("Giving up on model %s, trying next fallback", model)

    raise GeminiBusyError("Gemini is overloaded or rate-limited right now")