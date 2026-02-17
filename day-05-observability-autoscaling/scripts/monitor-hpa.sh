#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📊 HPA Monitoring Dashboard${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Press Ctrl+C to exit${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

PREV_REPLICAS=0
SCALING_EVENT=""

while true; do
    clear
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}📊 HPA Status - $(date '+%H:%M:%S')${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Get HPA status
    HPA_OUTPUT=$(kubectl get hpa api-hpa 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ HPA 'api-hpa' not found${NC}"
        echo "Run: kubectl apply -f manifests/09-hpa-api.yaml"
        sleep 5
        continue
    fi
    
    echo -e "${CYAN}HorizontalPodAutoscaler:${NC}"
    echo "$HPA_OUTPUT" | head -1  # Header
    HPA_LINE=$(echo "$HPA_OUTPUT" | tail -1)
    
    # Extract values
    CURRENT_CPU=$(echo "$HPA_LINE" | awk '{print $3}' | cut -d'/' -f1)
    TARGET_CPU=$(echo "$HPA_LINE" | awk '{print $3}' | cut -d'/' -f2)
    REPLICAS=$(echo "$HPA_LINE" | awk '{print $4}')
    MIN=$(echo "$HPA_LINE" | awk '{print $5}')
    MAX=$(echo "$HPA_LINE" | awk '{print $6}')
    
    # Color code based on CPU
    if [[ "$CURRENT_CPU" == *"%"* ]]; then
        CPU_VAL=$(echo "$CURRENT_CPU" | sed 's/%//')
        TARGET_VAL=$(echo "$TARGET_CPU" | sed 's/%//')
        
        if [ "$CPU_VAL" -gt "$TARGET_VAL" ]; then
            echo -e "${RED}$HPA_LINE${NC}"
        elif [ "$CPU_VAL" -gt $((TARGET_VAL - 10)) ]; then
            echo -e "${YELLOW}$HPA_LINE${NC}"
        else
            echo -e "${GREEN}$HPA_LINE${NC}"
        fi
    else
        echo "$HPA_LINE"
    fi
    
    echo ""
    
    # Detect scaling events
    if [ "$REPLICAS" != "$PREV_REPLICAS" ] && [ "$PREV_REPLICAS" -ne 0 ]; then
        if [ "$REPLICAS" -gt "$PREV_REPLICAS" ]; then
            SCALING_EVENT="${GREEN}🔼 SCALING UP: $PREV_REPLICAS → $REPLICAS replicas${NC}"
        else
            SCALING_EVENT="${YELLOW}🔽 SCALING DOWN: $PREV_REPLICAS → $REPLICAS replicas${NC}"
        fi
    fi
    
    if [ -n "$SCALING_EVENT" ]; then
        echo -e "$SCALING_EVENT"
        echo ""
    fi
    
    PREV_REPLICAS=$REPLICAS
    
    # Show Pods
    echo -e "${CYAN}API Pods:${NC}"
    kubectl get pods -l app=api --no-headers 2>/dev/null | while read line; do
        STATUS=$(echo "$line" | awk '{print $3}')
        case $STATUS in
            Running)
                echo -e "${GREEN}$line${NC}"
                ;;
            Pending|ContainerCreating)
                echo -e "${YELLOW}$line${NC}"
                ;;
            *)
                echo -e "${RED}$line${NC}"
                ;;
        esac
    done
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}💡 Tips:${NC}"
    echo "  • Target CPU: Keep average around ${TARGET_CPU}"
    echo "  • Generate load: ./scripts/generate-load.sh 50 120"
    echo "  • Scale-up triggers when CPU > ${TARGET_CPU}"
    echo "  • Scale-down has 5min cooldown"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    sleep 2
done
