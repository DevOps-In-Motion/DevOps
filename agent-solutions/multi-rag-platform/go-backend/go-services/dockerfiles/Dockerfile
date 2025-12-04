# Use the official Golang image as a parent image
FROM golang:1.22 AS builder
# Set the working directory inside the container
WORKDIR /workspace

# Copy the local package files to the container's workspace.
COPY go.mod go.sum /workspace/
# Refresh dependencies
RUN go mod download
# Copy the local package files to the container's workspace.
COPY cmd /workspace/cmd
# Copy the local package files to the container's workspace.
COPY internal /workspace/internal
# Copy gen files to the container's workspace.
COPY gen /workspace/gen
# Build the server command inside the container.
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o server ./cmd/server
# Ensure the server binary exists
RUN ls -l /workspace/server

# Use a Docker multi-stage build to create a lean production image.
FROM alpine:latest
# Install the certificates and timezone data
RUN apk --update --no-cache add ca-certificates tzdata && rm -rf /var/cache/apk/*

# Expose port 8080 to the outside world
EXPOSE 8080

COPY --from=builder /workspace/server /usr/local/bin/server
RUN ls -l /usr/local/bin/server

CMD [ "/usr/local/bin/server", "--server-stream-delay=500ms" ]

