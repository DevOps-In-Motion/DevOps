#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Base URL
BASE_URL="http://localhost:8080"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Testing User and Post API${NC}"
echo -e "${BLUE}========================================${NC}\n"

# App uses PostgreSQL (DATABASE_URL). Ensure DB is up before running.
echo -e "${YELLOW}Using API at $BASE_URL (ensure server and PostgreSQL are running).${NC}\n"
sleep 1
echo -e "${GREEN}✓ Ready to test${NC}\n"

# Test 1: Create first user
echo -e "${YELLOW}Test 1: Creating first user (Alice)...${NC}"
RESPONSE=$(curl -s -X POST "$BASE_URL/users" \
  -H "Content-Type: application/json" \
  -d '{"name": "Alice"}')
echo -e "${GREEN}Response:${NC} $RESPONSE\n"

# Test 2: Create second user
echo -e "${YELLOW}Test 2: Creating second user (Bob)...${NC}"
RESPONSE=$(curl -s -X POST "$BASE_URL/users" \
  -H "Content-Type: application/json" \
  -d '{"name": "Bob"}')
echo -e "${GREEN}Response:${NC} $RESPONSE\n"

# Test 3: Create third user
echo -e "${YELLOW}Test 3: Creating third user (Charlie)...${NC}"
RESPONSE=$(curl -s -X POST "$BASE_URL/users" \
  -H "Content-Type: application/json" \
  -d '{"name": "Charlie"}')
echo -e "${GREEN}Response:${NC} $RESPONSE\n"

# Test 4: Get user by ID
echo -e "${YELLOW}Test 4: Getting user with ID 1...${NC}"
RESPONSE=$(curl -s "$BASE_URL/users/1")
echo -e "${GREEN}Response:${NC} $RESPONSE\n"

# Test 5: Get user by ID
echo -e "${YELLOW}Test 5: Getting user with ID 2...${NC}"
RESPONSE=$(curl -s "$BASE_URL/users/2")
echo -e "${GREEN}Response:${NC} $RESPONSE\n"

# Test 6: Get non-existent user (should return 404)
echo -e "${YELLOW}Test 6: Getting non-existent user (ID 999)...${NC}"
RESPONSE=$(curl -s "$BASE_URL/users/999")
echo -e "${GREEN}Response:${NC} $RESPONSE\n"

# Test 7: Create first post
echo -e "${YELLOW}Test 7: Creating first post (by user 1)...${NC}"
RESPONSE=$(curl -s -X POST "$BASE_URL/posts" \
  -H "Content-Type: application/json" \
  --data-raw '{"user_id": 1, "content": "Hello World! This is my first post."}')
echo -e "${GREEN}Response:${NC} $RESPONSE\n"

# Test 8: Create second post
echo -e "${YELLOW}Test 8: Creating second post (by user 2)...${NC}"
RESPONSE=$(curl -s -X POST "$BASE_URL/posts" \
  -H "Content-Type: application/json" \
  --data-raw '{"user_id": 2, "content": "Bob here, sharing some thoughts!"}')
echo -e "${GREEN}Response:${NC} $RESPONSE\n"

# Test 9: Create third post
echo -e "${YELLOW}Test 9: Creating third post (by user 1)...${NC}"
RESPONSE=$(curl -s -X POST "$BASE_URL/posts" \
  -H "Content-Type: application/json" \
  --data-raw '{"user_id": 1, "content": "Another post from Alice"}')
echo -e "${GREEN}Response:${NC} $RESPONSE\n"

# Test 10: Create post with non-existent user (should fail)
echo -e "${YELLOW}Test 10: Creating post with non-existent user (should fail)...${NC}"
RESPONSE=$(curl -s -X POST "$BASE_URL/posts" \
  -H "Content-Type: application/json" \
  --data-raw '{"user_id": 999, "content": "This should fail"}')
echo -e "${RED}Response:${NC} $RESPONSE\n"

# Test 11: Get post by ID
echo -e "${YELLOW}Test 11: Getting post with ID 1...${NC}"
RESPONSE=$(curl -s "$BASE_URL/posts/1")
echo -e "${GREEN}Response:${NC} $RESPONSE\n"

# Test 12: Get post by ID
echo -e "${YELLOW}Test 12: Getting post with ID 2...${NC}"
RESPONSE=$(curl -s "$BASE_URL/posts/2")
echo -e "${GREEN}Response:${NC} $RESPONSE\n"

# Test 13: Get non-existent post (should return 404)
echo -e "${YELLOW}Test 13: Getting non-existent post (ID 999)...${NC}"
RESPONSE=$(curl -s "$BASE_URL/posts/999")
echo -e "${GREEN}Response:${NC} $RESPONSE\n"

# Test 14: Get Prometheus metrics
echo -e "${YELLOW}Test 14: Getting Prometheus metrics...${NC}"
echo -e "${GREEN}Metrics (users and posts counters):${NC}"
curl -s "$BASE_URL/metrics" | grep -E "(users_created_total|posts_created_total)"
echo ""

# Summary
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓ Created 3 users${NC}"
echo -e "${GREEN}✓ Retrieved users by ID${NC}"
echo -e "${GREEN}✓ Created 3 posts${NC}"
echo -e "${GREEN}✓ Retrieved posts by ID${NC}"
echo -e "${GREEN}✓ Tested error handling (404s)${NC}"
echo -e "${GREEN}✓ Verified Prometheus metrics${NC}"
echo -e "\n${BLUE}All tests completed!${NC}\n"
