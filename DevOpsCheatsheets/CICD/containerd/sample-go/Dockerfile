# syntax=docker/dockerfile:1.4

#############################################
# Build Stage
#############################################
FROM golang:1.22.0-alpine3.19 AS builder

# Install build dependencies and security tools
RUN apk add --no-cache \
    git=2.43.0-r0 \
    ca-certificates=20240226-r0 \
    tzdata=2024a-r0 \
    upx=4.2.1-r0

# Create non-root user for final image
RUN addgroup -g 10001 -S grpcuser && \
    adduser -u 10001 -S grpcuser -G grpcuser

WORKDIR /build

# Copy dependency files first for better caching
COPY go.mod go.sum ./

# Download dependencies with verification
RUN go mod download && \
    go mod verify

# Copy source code
COPY . .

# Build with security flags and optimizations
RUN CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64 \
    go build \
    -ldflags='-w -s -extldflags "-static"' \
    -a \
    -installsuffix cgo \
    -tags netgo \
    -o /build/server \
    ./cmd/server

# Compress binary (optional but saves ~30-40% space)
RUN upx --best --lzma /build/server

# Run security scan on dependencies
RUN go install golang.org/x/vuln/cmd/govulncheck@latest && \
    govulncheck ./...

#############################################
# Security Scanner Stage (Optional but Recommended)
#############################################
FROM aquasec/trivy:0.48.0 AS scanner

COPY --from=builder /build /scan

# Scan for vulnerabilities
RUN trivy fs --exit-code 0 --severity HIGH,CRITICAL --no-progress /scan

#############################################
# Production Stage - Distroless
#############################################
FROM gcr.io/distroless/static-debian12:nonroot

# Metadata labels
LABEL org.opencontainers.image.title="gRPC Service" \
      org.opencontainers.image.description="Production gRPC service in Go" \
      org.opencontainers.image.vendor="Your Company" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/devops-in-motion/devops"

# Copy certificates for TLS
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy timezone data
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

# Copy binary
COPY --from=builder --chown=nonroot:nonroot /build/server /app/server

# Set working directory
WORKDIR /app

# Use nonroot user (UID 65532)
USER nonroot:nonroot

# Expose gRPC port
EXPOSE 50051

# Health check for gRPC service
# Note: Distroless doesn't have grpc-health-probe, so we rely on Kubernetes probes
# You'll need to implement gRPC health checking service

# Start server
ENTRYPOINT ["/app/server"]