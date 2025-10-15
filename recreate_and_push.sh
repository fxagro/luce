#!/bin/bash

# ============================================================================
# Luce Booking Subsystem - Deployment Script
# ============================================================================
# This script verifies the project structure, commits all files, and pushes
# to the GitHub repository with proper error handling and colored output.
#
# Usage: ./recreate_and_push.sh
# ============================================================================

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Repository details
REPO_URL="https://github.com/fxagro/luce"
BRANCH="main"

echo -e "${BLUE}🚀 Starting Luce Booking Subsystem deployment...${NC}"

# ============================================================================
# VERIFICATION FUNCTIONS
# ============================================================================

verify_directory_structure() {
    echo -e "\n${YELLOW}📁 Verifying directory structure...${NC}"

    local required_dirs=(
        "app/controllers/api/v1"
        "app/services/booking"
        "app/jobs/booking"
        "db/migrate"
        "spec/requests/api/v1"
        "spec/services/booking"
        "spec/jobs/booking"
        "doc/adr"
        ".github/workflows"
    )

    local missing_dirs=()

    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            missing_dirs+=("$dir")
        else
            echo -e "  ${GREEN}✓${NC} $dir"
        fi
    done

    if [ ${#missing_dirs[@]} -ne 0 ]; then
        echo -e "${RED}❌ Missing directories:${NC}"
        for dir in "${missing_dirs[@]}"; do
            echo -e "  ${RED}✗${NC} $dir"
        done
        return 1
    fi

    echo -e "${GREEN}✅ All required directories exist${NC}"
    return 0
}

verify_files() {
    echo -e "\n${YELLOW}📄 Verifying required files...${NC}"

    local required_files=(
        "app/controllers/api/v1/bookings_controller.rb"
        "app/services/booking/create_booking.rb"
        "app/jobs/booking/match_provider_job.rb"
        "db/migrate/20250115092200_add_default_status_and_unique_client_token_to_bookings.rb"
        "spec/requests/api/v1/bookings_spec.rb"
        "spec/services/booking/create_booking_spec.rb"
        "spec/jobs/booking/match_provider_job_spec.rb"
        "doc/adr/0001-booking-refactor.md"
        ".github/workflows/ci.yml"
        ".gitignore"
        "README.md"
    )

    local missing_files=()

    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_files+=("$file")
        else
            echo -e "  ${GREEN}✓${NC} $file"
        fi
    done

    if [ ${#missing_files[@]} -ne 0 ]; then
        echo -e "${RED}❌ Missing files:${NC}"
        for file in "${missing_files[@]}"; do
            echo -e "  ${RED}✗${NC} $file"
        done
        return 1
    fi

    echo -e "${GREEN}✅ All required files exist${NC}"
    return 0
}

verify_git_repository() {
    echo -e "\n${YELLOW}🔍 Verifying Git repository...${NC}"

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}❌ Not a Git repository${NC}"
        echo -e "${YELLOW}💡 Run the following commands to initialize:${NC}"
        echo -e "  git init"
        echo -e "  git remote add origin $REPO_URL"
        return 1
    fi

    echo -e "${GREEN}✅ Git repository found${NC}"

    # Check remote
    if git remote get-url origin > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Remote origin configured${NC}"
    else
        echo -e "${YELLOW}⚠️  Remote origin not configured${NC}"
        echo -e "${YELLOW}💡 Run: git remote add origin $REPO_URL${NC}"
        return 1
    fi

    return 0
}

# ============================================================================
# DEPLOYMENT FUNCTIONS
# ============================================================================

add_and_commit_files() {
    echo -e "\n${YELLOW}📦 Adding files to Git...${NC}"

    # Add all files
    if git add .; then
        echo -e "${GREEN}✅ Files added to staging area${NC}"
    else
        echo -e "${RED}❌ Failed to add files${NC}"
        return 1
    fi

    # Check if there are changes to commit
    if git diff --cached --quiet; then
        echo -e "${YELLOW}⚠️  No changes to commit${NC}"
        return 0
    fi

    # Commit with message
    local commit_message="Add all project files: controller, service, job, migration, tests, ADR, CI workflow

- Add bookings controller with POST action, idempotency, HTTP 202 response
- Add CreateBooking service object with validation and structured logging
- Add MatchProviderJob Sidekiq job with provider matching and metrics
- Add database migration for booking status and client_token constraints
- Add comprehensive RSpec tests for all components
- Add ADR documenting refactor decisions and architecture
- Add GitHub Actions CI workflow with Ruby 3.x, Rails 7, PostgreSQL, Redis
- Add Rails 7 .gitignore with comprehensive exclusions
- Update README with setup instructions, API examples, and project status"

    if git commit -m "$commit_message"; then
        echo -e "${GREEN}✅ Files committed successfully${NC}"
    else
        echo -e "${RED}❌ Failed to commit files${NC}"
        return 1
    fi

    return 0
}

push_to_repository() {
    echo -e "\n${YELLOW}🚀 Pushing to repository...${NC}"

    # Check if we're ahead of remote
    if git status -uno | grep -q "Your branch is ahead"; then
        echo -e "${YELLOW}📤 Branch is ahead of remote, pushing...${NC}"
    fi

    # Push to remote
    if git push origin $BRANCH; then
        echo -e "${GREEN}✅ Successfully pushed to $REPO_URL${NC}"
    else
        echo -e "${RED}❌ Failed to push to repository${NC}"
        echo -e "${YELLOW}💡 Possible causes:${NC}"
        echo -e "  - Authentication issues (check git credentials)"
        echo -e "  - Network connectivity problems"
        echo -e "  - Remote repository doesn't exist"
        echo -e "  - Branch protection rules"
        return 1
    fi

    return 0
}

verify_github_actions() {
    echo -e "\n${YELLOW}🔍 Verifying GitHub Actions...${NC}"

    echo -e "${BLUE}🔗 GitHub Actions URL: ${REPO_URL}/actions${NC}"
    echo -e "${YELLOW}💡 Please check the Actions tab in your repository to verify the CI pipeline${NC}"
    echo -e "${YELLOW}💡 The pipeline should run automatically after the push${NC}"

    return 0
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo -e "${BLUE}🎯 Luce Booking Subsystem Deployment Script${NC}"
    echo -e "${BLUE}==========================================${NC}"

    # Run verifications
    verify_directory_structure || exit 1
    verify_files || exit 1
    verify_git_repository || exit 1

    # Deploy
    add_and_commit_files || exit 1
    push_to_repository || exit 1
    verify_github_actions || exit 1

    # Success message
    echo -e "\n${GREEN}🎉 Deployment completed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${BLUE}📋 Summary:${NC}"
    echo -e "  ${GREEN}✓${NC} All files verified and committed"
    echo -e "  ${GREEN}✓${NC} Pushed to $REPO_URL"
    echo -e "  ${GREEN}✓${NC} GitHub Actions pipeline should be running"
    echo -e "\n${YELLOW}🔍 Next steps:${NC}"
    echo -e "  1. Check GitHub Actions: ${REPO_URL}/actions"
    echo -e "  2. Verify all tests pass"
    echo -e "  3. Review the deployed application"

    return 0
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

# Trap to handle script interruption
trap 'echo -e "\n${RED}⚠️  Script interrupted${NC}"; exit 1' INT

# Check if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi