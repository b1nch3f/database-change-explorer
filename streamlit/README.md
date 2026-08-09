# Streamlit Dashboard

Local Streamlit dashboard for Database Change Explorer.

## Prerequisites

- Backend service port-forwarded to localhost:8000
- Python 3.12+ with uv installed

## Setup & Run

```powershell
# Install dependencies
uv pip install -r pyproject.toml

# Run streamlit
uv run streamlit run app.py
```

Or simply:

```powershell
streamlit run app.py
```

The dashboard will be available at http://localhost:8501

## Features

- **Home**: Overview of the system architecture
- **CDC Events**: Real-time CDC event monitoring with timeline charts
- **Anomaly Detection**: ML-powered anomaly detection dashboard
