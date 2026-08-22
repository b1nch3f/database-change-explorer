package io.cdcconsumer;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * Main application class for CDC Kafka Consumer.
 * Consumes Debezium CDC events from Kafka and writes to ClickHouse.
 */
@SpringBootApplication
@EnableScheduling
public class CdcConsumerApplication {

    public static void main(String[] args) {
        SpringApplication.run(CdcConsumerApplication.class, args);
    }
}
