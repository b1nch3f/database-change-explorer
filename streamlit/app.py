import streamlit as st
import requests
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from datetime import datetime

# Backend API URL - using port-forwarded backend
BACKEND_URL = "http://localhost:8000"

# Page config
st.set_page_config(
    page_title="Database Change Explorer",
    page_icon="📊",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Sidebar navigation
st.sidebar.title("📊 Database Change Explorer")
page = st.sidebar.radio("Navigate", ["🏠 Home", "📝 CDC Events", "⚠️ Anomaly Detection"])

if page == "🏠 Home":
    st.title("Database Change Explorer")
    st.markdown("""
    ## Welcome to the Database Change Explorer Dashboard
    
    This application provides real-time monitoring of database changes and anomaly detection.
    
    ### Features:
    - **CDC Events**: Monitor all database change events (CREATE, UPDATE, DELETE, READ)
    - **Anomaly Detection**: ML-powered detection of unusual data patterns
    
    ### Architecture:
    - PostgreSQL with logical replication
    - Debezium for change data capture
    - Kafka/Redpanda for event streaming
    - ClickHouse for analytics storage
    - FastAPI backend for REST API
    - Streamlit for visualization
    
    Use the sidebar to navigate between dashboards.
    """)

elif page == "📝 CDC Events":
    st.title("CDC Events Dashboard")
    
    # Controls
    col1, col2, col3 = st.columns([2, 2, 1])
    with col1:
        time_range = st.selectbox("Time Range", ["1h", "6h", "12h", "24h"], index=0)
    with col2:
        auto_refresh = st.checkbox("Auto-refresh (30s)", value=True)
    with col3:
        if st.button("🔄 Refresh"):
            st.rerun()
    
    # Fetch data from backend
    try:
        # Stats
        stats_response = requests.get(f"{BACKEND_URL}/api/cdc/stats?time_range={time_range}")
        stats_response.raise_for_status()
        stats = stats_response.json()
        
        # Events
        events_response = requests.get(f"{BACKEND_URL}/api/cdc/events?time_range={time_range}&limit=50")
        events_response.raise_for_status()
        events_data = events_response.json()
        
        # Timeline
        timeline_response = requests.get(f"{BACKEND_URL}/api/cdc/timeline?time_range={time_range}")
        timeline_response.raise_for_status()
        timeline_data = timeline_response.json()
        
        # Display stats
        st.subheader("Statistics")
        col1, col2, col3, col4, col5, col6 = st.columns(6)
        with col1:
            st.metric("Total Events", f"{stats['total_events']:,}")
        with col2:
            st.metric("Event Rate", f"{stats['event_rate']:.1f}/hr")
        with col3:
            st.metric("CREATE", stats['creates'])
        with col4:
            st.metric("UPDATE", stats['updates'])
        with col5:
            st.metric("DELETE", stats['deletes'])
        with col6:
            st.metric("READ", stats['reads'])
        
        # Timeline chart
        st.subheader("Events Over Time")
        if timeline_data['timeline']:
            df_timeline = pd.DataFrame(timeline_data['timeline'])
            df_timeline['time'] = pd.to_datetime(df_timeline['time'])
            
            # Filter out zero counts - only show dots where events actually occurred
            df_timeline = df_timeline[df_timeline['count'] > 0]
            
            fig = go.Figure()
            colors = {'CREATE': '#10b981', 'UPDATE': '#3b82f6', 'DELETE': '#ef4444', 'READ': '#8b5cf6'}
            for op in ['CREATE', 'UPDATE', 'DELETE', 'READ']:
                df_op = df_timeline[df_timeline['operation_type'] == op]
                if not df_op.empty:
                    fig.add_trace(go.Scatter(
                        x=df_op['time'],
                        y=df_op['count'],
                        mode='markers',
                        name=op,
                        marker=dict(color=colors.get(op, '#888888'), size=10)
                    ))
            
            fig.update_layout(
                xaxis_title="Time",
                yaxis_title="Count",
                hovermode='x unified',
                height=400
            )
            st.plotly_chart(fig, use_container_width=True)
        else:
            st.info("No timeline data available")
        
        # Recent events table
        st.subheader("Recent Events")
        if events_data['events']:
            df_events = pd.DataFrame(events_data['events'])
            df_events['event_time'] = pd.to_datetime(df_events['event_time'])
            df_events = df_events.sort_values('event_time', ascending=False)
            
            # Format for display
            display_df = df_events[['event_time', 'operation_type', 'table_name', 'material_id', 'primary_key']].copy()
            display_df['event_time'] = display_df['event_time'].dt.strftime('%Y-%m-%d %H:%M:%S')
            
            st.dataframe(
                display_df,
                column_config={
                    "event_time": "Time",
                    "operation_type": "Operation",
                    "table_name": "Table",
                    "material_id": "Material ID",
                    "primary_key": "Primary Key"
                },
                hide_index=True,
                use_container_width=True
            )
        else:
            st.info("No events available")
            
    except requests.exceptions.RequestException as e:
        st.error(f"Failed to fetch data from backend: {e}")
    
    if auto_refresh:
        import time
        time.sleep(30)
        st.rerun()

elif page == "⚠️ Anomaly Detection":
    st.title("Anomaly Detection Dashboard")
    
    # Controls
    col1, col2, col3 = st.columns([2, 2, 1])
    with col1:
        time_range = st.selectbox("Time Range", ["1h", "6h", "12h", "24h"], index=0)
    with col2:
        auto_refresh = st.checkbox("Auto-refresh (30s)", value=True)
    with col3:
        if st.button("🔄 Refresh"):
            st.rerun()
    
    # Fetch data from backend
    try:
        # Stats
        stats_response = requests.get(f"{BACKEND_URL}/api/anomalies/stats?time_range={time_range}")
        stats_response.raise_for_status()
        stats = stats_response.json()
        
        # Anomalies
        anomalies_response = requests.get(f"{BACKEND_URL}/api/anomalies?time_range={time_range}&limit=50")
        anomalies_response.raise_for_status()
        anomalies_data = anomalies_response.json()
        
        # Timeline
        timeline_response = requests.get(f"{BACKEND_URL}/api/anomalies/timeline?time_range={time_range}")
        timeline_response.raise_for_status()
        timeline_data = timeline_response.json()
        
        # Display stats
        st.subheader("Statistics")
        col1, col2, col3, col4 = st.columns(4)
        with col1:
            st.metric("Total Anomalies", stats['total_anomalies'], delta=None, delta_color="inverse")
        with col2:
            st.metric("Avg Score", f"{stats['avg_score']:.4f}")
        with col3:
            st.metric("Min Score", f"{stats['min_score']:.4f}")
        with col4:
            st.metric("Max Score", f"{stats['max_score']:.4f}")
        
        # Timeline chart
        st.subheader("Anomaly Detections Over Time")
        if timeline_data['timeline']:
            df_timeline = pd.DataFrame(timeline_data['timeline'])
            df_timeline['time'] = pd.to_datetime(df_timeline['time'])
            df_timeline = df_timeline.sort_values('time')
            
            fig = px.scatter(
                df_timeline, 
                x='time', 
                y='count'
            )
            fig.update_traces(marker=dict(color='#ef4444', size=10))
            fig.update_layout(
                xaxis_title="Time",
                yaxis_title="Anomaly Count",
                hovermode='x',
                height=400
            )
            st.plotly_chart(fig, use_container_width=True)
        else:
            st.info("No timeline data available")
        
        # Anomaly score vs volume scatter plot
        st.subheader("Anomaly Score vs Volume")
        if anomalies_data['anomalies']:
            df_anomalies = pd.DataFrame(anomalies_data['anomalies'])
            
            fig = px.scatter(
                df_anomalies,
                x='volume',
                y='anomaly_score',
                color='material_id',
                hover_data=['gross_weight', 'net_weight', 'detected_at'],
                title=""
            )
            fig.update_traces(marker=dict(size=10))
            fig.update_layout(
                xaxis_title="Volume",
                yaxis_title="Anomaly Score",
                height=400
            )
            st.plotly_chart(fig, use_container_width=True)
        else:
            st.info("No anomalies detected")
        
        # Detected anomalies table
        st.subheader("Detected Anomalies")
        if anomalies_data['anomalies']:
            df_anomalies = pd.DataFrame(anomalies_data['anomalies'])
            df_anomalies['detected_at'] = pd.to_datetime(df_anomalies['detected_at'])
            df_anomalies = df_anomalies.sort_values('detected_at', ascending=False)
            
            # Format for display
            display_df = df_anomalies[[
                'detected_at', 'material_id', 'anomaly_score', 
                'gross_weight', 'net_weight', 'volume', 
                'length', 'width', 'height'
            ]].copy()
            display_df['detected_at'] = display_df['detected_at'].dt.strftime('%Y-%m-%d %H:%M:%S')
            
            st.dataframe(
                display_df,
                column_config={
                    "detected_at": "Detected At",
                    "material_id": "Material ID",
                    "anomaly_score": st.column_config.NumberColumn("Anomaly Score", format="%.4f"),
                    "gross_weight": st.column_config.NumberColumn("Gross Weight", format="%.2f"),
                    "net_weight": st.column_config.NumberColumn("Net Weight", format="%.2f"),
                    "volume": st.column_config.NumberColumn("Volume", format="%.2f"),
                    "length": st.column_config.NumberColumn("Length", format="%.2f"),
                    "width": st.column_config.NumberColumn("Width", format="%.2f"),
                    "height": st.column_config.NumberColumn("Height", format="%.2f")
                },
                hide_index=True,
                use_container_width=True
            )
        else:
            st.info("No anomalies detected in this time range")
            
    except requests.exceptions.RequestException as e:
        st.error(f"Failed to fetch data from backend: {e}")
    
    if auto_refresh:
        import time
        time.sleep(30)
        st.rerun()
