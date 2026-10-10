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
 *
 * <p>Delivery is at-least-once: each poll's events are written to ClickHouse
 * before the poll is acknowledged. If the write fails, nothing is acknowledged
 * and the container redelivers the same records, so a crash or a ClickHouse
 * outage never loses events (it can duplicate them; dedupe on lsn downstream).
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class CdcKafkaConsumer {

    private final ClickHouseRepository clickHouseRepository;
    private final ObjectMapper objectMapper = new ObjectMapper();

    @Value("${clickhouse.batch-size}")
    private int batchSize;

    /**
     * Kafka listener that subscribes to topics matching the configured pattern.
     * Pattern is defined in application.yml: consumer.topic-pattern
     */
    @KafkaListener(
        topicPattern = "${consumer.topic-pattern}",
        containerFactory = "kafkaListenerContainerFactory"
    )
    public void consume(List<ConsumerRecord<String, String>> records, Acknowledgment ack) throws SQLException {
        log.debug("Received {} records from Kafka", records.size());

        List<CdcEvent> events = new ArrayList<>(records.size());
        for (ConsumerRecord<String, String> record : records) {
            if (record.value() == null) {
                // Tombstone after a delete: the delete event itself came just before it.
                continue;
            }
            try {
                CdcEvent event = parseDebeziumEvent(record);
                if (event != null) {
                    events.add(event);
                }
            } catch (Exception e) {
                log.error("Failed to parse Debezium event from topic {}, partition {}, offset {}: {}",
                        record.topic(), record.partition(), record.offset(), e.getMessage(), e);
                // Skip unparseable records; they would fail the same way on redelivery.
            }
        }

        // Write everything from this poll, then acknowledge. An exception here
        // propagates without acknowledging, so the records are redelivered.
        for (int i = 0; i < events.size(); i += batchSize) {
            clickHouseRepository.insertBatch(events.subList(i, Math.min(i + batchSize, events.size())));
        }
        ack.acknowledge();
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
}
