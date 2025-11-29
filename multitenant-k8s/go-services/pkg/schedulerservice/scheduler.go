package schedulerservice

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"time"

	mcpschedulerv1 "github.com/DevOps-In-Motion/DevOps/multitenant-k8s/go-services/gen/proto/mcp-scheduler/v1"
	"github.com/google/uuid"
)

// Service represents the MCP scheduler service responsible for
// throttling, deduplicating job requests and pushing them onto a queue (such as Kafka).
type Service struct {
	queue    JobQueue
	locker   DistributedLocker
	throttle Throttler
	lockTTL  time.Duration
}

// DistributedLocker defines a minimal interface for a distributed lock backend.
type DistributedLocker interface {
	// Acquire attempts to acquire a lock for the given key and owner.
	// Returns true if acquired, false if the lock already exists.
	Acquire(ctx context.Context, key, owner string, ttl time.Duration) (bool, error)

	// Release removes the lock if owned by the given owner.
	Release(ctx context.Context, key, owner string) error
}

// Throttler defines an interface for rate limiting job requests.
type Throttler interface {
	// Allow checks if the organization is within their rate limit.
	// Returns true if allowed, false if throttled.
	Allow(ctx context.Context, organizationID string) (bool, error)

	// Remaining returns the number of requests remaining in the current window.
	Remaining(ctx context.Context, organizationID string) (int64, error)
}

// JobQueue represents an abstract queue used for scheduling jobs.
// A Kafka producer can implement this interface.
type JobQueue interface {
	Enqueue(ctx context.Context, key []byte, payload []byte) error
}

// New creates a new scheduler Service.
// The caller is responsible for providing a concrete JobQueue (e.g., Kafka producer),
// a DistributedLocker (e.g., Redis), and a Throttler (e.g., Redis rate limiter).
func New(queue JobQueue, locker DistributedLocker, throttle Throttler, lockTTL time.Duration) (*Service, error) {
	if queue == nil {
		return nil, fmt.Errorf("queue must not be nil")
	}
	if locker == nil {
		return nil, fmt.Errorf("locker must not be nil")
	}
	if throttle == nil {
		return nil, fmt.Errorf("throttle must not be nil")
	}
	if lockTTL <= 0 {
		lockTTL = 5 * time.Minute
	}

	return &Service{
		queue:    queue,
		locker:   locker,
		throttle: throttle,
		lockTTL:  lockTTL,
	}, nil // FIX: Was missing nil
}

// ScheduledJobEnvelope is the payload pushed to Kafka for downstream processors.
type ScheduledJobEnvelope struct {
	JobID          string                           `json:"job_id"`
	OrganizationID string                           `json:"organization_id"`
	JobType        string                           `json:"job_type"`
	Prompt         string                           `json:"prompt"`
	Parameters     map[string]interface{}           `json:"parameters"`
	Payload        string                           `json:"payload"`
	TimeoutSeconds int32                            `json:"timeout_seconds"`
	CallbackURL    string                           `json:"callback_url"`
	CreatedAt      time.Time                        `json:"created_at"`
	RawRequest     *mcpschedulerv1.CreateJobRequest `json:"-"`
}

