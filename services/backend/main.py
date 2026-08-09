"""
FastAPI Backend for Database Change Explorer
Provides REST APIs for CDC events and anomaly detections from ClickHouse
"""
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from clickhouse_connect import get_client
from typing import Optional, List, Dict, Any
from datetime import datetime, timedelta
from pydantic import BaseModel
import os

app = FastAPI(
    title="Database Change Explorer API",
    description="REST API for CDC events and ML anomaly detections",
    version="1.0.0"
)

# CORS middleware for Next.js frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify your frontend domain
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ClickHouse connection
CLICKHOUSE_HOST = os.getenv("CLICKHOUSE_HOST", "clickhouse")
CLICKHOUSE_PORT = int(os.getenv("CLICKHOUSE_PORT", "8123"))
CLICKHOUSE_USER = os.getenv("CLICKHOUSE_USER", "default")
CLICKHOUSE_PASSWORD = os.getenv("CLICKHOUSE_PASSWORD", "clickhouse123")
CLICKHOUSE_DATABASE = os.getenv("CLICKHOUSE_DATABASE", "cdc_events")

def get_clickhouse_client():
    """Get ClickHouse client connection"""
    return get_client(
        host=CLICKHOUSE_HOST,
        port=CLICKHOUSE_PORT,
        username=CLICKHOUSE_USER,
        password=CLICKHOUSE_PASSWORD,
        database=CLICKHOUSE_DATABASE
    )

# Response models
class CDCEvent(BaseModel):
    event_time: datetime
    table_name: str
    operation_type: str
    primary_key: str
    material_id: Optional[str]
    before_data: Optional[Dict[str, Any]]
    after_data: Optional[Dict[str, Any]]

class CDCStats(BaseModel):
    total_events: int
    creates: int
    updates: int
    deletes: int
    reads: int
    event_rate: float

class AnomalyDetection(BaseModel):
    detection_id: str
    event_time: datetime
    material_id: str
    anomaly_score: float
    is_anomaly: int
    gross_weight: Optional[float]
    net_weight: Optional[float]
    volume: Optional[float]
    length: Optional[float]
    width: Optional[float]
    height: Optional[float]
    model_version: str
    detected_at: datetime

class AnomalyStats(BaseModel):
    total_anomalies: int
    avg_score: float
    min_score: float
    max_score: float

@app.get("/")
async def root():
    """API root endpoint"""
    return {
        "message": "Database Change Explorer API",
        "version": "1.0.0",
        "endpoints": {
            "cdc_events": "/api/cdc/events",
            "cdc_stats": "/api/cdc/stats",
            "cdc_timeline": "/api/cdc/timeline",
            "anomalies": "/api/anomalies",
            "anomaly_stats": "/api/anomalies/stats"
        }
    }

@app.get("/health")
async def health():
    """Health check endpoint"""
    try:
        client = get_clickhouse_client()
        result = client.query("SELECT 1")
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Database connection failed: {str(e)}")

