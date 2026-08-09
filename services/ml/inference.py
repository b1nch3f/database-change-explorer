#!/usr/bin/env python3
"""
ML Inference Batch Job for MARA Anomaly Detection
Reads CDC events from ClickHouse, predicts anomalies, writes results back
"""

import pickle
import json
import logging
import uuid
from datetime import datetime
import pandas as pd
import clickhouse_connect

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
CLICKHOUSE_HOST = 'clickhouse'
CLICKHOUSE_PORT = 8123
CLICKHOUSE_USER = 'default'
CLICKHOUSE_PASSWORD = 'clickhouse123'
CLICKHOUSE_DATABASE = 'cdc_events'

BATCH_SIZE = 1000
JOB_NAME = 'anomaly_detection'


def load_model():
    """Load the trained pipeline from disk"""
    logger.info("Loading ML pipeline...")
    with open('anomaly_detection_pipeline.pkl', 'rb') as f:
        pipeline = pickle.load(f)
    
    with open('model_config.json', 'r') as f:
        config = json.load(f)
    
    logger.info(f"✓ Pipeline loaded: {config['model_version']}")
    logger.info(f"  Features: {config['features']}")
    return pipeline, config


def get_clickhouse_client():
    """Create ClickHouse client connection"""
    return clickhouse_connect.get_client(
        host=CLICKHOUSE_HOST,
        port=CLICKHOUSE_PORT,
        username=CLICKHOUSE_USER,
        password=CLICKHOUSE_PASSWORD,
        database=CLICKHOUSE_DATABASE
    )


def get_last_checkpoint(client):
    """Get the last processed timestamp from checkpoint table"""
    result = client.query(
        """
        SELECT last_processed_timestamp 
        FROM ml_job_checkpoints 
        WHERE job_name = %(job_name)s
        ORDER BY updated_at DESC
        LIMIT 1
        """,
        parameters={'job_name': JOB_NAME}
    )
    
    if result.row_count > 0:
        last_ts = result.first_row[0]
        logger.info(f"Last checkpoint: {last_ts}")
        return last_ts
    else:
        logger.info("No checkpoint found, starting from epoch")
        return '1970-01-01 00:00:00'


def fetch_new_events(client, last_checkpoint, features):
    """Fetch new CDC events since last checkpoint"""
    query = f"""
        SELECT 
            event_time,
            table_name,
            primary_key,
            after_json
        FROM cdc_events
        WHERE event_time >= %(last_ts)s
          AND operation IN ('c', 'u')
          AND table_name = 'mara'
        ORDER BY event_time
        LIMIT %(limit)s
    """
    
    result = client.query(
        query,
        parameters={
            'last_ts': last_checkpoint,
            'limit': BATCH_SIZE
        }
    )
    
    if result.row_count == 0:
        logger.info("No new events to process")
        return None
    
    # Convert to DataFrame
    df = pd.DataFrame(
        result.result_rows,
        columns=['event_time', 'table_name', 'primary_key', 'after_json']
    )
    
    logger.info(f"Fetched {len(df)} new events")
    return df


def extract_features(df, features):
    """Extract features from JSON for prediction"""
    # Parse JSON strings
    json_data = df['after_json'].apply(json.loads)
    
    # Extract features into DataFrame
    features_df = pd.DataFrame(json_data.tolist())[features]
    
    # Convert to float (pipeline will handle missing values)
    features_df = features_df.astype(float)
    
    return features_df


def predict_anomalies(pipeline, features_df):
    """Run predictions using the pipeline"""
    # Predict
    predictions = pipeline.predict(features_df)
    
    # Get anomaly scores
    scores = pipeline.named_steps['isolation_forest'].score_samples(
        pipeline.named_steps['imputer'].transform(features_df)
    )
    
    return predictions, scores


