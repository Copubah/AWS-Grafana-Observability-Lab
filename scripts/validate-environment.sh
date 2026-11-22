#!/bin/bash

#############################################
# Phase 1: Environment Validation Script
# Validates all prerequisites for the 
# AWS Grafana Observability Lab
#############################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Tracking
ERRORS=0
WARNINGS=0

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}AWS Grafana Observability Lab${NC}"
echo -e "${BLUE}Phase 1: Environment Validation${NC}"
echo -e "${BLUE}================================================${NC}\n"

# Helper functions
check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((ERRORS++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# 1. Check Docker
echo -e "\n${BLUE}[1/10] Checking Docker${NC}"
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')
    check_pass "Docker installed: $DOCKER_VERSION"
    
    if docker ps &> /dev/null; then
        check_pass "Docker daemon is running"
    else
        check_fail "Docker daemon is not running or requires sudo"
        info "Try: sudo systemctl start docker"
    fi
else
    check_fail "Docker is not installed"
    info "Install: https://docs.docker.com/engine/install/"
fi

# 2. Check Docker Compose
echo -e "\n${BLUE}[2/10] Checking Docker Compose${NC}"
if docker compose version &> /dev/null; then
    COMPOSE_VERSION=$(docker compose version --short)
    check_pass "Docker Compose installed: $COMPOSE_VERSION"
else
    check_fail "Docker Compose is not available"
    info "Install Docker Compose plugin"
fi

# 3. Check Terraform
echo -e "\n${BLUE}[3/10] Checking Terraform${NC}"
if command -v terraform &> /dev/null; then
    TF_VERSION=$(terraform version -json | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4)
    check_pass "Terraform installed: $TF_VERSION"
    
    # Check minimum version
    if [[ "$(printf '%s\n' "1.5.0" "$TF_VERSION" | sort -V | head -n1)" == "1.5.0" ]]; then
        check_pass "Terraform version >= 1.5.0"
    else
        check_warn "Terraform version < 1.5.0 (may not be compatible)"
    fi
else
    check_fail "Terraform is not installed"
    info "Install: https://developer.hashicorp.com/terraform/install"
fi

# 4. Check AWS CLI
echo -e "\n${BLUE}[4/10] Checking AWS CLI${NC}"
if command -v aws &> /dev/null; then
    AWS_VERSION=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2)
    check_pass "AWS CLI installed: $AWS_VERSION"
else
    check_fail "AWS CLI is not installed"
    info "Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
fi

# 5. Check AWS Configuration
echo -e "\n${BLUE}[5/10] Checking AWS Configuration${NC}"
if aws sts get-caller-identity &> /dev/null; then
    AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    AWS_USER=$(aws sts get-caller-identity --query Arn --output text)
    check_pass "AWS credentials configured"
    info "Account: $AWS_ACCOUNT"
    info "Identity: $AWS_USER"
else
    check_fail "AWS credentials not configured or invalid"
    info "Configure: aws configure"
fi

# 6. Check AWS Region
echo -e "\n${BLUE}[6/10] Checking AWS Region${NC}"
CONFIGURED_REGION=$(aws configure get region 2>/dev/null || echo "")
if [[ -n "$CONFIGURED_REGION" ]]; then
    check_pass "AWS region configured: $CONFIGURED_REGION"
    
    if [[ "$CONFIGURED_REGION" == "us-east-1" ]]; then
        check_pass "Region matches project requirement (us-east-1)"
    else
        check_warn "Region is $CONFIGURED_REGION, project expects us-east-1"
        info "This may work, but cross-region resources won't be visible"
    fi
else
    check_fail "AWS region not configured"
    info "Set default region: aws configure set region us-east-1"
fi

# 7. Check Session Manager Plugin
echo -e "\n${BLUE}[7/10] Checking AWS Session Manager Plugin${NC}"
if command -v session-manager-plugin &> /dev/null; then
    check_pass "Session Manager plugin installed"
else
    check_fail "Session Manager plugin not installed"
    info "Install: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
fi

# 8. Check Default VPC
echo -e "\n${BLUE}[8/10] Checking Default VPC${NC}"
if aws sts get-caller-identity &> /dev/null; then
    DEFAULT_VPC=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "None")
    
    if [[ "$DEFAULT_VPC" != "None" && "$DEFAULT_VPC" != "" ]]; then
        check_pass "Default VPC exists: $DEFAULT_VPC"
        
        # Check subnets
        SUBNET_COUNT=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$DEFAULT_VPC" --query "length(Subnets)" --output text 2>/dev/null || echo "0")
        if [[ "$SUBNET_COUNT" -gt 0 ]]; then
            check_pass "Default VPC has $SUBNET_COUNT subnet(s)"
        else
            check_fail "Default VPC has no subnets"
        fi
    else
        check_fail "No default VPC found in $CONFIGURED_REGION"
        info "Create one: aws ec2 create-default-vpc"
    fi
fi

# 9. Check Local Docker Containers
echo -e "\n${BLUE}[9/10] Checking Local Monitoring Stack${NC}"
if docker ps &> /dev/null; then
    if docker ps --format '{{.Names}}' | grep -q "observability-prometheus"; then
        PROM_STATUS=$(docker ps --filter "name=observability-prometheus" --format "{{.Status}}")
        check_pass "Prometheus container running: $PROM_STATUS"
    else
        check_warn "Prometheus container not running"
        info "Start with: docker compose up -d"
    fi
    
    if docker ps --format '{{.Names}}' | grep -q "observability-grafana"; then
        GRAF_STATUS=$(docker ps --filter "name=observability-grafana" --format "{{.Status}}")
        check_pass "Grafana container running: $GRAF_STATUS"
    else
        check_warn "Grafana container not running"
        info "Start with: docker compose up -d"
    fi
else
    check_warn "Cannot check Docker containers (Docker not accessible)"
fi

# 10. Check Port Availability
echo -e "\n${BLUE}[10/10] Checking Port Availability${NC}"
check_port() {
    local port=$1
    local service=$2
    
    if ss -tuln 2>/dev/null | grep -q ":$port " || netstat -tuln 2>/dev/null | grep -q ":$port "; then
        check_warn "Port $port ($service) is in use"
    else
        check_pass "Port $port ($service) is available"
    fi
}

check_port 3000 "Grafana"
check_port 9090 "Prometheus"
check_port 9100 "Node Exporter/SSM Tunnel"

# Summary
echo -e "\n${BLUE}================================================${NC}"
echo -e "${BLUE}Validation Summary${NC}"
echo -e "${BLUE}================================================${NC}"

if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo -e "Ready to proceed with deployment.\n"
    exit 0
elif [[ $ERRORS -eq 0 ]]; then
    echo -e "${YELLOW}⚠ $WARNINGS warning(s) found${NC}"
    echo -e "You can proceed, but review the warnings above.\n"
    exit 0
else
    echo -e "${RED}✗ $ERRORS error(s) found${NC}"
    if [[ $WARNINGS -gt 0 ]]; then
        echo -e "${YELLOW}⚠ $WARNINGS warning(s) found${NC}"
    fi
    echo -e "\nFix the errors above before proceeding.\n"
    exit 1
fi
