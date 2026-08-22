package io.cdcconsumer.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

/**
 * Represents the Debezium source metadata.
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class DebeziumSource {
    
    /**
     * Database name
     */
    private String db;
    
    /**
     * Schema name
     */
    private String schema;
    
    /**
     * Table name
     */
    private String table;
    
    /**
     * Transaction ID
     */
    @JsonProperty("txId")
    private String txId;
    
    /**
     * Log Sequence Number (LSN)
     */
    private String lsn;
    
    /**
     * Timestamp in microseconds
     */
    @JsonProperty("ts_ms")
    private Long tsMs;
}
