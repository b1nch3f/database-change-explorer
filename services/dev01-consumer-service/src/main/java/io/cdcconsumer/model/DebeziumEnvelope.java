package io.cdcconsumer.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.databind.JsonNode;
import lombok.Data;

/**
 * Represents the Debezium CDC event envelope structure.
 * 
 * Example event:
 * {
 *   "before": {...},
 *   "after": {...},
 *   "source": {...},
 *   "op": "c",
 *   "ts_ms": 1627890123456
 * }
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class DebeziumEnvelope {
    
    /**
     * State before the change (null for CREATE operations)
     */
    private JsonNode before;
    
    /**
     * State after the change (null for DELETE operations)
     */
    private JsonNode after;
    
    /**
     * Source metadata (database, table, transaction info)
     */
    private DebeziumSource source;
    
    /**
     * Operation type:
     * - r: read (snapshot)
     * - c: create (insert)
     * - u: update
     * - d: delete
     */
    private String op;
    
    /**
     * Timestamp in milliseconds since epoch
     */
    @JsonProperty("ts_ms")
    private Long tsMs;
    
    /**
     * Transaction metadata
     */
    private JsonNode transaction;
}
