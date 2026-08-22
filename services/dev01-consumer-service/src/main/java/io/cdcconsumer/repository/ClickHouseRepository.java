package io.cdcconsumer.repository;

import io.cdcconsumer.model.CdcEvent;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Repository;

import javax.sql.DataSource;
import java.sql.*;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Repository for inserting CDC events into ClickHouse.
 * Uses batch inserts for optimal performance.
 */
@Slf4j
@Repository
@RequiredArgsConstructor
public class ClickHouseRepository {

    private final DataSource dataSource;

    @Value("${clickhouse.batch-size}")
    private int batchSize;

    private final AtomicLong totalInserted = new AtomicLong(0);
    private final AtomicLong totalBatches = new AtomicLong(0);

    private static final String INSERT_SQL = """
        INSERT INTO cdc_events.cdc_events (
            event_time,
            database,
            schema,
            table_name,
            primary_key,
            operation,
            before_json,
            after_json,
            transaction_id,
            lsn,
            raw_event
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """;

    /**
     * Insert a batch of CDC events into ClickHouse.
     *
     * @param events List of events to insert
     * @throws SQLException if database error occurs
     */
    public void insertBatch(List<CdcEvent> events) throws SQLException {
        if (events == null || events.isEmpty()) {
            return;
        }

        long startTime = System.currentTimeMillis();
        
        try (Connection conn = dataSource.getConnection();
             PreparedStatement ps = conn.prepareStatement(INSERT_SQL)) {
            
            for (CdcEvent event : events) {
                ps.setTimestamp(1, Timestamp.from(event.getEventTime()));
                ps.setString(2, event.getDatabase());
                ps.setString(3, event.getSchema());
                ps.setString(4, event.getTableName());
                ps.setString(5, event.getPrimaryKey());
                ps.setString(6, event.getOperation());
                ps.setString(7, event.getBeforeJson());
                ps.setString(8, event.getAfterJson());
                ps.setString(9, event.getTransactionId());
                ps.setString(10, event.getLsn());
                ps.setString(11, event.getRawEvent());
                
                ps.addBatch();
            }
            
            ps.executeBatch();
            
            long inserted = totalInserted.addAndGet(events.size());
            long batches = totalBatches.incrementAndGet();
            long duration = System.currentTimeMillis() - startTime;
            
            log.info("Inserted batch of {} events into ClickHouse in {}ms. Total: {} events, {} batches",
                    events.size(), duration, inserted, batches);
            
        } catch (SQLException e) {
            log.error("Failed to insert batch of {} events into ClickHouse", events.size(), e);
            throw e;
        }
    }

    /**
     * Test database connectivity.
     *
     * @return true if connection successful
     */
    public boolean testConnection() {
        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery("SELECT 1")) {
            
            if (rs.next()) {
                log.info("ClickHouse connection test successful");
                return true;
            }
        } catch (SQLException e) {
            log.error("ClickHouse connection test failed", e);
        }
        return false;
    }

    /**
     * Get total number of events inserted (lifetime of application).
     */
    public long getTotalInserted() {
        return totalInserted.get();
    }

    /**
     * Get total number of batches processed (lifetime of application).
     */
    public long getTotalBatches() {
        return totalBatches.get();
    }
}
