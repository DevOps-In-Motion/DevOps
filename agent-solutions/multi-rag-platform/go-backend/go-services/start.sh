# Generate all code (gRPC, Gateway, OpenAPI)
buf generate --path proto

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
go mod init github.com/DevOps-In-Motion/DevOps/multitenant-k8s/go-services

# Add dependencies
# go get google.golang.org/grpc
# go get google.golang.org/protobuf
# go get github.com/grpc-ecosystem/grpc-gateway/v2
# go get github.com/bufbuild/connect-go
# AWS SDK v2
go get github.com/aws/aws-sdk-go-v2/config
go get github.com/aws/aws-sdk-go-v2/service/iam
go get github.com/aws/aws-sdk-go-v2/service/s3

# Kubernetes client-go
go get k8s.io/client-go@latest
go get k8s.io/api@latest
go get k8s.io/apimachinery@latest
go install github.com/bufbuild/buf/cmd/buf@latest
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
go install connectrpc.com/connect/cmd/protoc-gen-connect-go@latest

# You'll need buf, protoc-gen-go and protoc-gen-connect-go on your PATH. 
# If which buf protoc-gen-go protoc-gen-connect-go doesn't succeed, 
# add Go's install directories to your path:
[ -n "$(go env GOBIN)" ] && export PATH="$(go env GOBIN):${PATH}"
[ -n "$(go env GOPATH)" ] && export PATH="$(go env GOPATH)/bin:${PATH}"




### --- Project Structure --- ###

mkdir -p cmd/account-server
mkdir -p cmd/scheduler-server
mkdir -p cmd/client-example
mkdir -p pkg/accountservice
mkdir -p pkg/schedulerservice
mkdir -p pkg/storage
mkdir -p internal/config
mkdir -p internal/middleware

### --- Issues --- ###
# clean after new installs .
go clean -modcache

# Re-Generate
rm -rf gen/

# Regenerate with new import paths
buf generate
go mod tidy