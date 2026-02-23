package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/ClickHouse/clickhouse-go/v2"
	"github.com/IBM/sarama"
	"github.com/hjson/hjson-go/v4"
)

type Config struct {
	ClickHouse struct {
		Host         string `json:"host"`
		Port         int    `json:"port"`
		Database     string `json:"database"`
		Username     string `json:"username"`
		Password     string `json:"password"`
		Secure       bool   `json:"secure"`
		Protocol     string `json:"protocol"`
		MaxOpenConns int    `json:"maxOpenConns"`
		AsyncInsert  bool   `json:"asyncInsert"`
	} `json:"clickhouse"`
	Kafka struct {
		Brokers    []string `json:"brokers"`
		Security   map[string]string `json:"security"`
		Properties map[string]interface{} `json:"properties"`
	} `json:"kafka"`
	Tasks []Task `json:"tasks"`
	LogLevel string `json:"logLevel"`
	LogTrace bool   `json:"logTrace"`
}

type Task struct {
	Name          string `json:"name"`
	Topic         string `json:"topic"`
	ConsumerGroup string `json:"consumerGroup"`
	Earliest      bool   `json:"earliest"`
	Parser        string `json:"parser"`
	AutoSchema    bool   `json:"autoSchema"`
	TableName     string `json:"tableName"`
	Dims          []Dim  `json:"dims"`
	BufferSize    int    `json:"bufferSize"`
	FlushInterval int    `json:"flushInterval"`
}

type Dim struct {
	Name string `json:"name"`
	Type string `json:"type"`
}

type DebeziumMessage struct {
	Before    interface{} `json:"before"`
	After     interface{} `json:"after"`
	Source    map[string]interface{} `json:"source"`
	Op        string      `json:"op"`
	TsMs      int64       `json:"ts_ms"`
	Schema    interface{} `json:"schema"`
}

type SinkConnector struct {
	config     *Config
	clickhouse clickhouse.Conn
	consumers  map[string]sarama.ConsumerGroup
	buffers    map[string][]map[string]interface{}
	mutex      sync.RWMutex
	ctx        context.Context
	cancel     context.CancelFunc
}

func main() {
	configData, err := os.ReadFile("config.hjson")
	if err != nil {
		log.Fatal("Error reading config file:", err)
	}

	var config Config
	if err := hjson.Unmarshal(configData, &config); err != nil {
		log.Fatal("Error parsing config:", err)
	}

	connector := &SinkConnector{
		config:    &config,
		consumers: make(map[string]sarama.ConsumerGroup),
		buffers:   make(map[string][]map[string]interface{}),
	}

	connector.ctx, connector.cancel = context.WithCancel(context.Background())

	// Initialize ClickHouse connection
	if err := connector.initClickHouse(); err != nil {
		log.Fatal("Error initializing ClickHouse:", err)
	}

	// Create tables
	if err := connector.createTables(); err != nil {
		log.Fatal("Error creating tables:", err)
	}

	// Start consumers for each task
	var wg sync.WaitGroup
	for _, task := range config.Tasks {
		wg.Add(1)
		go func(t Task) {
			defer wg.Done()
			if err := connector.startConsumer(t); err != nil {
				log.Printf("Error starting consumer for %s: %v", t.Name, err)
			}
		}(task)
	}

	// Start flush routine
	wg.Add(1)
	go func() {
		defer wg.Done()
		connector.flushRoutine()
	}()

	// Wait for interrupt signal
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	<-sigChan

	log.Println("Shutting down...")
	connector.cancel()
	wg.Wait()
	
	if err := connector.clickhouse.Close(); err != nil {
		log.Printf("Error closing ClickHouse connection: %v", err)
	}
}

func (sc *SinkConnector) initClickHouse() error {
	options := &clickhouse.Options{
		Addr: []string{fmt.Sprintf("%s:%d", sc.config.ClickHouse.Host, sc.config.ClickHouse.Port)},
		Auth: clickhouse.Auth{
			Database: sc.config.ClickHouse.Database,
			Username: sc.config.ClickHouse.Username,
			Password: sc.config.ClickHouse.Password,
		},
		Settings: clickhouse.Settings{
			"async_insert": 1,
		},
		MaxOpenConns: sc.config.ClickHouse.MaxOpenConns,
	}

	conn, err := clickhouse.Open(options)
	if err != nil {
		return err
	}

	if err := conn.Ping(context.Background()); err != nil {
		return err
	}

	sc.clickhouse = conn
	log.Println("ClickHouse connection established")
	return nil
}

func (sc *SinkConnector) createTables() error {
	for _, task := range sc.config.Tasks {
		query := fmt.Sprintf(`
			CREATE TABLE IF NOT EXISTS %s (
				id UInt32,
				data String,
				op String,
				source_ts_ms UInt64,
				source_db String,
				source_table String,
				_raw_message String,
				_ingestion_time DateTime DEFAULT now()
			) ENGINE = MergeTree()
			ORDER BY (id, _ingestion_time)
		`, task.TableName)

		if err := sc.clickhouse.Exec(context.Background(), query); err != nil {
			return fmt.Errorf("failed to create table %s: %v", task.TableName, err)
		}
		log.Printf("Created/verified table: %s", task.TableName)
	}
	return nil
}

