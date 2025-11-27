# Generate all code (gRPC, Gateway, OpenAPI)
buf generate

# This creates:
# - gen/go/saas/v1/*.pb.go
# - gen/openapi/api.swagger.json

# Check for breaking changes
buf breaking --against '.git#branch=main'

# Lint proto files
buf lint

# Format proto files
buf format -w


# Initialize Go module
go mod init github.com/devops-in-motion/saas-services

# Add dependencies
go get google.golang.org/grpc
go get google.golang.org/protobuf
go get github.com/grpc-ecosystem/grpc-gateway/v2
go get github.com/bufbuild/connect-go