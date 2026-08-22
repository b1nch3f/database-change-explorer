package io.cdcconsumer.consumer;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.cdcconsumer.model.CdcEvent;
import io.cdcconsumer.model.DebeziumEnvelope;
import io.cdcconsumer.repository.ClickHouseRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.support.Acknowledgment;
import org.springframework.stereotype.Service;

import java.sql.SQLException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/**
 * Kafka consumer for CDC events.
 * Subscribes to topics matching the pattern and processes Debezium events.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class CdcKafkaConsumer {

    private final ClickHouseRepository clickHouseRepository;
    private final ObjectMapper objectMapper = new ObjectMapper();

    @Value("${clickhouse.batch-size}")
    private int batchSize;

    @Value("${clickhouse.batch-timeout-ms}")
    private long batchTimeoutMs;

    private final List<CdcEvent> eventBatch = new ArrayList<>();
    private long lastFlushTime = System.currentTimeMillis();

    /**
     * Kafka listener that subscribes to topics matching the configured pattern.
     * Pattern is defined in application.yml: consumer.topic-pattern
     */
    @KafkaListener(
        topicPattern = "${consumer.topic-pattern}",
        containerFactory = "kafkaListenerContainerFactory"
    )
    public void consume(List<ConsumerRecord<String, String>> records, Acknowledgment ack) {
        log.debug("Received {} records from Kafka", records.size());

        try {
            for (ConsumerRecord<String, String> record : records) {
                try {
                    CdcEvent event = parseDebeziumEvent(record);
                    if (event != null) {
                        synchronized (eventBatch) {
                            eventBatch.add(event);
                        }
                    }
                } catch (Exception e) {
                    log.error("Failed to parse Debezium event from topic {}, partition {}, offset {}: {}",
                            record.topic(), record.partition(), record.offset(), e.getMessage(), e);
                    // Continue processing other records
                }
            }

            // Check if we should flush the batch
            boolean shouldFlush = false;
            synchronized (eventBatch) {
                shouldFlush = eventBatch.size() >= batchSize || 
                             (System.currentTimeMillis() - lastFlushTime) >= batchTimeoutMs;
            }

            if (shouldFlush) {
                flushBatch();
            }

            // Acknowledge the Kafka records
            ack.acknowledge();

        } catch (Exception e) {
            log.error("Error processing Kafka records batch", e);
            // Don't acknowledge - records will be reprocessed
            throw e;
        }
    }

    /**
     * Parse a Debezium CDC event from Kafka record.
     */
    private CdcEvent parseDebeziumEvent(ConsumerRecord<String, String> record) throws Exception {
        String json = record.value();
        DebeziumEnvelope envelope = objectMapper.readValue(json, DebeziumEnvelope.class);

        // Extract event timestamp
        Instant eventTime = envelope.getTsMs() != null 
            ? Instant.ofEpochMilli(envelope.getTsMs())
            : Instant.now();

        // Extract primary key from after or before state
        JsonNode pkNode = envelope.getAfter() != null ? envelope.getAfter() : envelope.getBefore();
        String primaryKey = pkNode != null ? pkNode.toString() : "{}";

        // Convert JsonNode to JSON strings
        String beforeJson = envelope.getBefore() != null ? envelope.getBefore().toString() : null;
        String afterJson = envelope.getAfter() != null ? envelope.getAfter().toString() : null;

        return CdcEvent.builder()
                .eventTime(eventTime)
                .database(envelope.getSource().getDb())
                .schema(envelope.getSource().getSchema())
                .tableName(envelope.getSource().getTable())
                .primaryKey(primaryKey)
                .operation(envelope.getOp())
                .beforeJson(beforeJson)
                .afterJson(afterJson)
                .transactionId(envelope.getSource().getTxId())
                .lsn(envelope.getSource().getLsn())
                .rawEvent(json)
                .build();
    }

    /**
     * Flush accumulated events to ClickHouse.
     */
    private void flushBatch() {
        List<CdcEvent> eventsToInsert;
        synchronized (eventBatch) {
            if (eventBatch.isEmpty()) {
                return;
            }
            eventsToInsert = new ArrayList<>(eventBatch);
            eventBatch.clear();
            lastFlushTime = System.currentTimeMillis();
        }

        try {
            clickHouseRepository.insertBatch(eventsToInsert);
        } catch (SQLException e) {
            log.error("Failed to insert batch into ClickHouse, re-adding to batch", e);
            // Re-add events to batch for retry
            synchronized (eventBatch) {
                eventBatch.addAll(0, eventsToInsert);
            }
            throw new RuntimeException("ClickHouse insert failed", e);
        }
    }

    /**
     * Scheduled task to flush batch on timeout.
     */
    @org.springframework.scheduling.annotation.Scheduled(fixedDelay = 1000)
    public void scheduledFlush() {
        synchronized (eventBatch) {
            if (!eventBatch.isEmpty() && 
                (System.currentTimeMillis() - lastFlushTime) >= batchTimeoutMs) {
                flushBatch();
            }
        }
    }
}