func (sc *SinkConnector) startConsumer(task Task) error {
	config := sarama.NewConfig()
	config.Consumer.Group.Rebalance.Strategy = sarama.BalanceStrategyRoundRobin
	config.Consumer.Offsets.Initial = sarama.OffsetNewest
	if task.Earliest {
		config.Consumer.Offsets.Initial = sarama.OffsetOldest
	}

	consumer, err := sarama.NewConsumerGroup(sc.config.Kafka.Brokers, task.ConsumerGroup, config)
	if err != nil {
		return err
	}

	sc.consumers[task.Name] = consumer

	handler := &ConsumerGroupHandler{
		connector: sc,
		task:      task,
	}

	for {
		select {
		case <-sc.ctx.Done():
			return consumer.Close()
		default:
			if err := consumer.Consume(sc.ctx, []string{task.Topic}, handler); err != nil {
				log.Printf("Error in consumer %s: %v", task.Name, err)
				return err
			}
		}
	}
}

type ConsumerGroupHandler struct {
	connector *SinkConnector
	task      Task
}

func (h *ConsumerGroupHandler) Setup(sarama.ConsumerGroupSession) error   { return nil }
func (h *ConsumerGroupHandler) Cleanup(sarama.ConsumerGroupSession) error { return nil }

func (h *ConsumerGroupHandler) ConsumeClaim(session sarama.ConsumerGroupSession, claim sarama.ConsumerGroupClaim) error {
	for message := range claim.Messages() {
		var debeziumMsg DebeziumMessage
		if err := json.Unmarshal(message.Value, &debeziumMsg); err != nil {
			log.Printf("Error unmarshaling message: %v", err)
			session.MarkMessage(message, "")
			continue
		}

		data := h.transformMessage(debeziumMsg, string(message.Value))
		h.connector.addToBuffer(h.task.TableName, data)

		session.MarkMessage(message, "")
	}
	return nil
}

func (h *ConsumerGroupHandler) transformMessage(msg DebeziumMessage, rawMessage string) map[string]interface{} {
	data := make(map[string]interface{})

	// Pick the row: use 'after' for insert/update/snapshot, 'before' for delete
	var row map[string]interface{}
	if msg.After != nil {
		if m, ok := msg.After.(map[string]interface{}); ok {
			row = m
		}
	}
	if row == nil && msg.Before != nil {
		if m, ok := msg.Before.(map[string]interface{}); ok {
			row = m
		}
	}

	// id
	if row != nil {
		if id, ok := row["id"]; ok {
			switch v := id.(type) {
			case float64:
				data["id"] = uint32(v)
			default:
				data["id"] = uint32(0)
			}
		}
	} else {
		data["id"] = uint32(0)
	}

	// data — full row as JSON string
	if row != nil {
		if b, err := json.Marshal(row); err == nil {
			data["data"] = string(b)
		}
	} else {
		data["data"] = ""
	}

	// op
	data["op"] = msg.Op

	// source_ts_ms
	if msg.TsMs > 0 {
		data["source_ts_ms"] = uint64(msg.TsMs)
	} else {
		data["source_ts_ms"] = uint64(0)
	}

	// source_db / source_table
	if msg.Source != nil {
		if db, ok := msg.Source["db"].(string); ok {
			data["source_db"] = db
		} else {
			data["source_db"] = ""
		}
		if tbl, ok := msg.Source["table"].(string); ok {
			data["source_table"] = tbl
		} else {
			data["source_table"] = ""
		}
	} else {
		data["source_db"] = ""
		data["source_table"] = ""
	}

	data["_raw_message"] = rawMessage

	return data
}

func (sc *SinkConnector) addToBuffer(tableName string, data map[string]interface{}) {
	sc.mutex.Lock()
	defer sc.mutex.Unlock()
	
	if sc.buffers[tableName] == nil {
		sc.buffers[tableName] = make([]map[string]interface{}, 0)
	}
	
	sc.buffers[tableName] = append(sc.buffers[tableName], data)
	
	// Check if buffer size exceeded
	for _, task := range sc.config.Tasks {
		if task.TableName == tableName && len(sc.buffers[tableName]) >= task.BufferSize {
			go sc.flushBuffer(tableName)
			break
		}
	}
}

func (sc *SinkConnector) flushRoutine() {
	for _, task := range sc.config.Tasks {
		go func(t Task) {
			ticker := time.NewTicker(time.Duration(t.FlushInterval) * time.Second)
			defer ticker.Stop()
			
			for {
				select {
				case <-sc.ctx.Done():
					return
				case <-ticker.C:
					sc.flushBuffer(t.TableName)
				}
			}
		}(task)
	}
}

func (sc *SinkConnector) flushBuffer(tableName string) {
	sc.mutex.Lock()
	data := sc.buffers[tableName]
	if len(data) == 0 {
		sc.mutex.Unlock()
		return
	}
	sc.buffers[tableName] = make([]map[string]interface{}, 0)
	sc.mutex.Unlock()
	
	if err := sc.insertBatch(tableName, data); err != nil {
		log.Printf("Error inserting batch for table %s: %v", tableName, err)
	} else {
		log.Printf("Inserted %d records into %s", len(data), tableName)
	}
}

func (sc *SinkConnector) insertBatch(tableName string, data []map[string]interface{}) error {
	if len(data) == 0 {
		return nil
	}
	
	query := fmt.Sprintf(`
		INSERT INTO %s (id, data, op, source_ts_ms, source_db, source_table, _raw_message)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	`, tableName)
	
	batch, err := sc.clickhouse.PrepareBatch(context.Background(), query)
	if err != nil {
		return err
	}
	
	for _, row := range data {
		err := batch.Append(
			row["id"],
			row["data"],
			row["op"],
			row["source_ts_ms"],
			row["source_db"],
			row["source_table"],
			row["_raw_message"],
		)
		if err != nil {
			return err
		}
	}
	
	return batch.Send()
}