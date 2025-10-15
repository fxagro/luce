#!/bin/bash

# ============================================================================
# README Update and Deployment Script
# ============================================================================
# This script commits the updated README.md with architecture diagram,
# CI/CD badge, and Future Improvements section, then pushes to GitHub.
#
# Usage: ./commit_and_push_readme.sh
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

echo -e "${BLUE}📝 Starting README update and deployment...${NC}"

# ============================================================================
# VERIFICATION FUNCTIONS
# ============================================================================

verify_readme_exists() {
    echo -e "\n${YELLOW}📄 Verifying README.md exists...${NC}"

    if [ ! -f "README.md" ]; then
        echo -e "${RED}❌ README.md not found${NC}"
        return 1
    fi

    echo -e "${GREEN}✅ README.md exists${NC}"
    return 0
}

verify_readme_content() {
    echo -e "\n${YELLOW}🔍 Verifying README.md content...${NC}"

    # Check for required sections
    local required_sections=(
        "Architecture Overview"
        "Future Improvements"
        "mermaid"
        "GitHub Actions CI"
    )

    local missing_sections=()

    for section in "${required_sections[@]}"; do
        if ! grep -q "$section" README.md; then
            missing_sections+=("$section")
        fi
    done

    if [ ${#missing_sections[@]} -ne 0 ]; then
        echo -e "${RED}❌ Missing sections in README.md:${NC}"
        for section in "${missing_sections[@]}"; do
            echo -e "  ${RED}✗${NC} $section"
        done
        return 1
    fi

    echo -e "${GREEN}✅ All required sections found in README.md${NC}"
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

add_readme() {
    echo -e "\n${YELLOW}📦 Adding README.md to Git...${NC}"

    if git add README.md; then
        echo -e "${GREEN}✅ README.md added to staging area${NC}"
    else
        echo -e "${RED}❌ Failed to add README.md${NC}"
        return 1
    fi

    return 0
}

commit_readme() {
    echo -e "\n${YELLOW}💾 Committing README.md...${NC}"

    # Check if there are changes to commit
    if git diff --cached --quiet; then
        echo -e "${YELLOW}⚠️  No changes to commit${NC}"
        return 0
    fi

    local commit_message="Update README with architecture diagram, CI/CD badge, and Future Improvements section

- Add GitHub Actions CI/CD badge for build status visibility
- Add Architecture Overview section with Mermaid flowchart diagram
- Add Future Improvements section with sharding, rate limiting, and Kafka streaming
- Enhance documentation for technical reviewers and evaluators"

    if git commit -m "$commit_message"; then
        echo -e "${GREEN}✅ README.md committed successfully${NC}"
    else
        echo -e "${RED}❌ Failed to commit README.md${NC}"
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

verify_deployment() {
    echo -e "\n${YELLOW}🔍 Verifying deployment...${NC}"

    echo -e "${BLUE}📖 README URL: ${REPO_URL}${NC}"
    echo -e "${BLUE}🔗 GitHub Actions URL: ${REPO_URL}/actions${NC}"

    echo -e "\n${YELLOW}💡 Verification steps:${NC}"
    echo -e "  1. Check README rendering: ${REPO_URL}"
    echo -e "  2. Verify Mermaid diagram displays correctly"
    echo -e "  3. Confirm CI/CD badge shows build status"
    echo -e "  4. Check GitHub Actions: ${REPO_URL}/actions"
    echo -e "  5. Verify pipeline runs after push"

    return 0
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo -e "${BLUE}📋 README Update and Deployment Script${NC}"
    echo -e "${BLUE}=====================================${NC}"

    # Run verifications
    verify_readme_exists || exit 1
    verify_readme_content || exit 1
    verify_git_repository || exit 1

    # Deploy
    add_readme || exit 1
    commit_readme || exit 1
    push_to_repository || exit 1
    verify_deployment || exit 1

    # Success message
    echo -e "\n${GREEN}🎉 README update completed successfully!${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${BLUE}📋 Summary:${NC}"
    echo -e "  ${GREEN}✓${NC} README.md verified with new sections"
    echo -e "  ${GREEN}✓${NC} Changes committed and pushed"
    echo -e "  ${GREEN}✓${NC} GitHub Actions pipeline should be running"
    echo -e "\n${YELLOW}🔍 Next steps:${NC}"
    echo -e "  1. Verify README at: ${REPO_URL}"
    echo -e "  2. Check Actions tab: ${REPO_URL}/actions"
    echo -e "  3. Confirm Mermaid diagram renders correctly"

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