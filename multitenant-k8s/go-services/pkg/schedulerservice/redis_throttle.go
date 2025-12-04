package schedulerservice

import (
	"context"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

// RedisThrottler implements Throttler using Redis sorted sets (sliding window)
type RedisThrottler struct {
	client       *redis.Client
	limitPerMin  int64
	limitPerHour int64
	windowMin    time.Duration
	windowHour   time.Duration
}

// NewRedisThrottler creates a new Redis-based rate limiter with sliding window
func NewRedisThrottler(client *redis.Client, limitPerMin, limitPerHour int64) *RedisThrottler {
	return &RedisThrottler{
		client:       client,
		limitPerMin:  limitPerMin,
		limitPerHour: limitPerHour,
		windowMin:    1 * time.Minute,
		windowHour:   1 * time.Hour,
	}
}

// Allow checks if the organization is within their rate limit using sliding window
func (r *RedisThrottler) Allow(ctx context.Context, organizationID string) (bool, error) {
	now := time.Now()

	// Check minute window
	minKey := fmt.Sprintf("throttle:%s:minute", organizationID)
	minCount, err := r.countInWindow(ctx, minKey, now, r.windowMin)
	if err != nil {
		return false, fmt.Errorf("failed to check minute throttle: %w", err)
	}
	if minCount >= r.limitPerMin {
		return false, nil
	}

	// Check hour window
	hourKey := fmt.Sprintf("throttle:%s:hour", organizationID)
	hourCount, err := r.countInWindow(ctx, hourKey, now, r.windowHour)
	if err != nil {
		return false, fmt.Errorf("failed to check hour throttle: %w", err)
	}
	if hourCount >= r.limitPerHour {
		return false, nil
	}

	// Record this request in both windows using pipeline for efficiency
	pipe := r.client.Pipeline()

	// Add to minute window
	pipe.ZAdd(ctx, minKey, redis.Z{Score: float64(now.UnixNano()), Member: now.UnixNano()})
	pipe.Expire(ctx, minKey, r.windowMin+10*time.Second) // Extra buffer for cleanup

	// Add to hour window
	pipe.ZAdd(ctx, hourKey, redis.Z{Score: float64(now.UnixNano()), Member: now.UnixNano()})
	pipe.Expire(ctx, hourKey, r.windowHour+10*time.Minute)

	_, err = pipe.Exec(ctx)
	if err != nil {
		return false, fmt.Errorf("failed to record request: %w", err)
	}

	return true, nil
}

// Remaining returns the number of requests remaining in the current minute window
func (r *RedisThrottler) Remaining(ctx context.Context, organizationID string) (int64, error) {
	minKey := fmt.Sprintf("throttle:%s:minute", organizationID)
	count, err := r.countInWindow(ctx, minKey, time.Now(), r.windowMin)
	if err != nil {
		return 0, fmt.Errorf("failed to get remaining: %w", err)
	}

	remaining := r.limitPerMin - count
	if remaining < 0 {
		remaining = 0
	}

	return remaining, nil
}

// countInWindow counts requests in the sliding window using sorted set
func (r *RedisThrottler) countInWindow(ctx context.Context, key string, now time.Time, window time.Duration) (int64, error) {
	windowStart := now.Add(-window)

	// Remove old entries and count current entries atomically with Lua script
	script := `
		local key = KEYS[1]
		local window_start = ARGV[1]
		local now = ARGV[2]
		
		-- Remove entries older than window
		redis.call("ZREMRANGEBYSCORE", key, "-inf", window_start)
		
		-- Count entries in current window
		return redis.call("ZCOUNT", key, window_start, now)
	`

	result, err := r.client.Eval(ctx, script,
		[]string{key},
		windowStart.UnixNano(),
		now.UnixNano(),
	).Result()

	if err != nil {
		return 0, fmt.Errorf("failed to count window: %w", err)
	}

	count, ok := result.(int64)
	if !ok {
		return 0, fmt.Errorf("unexpected result type: %T", result)
	}

	return count, nil
}
