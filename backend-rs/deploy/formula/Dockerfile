# Handwritten formula -> LaTeX (Pix2Text MFR, MIT, ONNX on CPU). Loopback only;
# octonotes-api sends it a PNG of the selected ink.
FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu
# rapidocr 3.10 dropped a function cnstd 1.2.8 imports.
RUN pip install --no-cache-dir pix2text==1.1.7 cnstd==1.2.8 rapidocr==3.9.2 fastapi==0.115.6 uvicorn==0.34.0
COPY app.py /app/app.py
# The model is fetched at build time, so the first request is quick.
RUN python -c "from pix2text import LatexOCR; LatexOCR()"
EXPOSE 8000
CMD ["uvicorn", "app:app", "--app-dir", "/app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