def insert_anomaly_detections(client, events_df, predictions, scores, model_version):
    """Insert anomaly detection results into ClickHouse"""
    # Check for existing detections to avoid duplicates
    existing_pairs = set()
    if len(events_df) > 0:
        # Get list of already processed (event_time, primary_key) pairs
        event_times = events_df['event_time'].tolist()
        primary_keys = events_df['primary_key'].tolist()
        
        # Query for existing detections
        existing_check = f"""
            SELECT event_time, primary_key
            FROM cdc_events.anomaly_detections
            WHERE (event_time, primary_key) IN (
                {','.join([f"('{et}', '{pk}')" for et, pk in zip(event_times, primary_keys)])}
            )
        """
        existing_result = client.query(existing_check)
        existing_pairs = {(row[0], row[1]) for row in existing_result.result_rows}
        
        logger.info(f"Found {len(existing_pairs)} already processed events")
    
    # Prepare data for insertion
    detections = []
    now = datetime.now()
    
    for idx, row in events_df.iterrows():
        # Skip if already processed
        event_pk_pair = (row['event_time'], row['primary_key'])
        if event_pk_pair in existing_pairs:
            continue
            
        json_data = json.loads(row['after_json'])
        
        detection = (
            str(uuid.uuid4()),  # detection_id
            row['event_time'],
            row['table_name'],
            json_data.get('matnr', ''),  # material_id
            row['primary_key'],
            float(scores[idx]),
            1 if predictions[idx] == -1 else 0,
            model_version,
            row['after_json'],  # Store features as JSON
            now  # detected_at
        )
        detections.append(detection)
    
    if len(detections) == 0:
        logger.info("No new detections to insert (all already processed)")
        return 0, 0
    
    # Insert into anomaly_detections table
    client.insert(
        'cdc_events.anomaly_detections',
        detections,
        column_names=[
            'detection_id', 'event_time', 'table_name', 'material_id', 'primary_key',
            'anomaly_score', 'is_anomaly', 'model_version', 'features_json', 'detected_at'
        ]
    )
    
    anomaly_count = sum(1 for p in predictions if p == -1)
    logger.info(f"✓ Inserted {len(detections)} predictions ({anomaly_count} anomalies)")
    
    return len(detections), anomaly_count


def update_checkpoint(client, max_event_time, processed_count, anomaly_count):
    """Update the checkpoint with latest processed timestamp"""
    client.command(
        """
        INSERT INTO ml_job_checkpoints 
        VALUES (%(job_name)s, %(last_ts)s, %(processed)s, %(anomalies)s, now64(3))
        """,
        parameters={
            'job_name': JOB_NAME,
            'last_ts': max_event_time,
            'processed': processed_count,
            'anomalies': anomaly_count
        }
    )
    logger.info(f"✓ Checkpoint updated: {max_event_time}")


def run_inference():
    """Main inference pipeline"""
    logger.info("="*80)
    logger.info("MARA Anomaly Detection - Batch Inference Job")
    logger.info("="*80)
    
    try:
        # Load model
        pipeline, config = load_model()
        features = config['features']
        model_version = config['model_version']
        
        # Connect to ClickHouse
        logger.info("Connecting to ClickHouse...")
        client = get_clickhouse_client()
        logger.info("✓ Connected to ClickHouse")
        
        # Get last checkpoint
        last_checkpoint = get_last_checkpoint(client)
        
        # Fetch new events
        events_df = fetch_new_events(client, last_checkpoint, features)
        
        if events_df is None:
            logger.info("✓ No work to do, exiting")
            return
        
        # Extract features
        logger.info("Extracting features...")
        features_df = extract_features(events_df, features)
        logger.info(f"✓ Extracted {len(features_df)} feature vectors")
        
        # Predict anomalies
        logger.info("Running predictions...")
        predictions, scores = predict_anomalies(pipeline, features_df)
        logger.info(f"✓ Predictions complete")
        
        # Insert results
        logger.info("Inserting anomaly detections...")
        processed_count, anomaly_count = insert_anomaly_detections(
            client, events_df, predictions, scores, model_version
        )
        
        # Update checkpoint with full precision (DateTime64(3))
        max_event_time = pd.Timestamp(events_df['event_time'].max())
        # Format with microseconds to preserve precision
        max_event_time_str = max_event_time.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]  # Keep milliseconds
        update_checkpoint(client, max_event_time_str, processed_count, anomaly_count)
        
        logger.info("="*80)
        logger.info(f"✓ Batch complete: {processed_count} processed, {anomaly_count} anomalies detected")
        logger.info("="*80)
        
    except Exception as e:
        logger.error(f"Error in inference pipeline: {e}", exc_info=True)
        raise


if __name__ == '__main__':
    run_inference()
