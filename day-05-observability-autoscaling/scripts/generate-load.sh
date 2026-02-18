#!/bin/bash
set -e

# Configuration
RATE=${1:-20}           # Requests per second (default 20)
DURATION=${2:-300}      # Duration in seconds (default 5 min)
API_URL="http://$(minikube ip)/api"
HOST="capstone.local"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Validate inputs
if ! [[ "$RATE" =~ ^[0-9]+$ ]] || [ "$RATE" -lt 1 ]; then
    echo -e "${RED}Error: RATE must be a positive integer${NC}"
    echo "Usage: $0 [rate] [duration]"
    echo "Example: $0 20 300  # 20 req/s for 300 seconds"
    exit 1
fi

if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [ "$DURATION" -lt 1 ]; then
    echo -e "${RED}Error: DURATION must be a positive integer${NC}"
    exit 1
fi

# Check minikube is running
if ! minikube status > /dev/null 2>&1; then
    echo -e "${RED}Error: minikube is not running${NC}"
    echo "Start it with: minikube start"
    exit 1
fi

# Check API is reachable
if ! curl -sf -H "Host: $HOST" "$API_URL/health" > /dev/null 2>&1; then
    echo -e "${RED}Error: API not reachable at $API_URL${NC}"
    echo "Check Ingress is working:"
    echo "  kubectl get ingress"
    echo "  curl -H \"Host: capstone.local\" http://\$(minikube ip)/api/health"
    exit 1
fi

# Banner
clear
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🔥 Task API Load Generator${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Target:${NC}   $API_URL"
echo -e "${YELLOW}Rate:${NC}     $RATE req/s ($(($RATE * 2)) total req/s with POST+GET)"
echo -e "${YELLOW}Duration:${NC} $DURATION seconds ($((DURATION / 60)) min)"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop early${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Counters
COUNT=0
SUCCESS=0
FAILED=0
START=$(date +%s)

# Trap Ctrl+C
trap 'echo ""; echo -e "${YELLOW}⚠️  Load test interrupted${NC}"; print_summary; exit 0' INT

print_summary() {
    END=$(date +%s)
    ELAPSED=$((END - START))
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}📊 Load Test Summary${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Duration:${NC}   ${ELAPSED}s"
    echo -e "${YELLOW}Total:${NC}      $COUNT requests"
    echo -e "${GREEN}Success:${NC}    $SUCCESS"
    echo -e "${RED}Failed:${NC}     $FAILED"
    if [ $ELAPSED -gt 0 ]; then
        AVG_RATE=$(echo "scale=2; $COUNT / $ELAPSED" | bc 2>/dev/null || echo "N/A")
        echo -e "${YELLOW}Avg Rate:${NC}   ${AVG_RATE} req/s"
    fi
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Progress bar function
print_progress() {
    local percent=$1
    local elapsed=$2
    local count=$3
    local bar_length=40
    local filled=$((percent * bar_length / 100))
    local empty=$((bar_length - filled))
    
    printf "\r${YELLOW}Progress:${NC} ["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' ' '
    printf "] ${percent}%% | ${elapsed}s/${DURATION}s | Requests: $count"
}

# Main loop
while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START))
    PERCENT=$((ELAPSED * 100 / DURATION))
    
    # Check duration
    if [ $ELAPSED -ge $DURATION ]; then
        echo ""
        echo -e "${GREEN}✅ Load test complete${NC}"
        print_summary
        break
    fi
    
    # Send requests (background for parallelism)
    if curl -sf -H "Host: $HOST" "$API_URL/tasks" > /dev/null 2>&1; then
        SUCCESS=$((SUCCESS + 1))
    else
        FAILED=$((FAILED + 1))
    fi &
    
    if curl -sf -H "Host: $HOST" -X POST -H "Content-Type: application/json" \
        -d '{"title":"Load test task"}' "$API_URL/tasks" > /dev/null 2>&1; then
        SUCCESS=$((SUCCESS + 1))
    else
        FAILED=$((FAILED + 1))
    fi &
    
    COUNT=$((COUNT + 2))
    
    # Print progress bar
    print_progress $PERCENT $ELAPSED $COUNT
    
    # Sleep to control rate (2 requests per iteration)
    sleep $(awk "BEGIN {print 2/$RATE}" 2>/dev/null || echo "0.1")
done
