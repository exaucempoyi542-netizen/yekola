FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# LibreOffice Impress : conversion PPT/PPTX → PDF (lecture native mobile)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    default-libmysqlclient-dev \
    pkg-config \
    libreoffice-impress \
    libreoffice-java-common \
    fonts-dejavu-core \
    fonts-liberation \
    && rm -rf /var/lib/apt/lists/*

COPY backend/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY backend/ /app/

RUN mkdir -p /app/staticfiles /app/media

EXPOSE 8080

CMD ["python", "entrypoint.py"]
