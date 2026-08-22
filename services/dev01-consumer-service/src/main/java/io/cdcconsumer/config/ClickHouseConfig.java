package io.cdcconsumer.config;

import com.clickhouse.jdbc.ClickHouseDataSource;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import javax.sql.DataSource;
import java.sql.SQLException;
import java.util.Properties;

/**
 * ClickHouse JDBC configuration.
 */
@Slf4j
@Configuration
public class ClickHouseConfig {

    @Value("${clickhouse.url}")
    private String url;

    @Value("${clickhouse.username}")
    private String username;

    @Value("${clickhouse.password}")
    private String password;

    @Bean
    public DataSource clickHouseDataSource() throws SQLException {
        Properties properties = new Properties();
        properties.setProperty("user", username);
        properties.setProperty("password", password);
        properties.setProperty("socket_timeout", "300000");
        properties.setProperty("connect_timeout", "10000");
        
        log.info("Initializing ClickHouse DataSource with URL: {}", url);
        return new ClickHouseDataSource(url, properties);
    }
}
