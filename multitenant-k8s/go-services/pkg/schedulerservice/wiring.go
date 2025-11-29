package schedulerservice

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
	"github.com/segmentio/kafka-go"
)

// KafkaQueue is a JobQueue implementation backed by Kafka.
type KafkaQueue struct {
	writer *kafka.Writer
}

// NewKafkaQueue constructs a Kafka-backed JobQueue.
func NewKafkaQueue(brokers []string, topic string) (*KafkaQueue, error) {
	if len(brokers) == 0 {
		return nil, fmt.Errorf("brokers must not be empty")
	}
	if topic == "" {
		return nil, fmt.Errorf("topic must not be empty")
	}

	writer := &kafka.Writer{
		Addr:         kafka.TCP(brokers...),
		Topic:        topic,
		Balancer:     &kafka.Hash{},
		RequiredAcks: kafka.RequireAll,
		Async:        false,
	}

	return &KafkaQueue{writer: writer}, nil
}

// Enqueue implements JobQueue for Kafka.
func (k *KafkaQueue) Enqueue(ctx context.Context, key []byte, payload []byte) error {
	msg := kafka.Message{
		Key:   key,
		Value: payload,
	}
	return k.writer.WriteMessages(ctx, msg)
}

// RedisLocker is a Redis-based implementation of DistributedLocker.
type RedisLocker struct {
	client *redis.Client
}

// NewRedisLocker constructs a Redis-backed DistributedLocker.
func NewRedisLocker(addr, password string, db int) (*RedisLocker, error) {
	if addr == "" {
		return nil, fmt.Errorf("redis addr must not be empty")
	}

	client := redis.NewClient(&redis.Options{
		Addr:     addr,
		Password: password,
		DB:       db,
	})

	// Best-effort connectivity check.
	if err := client.Ping(context.Background()).Err(); err != nil {
		return nil, fmt.Errorf("failed to ping redis: %w", err)
	}

	return &RedisLocker{client: client}, nil
}

// Acquire implements DistributedLocker using SETNX with TTL.
func (r *RedisLocker) Acquire(ctx context.Context, key, owner string, ttl time.Duration) (bool, error) {
	ok, err := r.client.SetNX(ctx, key, owner, ttl).Result()
	if err != nil {
		return false, err
	}
	return ok, nil
}

// NewFromEnv wires the MCP scheduler service using environment variables:
//
//	KAFKA_BROKERS       - comma-separated list of brokers (host:port)
//	KAFKA_TOPIC         - topic name for MCP jobs
//	REDIS_ADDR          - Redis address (host:port)
//	REDIS_PASSWORD      - Redis password (optional)
//	REDIS_DB            - Redis DB index (optional, default 0)
//	LOCK_TTL_SECONDS    - TTL for duplicate-protection lock (optional, default 300)
func NewFromEnv() (*Service, error) {
	brokersEnv := os.Getenv("KAFKA_BROKERS")
	topic := os.Getenv("KAFKA_TOPIC")
	redisAddr := os.Getenv("REDIS_ADDR")
	redisPassword := os.Getenv("REDIS_PASSWORD")
	redisDBEnv := os.Getenv("REDIS_DB")
	lockTTLEnv := os.Getenv("LOCK_TTL_SECONDS")

	var brokers []string
	for _, b := range strings.Split(brokersEnv, ",") {
		b = strings.TrimSpace(b)
		if b != "" {
			brokers = append(brokers, b)
		}
	}

	redisDB := 0
	if redisDBEnv != "" {
		if v, err := strconv.Atoi(redisDBEnv); err == nil {
			redisDB = v
		}
	}

	lockTTL := 5 * time.Minute
	if lockTTLEnv != "" {
		if v, err := strconv.Atoi(lockTTLEnv); err == nil && v > 0 {
			lockTTL = time.Duration(v) * time.Second
		}
	}

	queue, err := NewKafkaQueue(brokers, topic)
	if err != nil {
		return nil, err
	}

	locker, err := NewRedisLocker(redisAddr, redisPassword, redisDB)
	if err != nil {
		return nil, err
	}

	return New(queue, locker, lockTTL)
}
