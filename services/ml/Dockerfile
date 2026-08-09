FROM python:3.12-slim

WORKDIR /app

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Copy pyproject.toml and install dependencies
COPY pyproject.toml .
RUN uv pip install --system --no-cache pandas>=2.0.0 numpy>=1.24.0 scikit-learn>=1.3.0 clickhouse-connect>=0.6.0

# Copy model files and inference script
COPY anomaly_detection_pipeline.pkl .
COPY model_config.json .
COPY inference.py .

# Run the inference job
CMD ["python", "inference.py"]