// ScheduleJob validates the request, checks throttle, acquires lock, and enqueues job.
// Order of operations:
// 1. Validate request
// 2. Check throttle (fail fast if rate limited)
// 3. Acquire distributed lock (prevent duplicates)
// 4. Enqueue to Kafka
// 5. Return response (lock released automatically via TTL)
func (s *Service) ScheduleJob(ctx context.Context, req *mcpschedulerv1.CreateJobRequest) (*mcpschedulerv1.CreateJobResponse, error) {
	// Step 1: Validate request
	if err := validateRequest(req); err != nil {
		return nil, fmt.Errorf("invalid request: %w", err)
	}

	// Step 2: Check throttle BEFORE acquiring lock (fail fast)
	allowed, err := s.throttle.Allow(ctx, req.GetOrganizationId())
	if err != nil {
		return nil, fmt.Errorf("failed to check throttle: %w", err)
	}
	if !allowed {
		remaining, _ := s.throttle.Remaining(ctx, req.GetOrganizationId())
		return nil, fmt.Errorf("rate limit exceeded for organization %s; remaining: %d", req.GetOrganizationId(), remaining)
	}

	// Step 3: Generate lock key and acquire lock
	sig := hashJobSignature(req)
	lockKey := fmt.Sprintf("mcp:job:%s:%s:%s", req.GetOrganizationId(), req.GetJobType(), sig)
	ownerID := uuid.NewString()

	acquired, err := s.locker.Acquire(ctx, lockKey, ownerID, s.lockTTL)
	if err != nil {
		return nil, fmt.Errorf("failed to acquire distributed lock: %w", err)
	}
	if !acquired {
		return nil, fmt.Errorf("duplicate job detected for this tenant and automation; please retry later")
	}

	// Ensure lock is released on error (best effort)
	var enqueueErr error
	defer func() {
		if enqueueErr != nil {
			if releaseErr := s.locker.Release(ctx, lockKey, ownerID); releaseErr != nil {
				// Log but don't override original error
				fmt.Printf("warning: failed to release lock %s: %v\n", lockKey, releaseErr)
			}
		}
	}()

	// Step 4: Create job envelope
	jobID := uuid.NewString()
	env := &ScheduledJobEnvelope{
		JobID:          jobID,
		OrganizationID: req.GetOrganizationId(),
		JobType:        req.GetJobType(),
		Prompt:         req.GetPrompt(),
		Parameters:     convertParameters(req.GetParameters()),
		Payload:        req.GetPayload(),
		TimeoutSeconds: req.GetTimeoutSeconds(),
		CallbackURL:    req.GetCallbackUrl(),
		CreatedAt:      time.Now().UTC(),
		RawRequest:     req,
	}

	payload, err := json.Marshal(env)
	if err != nil {
		enqueueErr = err
		return nil, fmt.Errorf("failed to marshal job payload: %w", err)
	}

	// Step 5: Enqueue to Kafka
	if err := s.queue.Enqueue(ctx, []byte(req.GetOrganizationId()), payload); err != nil {
		enqueueErr = err
		return nil, fmt.Errorf("failed to enqueue job: %w", err)
	}

	// Step 6: Return success response
	resp := &mcpschedulerv1.CreateJobResponse{
		JobId:               jobID,
		OrganizationId:      req.GetOrganizationId(),
		Status:              mcpschedulerv1.JobStatus_JOB_STATUS_PENDING,
		Namespace:           "",
		PodName:             "",
		CreatedAt:           nil,
		EstimatedTtlSeconds: req.GetTimeoutSeconds(),
	}

	return resp, nil
}

// validateRequest checks that required fields are present
func validateRequest(req *mcpschedulerv1.CreateJobRequest) error {
	if req == nil {
		return fmt.Errorf("request must not be nil")
	}
	if req.GetOrganizationId() == "" {
		return fmt.Errorf("organization_id is required")
	}
	if req.GetJobType() == "" {
		return fmt.Errorf("job_type is required")
	}
	if req.GetPrompt() == "" && req.GetPayload() == "" {
		return fmt.Errorf("either prompt or payload is required")
	}
	if req.GetTimeoutSeconds() <= 0 {
		return fmt.Errorf("timeout_seconds must be positive")
	}
	return nil
}

// convertParameters converts map[string]string to map[string]interface{}
func convertParameters(params map[string]string) map[string]interface{} {
	if params == nil {
		return nil
	}
	result := make(map[string]interface{}, len(params))
	for k, v := range params {
		result[k] = v
	}
	return result
}

// hashJobSignature creates a deterministic hash of the prompt, payload, and parameters
// to identify duplicate job requests.
func hashJobSignature(req *mcpschedulerv1.CreateJobRequest) string {
	h := sha256.New()
	h.Write([]byte(req.GetPrompt()))
	h.Write([]byte(req.GetJobType()))
	h.Write([]byte(req.GetPayload()))

	// Normalize parameter map by sorting keys
	if len(req.GetParameters()) > 0 {
		type kv struct {
			k string
			v string
		}
		pairs := make([]kv, 0, len(req.GetParameters()))
		for k, v := range req.GetParameters() {
			pairs = append(pairs, kv{k: k, v: v})
		}
		// Simple insertion sort
		for i := 1; i < len(pairs); i++ {
			j := i
			for j > 0 && pairs[j-1].k > pairs[j].k {
				pairs[j-1], pairs[j] = pairs[j], pairs[j-1]
				j--
			}
		}
		for _, p := range pairs {
			h.Write([]byte(p.k))
			h.Write([]byte(p.v))
		}
	}

	return hex.EncodeToString(h.Sum(nil))
}
