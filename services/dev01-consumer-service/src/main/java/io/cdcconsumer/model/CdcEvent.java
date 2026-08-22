package io.cdcconsumer.model;

import lombok.Builder;
import lombok.Data;
import java.time.Instant;

/**
 * Represents a CDC event to be inserted into ClickHouse.
 * Maps to the cdc_events table schema.
 */
@Data
@Builder
public class CdcEvent {
    
    /**
     * Event timestamp (from Debezium ts_ms)
     */
    private Instant eventTime;
    
    /**
     * Database name
     */
    private String database;
    
    /**
     * Schema name
     */
    private String schema;
    
    /**
     * Table name
     */
    private String tableName;
    
    /**
     * Primary key (JSON representation)
     */
    private String primaryKey;
    
    /**
     * Operation type: r, c, u, d
     */
    private String operation;
    
    /**
     * Before state (JSON string)
     */
    private String beforeJson;
    
    /**
     * After state (JSON string)
     */
    private String afterJson;
    
    /**
     * Transaction ID
     */
    private String transactionId;
    
    /**
     * Log Sequence Number
     */
    private String lsn;
    
    /**
     * Raw Debezium event (JSON string)
     */
    private String rawEvent;
}