@app.get("/api/cdc/events")
async def get_cdc_events(
    time_range: str = Query("7d", description="Time range: 1h, 6h, 24h, 7d, 30d"),
    limit: int = Query(100, ge=1, le=1000),
    offset: int = Query(0, ge=0)
):
    """Get recent CDC events"""
    try:
        client = get_clickhouse_client()
        
        # Parse time range
        time_map = {"5m": 0.083, "15m": 0.25, "30m": 0.5, "1h": 1, "6h": 6, "24h": 24, "7d": 168, "30d": 720}
        hours = time_map.get(time_range, 168)
        
        query = f"""
        SELECT 
            event_time,
            table_name,
            CASE operation 
                WHEN 'c' THEN 'CREATE'
                WHEN 'u' THEN 'UPDATE'
                WHEN 'd' THEN 'DELETE'
                WHEN 'r' THEN 'READ'
                ELSE 'UNKNOWN'
            END as operation_type,
            primary_key,
            JSONExtractString(after_json, 'matnr') as material_id,
            before_json,
            after_json
        FROM cdc_events
        WHERE event_time >= now() - INTERVAL {hours} HOUR
        ORDER BY event_time DESC
        LIMIT {limit} OFFSET {offset}
        """
        
        result = client.query(query)
        
        events = []
        for row in result.result_rows:
            events.append({
                "event_time": row[0].isoformat() if row[0] else None,
                "table_name": row[1],
                "operation_type": row[2],
                "primary_key": row[3],
                "material_id": row[4] if row[4] else None,
                "before_data": row[5],
                "after_data": row[6]
            })
        
        return {"events": events, "count": len(events)}
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/cdc/stats")
async def get_cdc_stats(
    time_range: str = Query("7d", description="Time range: 5m, 15m, 30m, 1h, 6h, 24h, 7d, 30d")
):
    """Get CDC event statistics"""
    try:
        client = get_clickhouse_client()
        
        time_map = {"5m": 0.083, "15m": 0.25, "30m": 0.5, "1h": 1, "6h": 6, "24h": 24, "7d": 168, "30d": 720}
        hours = time_map.get(time_range, 168)
        
        query = f"""
        SELECT 
            count() as total,
            countIf(operation = 'c') as creates,
            countIf(operation = 'u') as updates,
            countIf(operation = 'd') as deletes,
            countIf(operation = 'r') as reads,
            round(count() / (dateDiff('hour', min(event_time), max(event_time)) + 1), 2) as rate
        FROM cdc_events
        WHERE event_time >= now() - INTERVAL {hours} HOUR
        """
        
        result = client.query(query)
        row = result.result_rows[0]
        
        return {
            "total_events": row[0],
            "creates": row[1],
            "updates": row[2],
            "deletes": row[3],
            "reads": row[4],
            "event_rate": float(row[5]) if row[5] else 0.0
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/cdc/timeline")
async def get_cdc_timeline(
    time_range: str = Query("7d", description="Time range: 5m, 15m, 30m, 1h, 6h, 24h, 7d, 30d")
):
    """Get CDC events timeline grouped by operation type"""
    try:
        client = get_clickhouse_client()
        
        time_map = {"5m": 0.083, "15m": 0.25, "30m": 0.5, "1h": 1, "6h": 6, "24h": 24, "7d": 168, "30d": 720}
        hours = time_map.get(time_range, 168)
        
        # Use minute-by-minute granularity for 30m range
        if time_range in ["5m", "15m", "30m"]:
            interval_func = "toStartOfMinute"
        elif time_range == "1h":
            interval_func = "toStartOfFiveMinutes"
        elif time_range in ["6h", "24h", "7d"]:
            interval_func = "toStartOfFifteenMinutes"
        else:  # 30d
            interval_func = "toStartOfHour"
        
        query = f"""
        SELECT 
            {interval_func}(event_time) as time_bucket,
            CASE operation 
                WHEN 'c' THEN 'CREATE'
                WHEN 'u' THEN 'UPDATE'
                WHEN 'd' THEN 'DELETE'
                WHEN 'r' THEN 'READ'
                ELSE 'UNKNOWN'
            END as operation_type,
            count() as count
        FROM cdc_events
        WHERE event_time >= now() - INTERVAL {hours} HOUR
        GROUP BY time_bucket, operation_type
        ORDER BY time_bucket DESC, count DESC
        """
        
        result = client.query(query)
        
        timeline = []
        for row in result.result_rows:
            timeline.append({
                "time": row[0].isoformat() if row[0] else None,
                "operation_type": row[1],
                "count": row[2]
            })
        
        return {"timeline": timeline}
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/anomalies")
async def get_anomalies(
    time_range: str = Query("7d", description="Time range: 5m, 15m, 30m, 1h, 6h, 24h, 7d, 30d"),
    limit: int = Query(100, ge=1, le=1000),
    offset: int = Query(0, ge=0)
):
    """Get detected anomalies"""
    try:
        client = get_clickhouse_client()
        
        time_map = {"5m": 0.083, "15m": 0.25, "30m": 0.5, "1h": 1, "6h": 6, "24h": 24, "7d": 168, "30d": 720}
        hours = time_map.get(time_range, 168)
        
        query = f"""
        SELECT 
            toString(a.detection_id) as detection_id,
            a.event_time,
            a.material_id,
            a.anomaly_score,
            a.is_anomaly,
            toFloat64OrNull(JSONExtractString(a.features_json, 'brgew')) as gross_weight,
            toFloat64OrNull(JSONExtractString(a.features_json, 'ntgew')) as net_weight,
            toFloat64OrNull(JSONExtractString(a.features_json, 'volum')) as volume,
            toFloat64OrNull(JSONExtractString(a.features_json, 'laeng')) as length,
            toFloat64OrNull(JSONExtractString(a.features_json, 'breit')) as width,
            toFloat64OrNull(JSONExtractString(a.features_json, 'hoehe')) as height,
            a.model_version,
            a.detected_at
        FROM anomaly_detections a
        WHERE a.is_anomaly = 1 
          AND a.detected_at >= now() - INTERVAL {hours} HOUR
        ORDER BY a.anomaly_score ASC
        LIMIT {limit} OFFSET {offset}
        """
        
        result = client.query(query)
        
        anomalies = []
        for row in result.result_rows:
            anomalies.append({
                "detection_id": row[0],
                "event_time": row[1].isoformat() if row[1] else None,
                "material_id": row[2],
                "anomaly_score": float(row[3]),
                "is_anomaly": row[4],
                "gross_weight": row[5],
                "net_weight": row[6],
                "volume": row[7],
                "length": row[8],
                "width": row[9],
                "height": row[10],
                "model_version": row[11],
                "detected_at": row[12].isoformat() if row[12] else None
            })
        
        return {"anomalies": anomalies, "count": len(anomalies)}
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/anomalies/stats")
async def get_anomaly_stats(
    time_range: str = Query("7d", description="Time range: 5m, 15m, 30m, 1h, 6h, 24h, 7d, 30d")
):
    """Get anomaly detection statistics"""
    try:
        client = get_clickhouse_client()
        
        time_map = {"1h": 1, "6h": 6, "24h": 24, "7d": 168, "30d": 720}
        hours = time_map.get(time_range, 168)
        
        query = f"""
        SELECT 
            count() as total,
            round(avg(anomaly_score), 4) as avg_score,
            min(anomaly_score) as min_score,
            max(anomaly_score) as max_score
        FROM anomaly_detections
        WHERE is_anomaly = 1 
          AND detected_at >= now() - INTERVAL {hours} HOUR
        """
        
        result = client.query(query)
        row = result.result_rows[0]
        
        return {
            "total_anomalies": row[0],
            "avg_score": float(row[1]) if row[1] else 0.0,
            "min_score": float(row[2]) if row[2] else 0.0,
            "max_score": float(row[3]) if row[3] else 0.0
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/anomalies/timeline")
async def get_anomaly_timeline(
    time_range: str = Query("7d", description="Time range: 5m, 15m, 30m, 1h, 6h, 24h, 7d, 30d"),
    interval: str = Query("hour", description="Aggregation interval: hour, day")
):
    """Get anomaly detections timeline"""
    try:
        client = get_clickhouse_client()
        
        time_map = {"5m": 0.083, "15m": 0.25, "30m": 0.5, "1h": 1, "6h": 6, "24h": 24, "7d": 168, "30d": 720}
        hours = time_map.get(time_range, 168)
        
        interval_func = "toStartOfHour" if interval == "hour" else "toStartOfDay"
        
        query = f"""
        SELECT 
            {interval_func}(detected_at) as time_bucket,
            count() as anomaly_count
        FROM anomaly_detections
        WHERE is_anomaly = 1 
          AND detected_at >= now() - INTERVAL {hours} HOUR
        GROUP BY time_bucket
        ORDER BY time_bucket DESC
        """
        
        result = client.query(query)
        
        timeline = []
        for row in result.result_rows:
            timeline.append({
                "time": row[0].isoformat() if row[0] else None,
                "count": row[1]
            })
        
        return {"timeline": timeline}
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
