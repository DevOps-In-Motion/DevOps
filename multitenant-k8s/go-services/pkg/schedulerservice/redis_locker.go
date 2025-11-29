package schedulerservice

import (
	"context"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

// RedisLocker implements DistributedLocker using Redis
type RedisLocker struct {
	client *redis.Client
}

// NewRedisLocker creates a new Redis-based distributed locker
func NewRedisLocker(client *redis.Client) *RedisLocker {
	return &RedisLocker{client: client}
}

// Acquire attempts to acquire a lock using Redis SET NX (set if not exists)
func (r *RedisLocker) Acquire(ctx context.Context, key, owner string, ttl time.Duration) (bool, error) {
	// SET key owner NX EX ttl_seconds
	// NX = only set if key doesn't exist
	// EX = set expiration
	result, err := r.client.SetNX(ctx, key, owner, ttl).Result()
	if err != nil {
		return false, fmt.Errorf("failed to acquire lock: %w", err)
	}
	return result, nil
}

// Release removes the lock if owned by the given owner (atomic Lua script)
func (r *RedisLocker) Release(ctx context.Context, key, owner string) error {
	// Lua script to atomically check owner and delete
	script := `
		if redis.call("GET", KEYS[1]) == ARGV[1] then
			return redis.call("DEL", KEYS[1])
		else
			return 0
		end
	`
	result, err := r.client.Eval(ctx, script, []string{key}, owner).Result()
	if err != nil {
		return fmt.Errorf("failed to release lock: %w", err)
	}

	// result is 0 if lock wasn't owned by this owner, 1 if deleted
	if result == int64(0) {
		return fmt.Errorf("lock not owned by owner %s", owner)
	}

	return nil
}
