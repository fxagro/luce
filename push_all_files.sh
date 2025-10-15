#!/bin/bash

# Luce Booking Subsystem - Push All Files to GitHub Script
# This script removes unnecessary files, adds all project files, and pushes to GitHub

set -e  # Exit on any error

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Luce Booking Subsystem - Push All Files to GitHub${NC}"
echo -e "${BLUE}=================================================${NC}"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${PURPLE}[SUCCESS]${NC} $1"
}

# Check if Git is installed
if ! command -v git &> /dev/null; then
    print_error "Git is not installed. Please install Git first."
    echo "Visit: https://git-scm.com/downloads"
    exit 1
fi

# Check if we're in a Git repository
if [ ! -d .git ]; then
    print_error "Not in a Git repository."
    print_status "To initialize a new repository:"
    echo "  git init"
    echo "  git remote add origin https://github.com/fxagro/luce.git"
    exit 1
fi

print_status "Git repository detected."

# Remove unnecessary files before committing
print_status "Cleaning up unnecessary files..."

# Remove notepad file if it exists
if [ -f "notepad" ]; then
    rm "notepad"
    print_status "Removed: notepad"
else
    print_warning "File 'notepad' not found (already cleaned)"
fi

# Remove metrics_controller.rb if it exists
if [ -f "app/controllers/api/v1/metrics_controller.rb" ]; then
    rm "app/controllers/api/v1/metrics_controller.rb"
    print_status "Removed: app/controllers/api/v1/metrics_controller.rb"
else
    print_warning "File 'app/controllers/api/v1/metrics_controller.rb' not found (already cleaned)"
fi

print_status "Cleanup completed."

# Check current Git status
print_status "Checking Git status..."
git status

# Check if there are any changes to add
if git diff --cached --quiet && git diff --quiet; then
    print_warning "No changes to commit."
    echo ""
    print_status "Current repository status:"
    git log --oneline -5 2>/dev/null || echo "No commits yet"
else
    # Add all files
    print_status "Adding all project files..."
    git add .

    # Check what files are staged
    STAGED_FILES=$(git diff --cached --name-only | wc -l)
    print_status "Staged $STAGED_FILES files for commit."

    # Commit with specific message
    print_status "Committing files..."
    git commit -m "Add all project files: controller, service, job, migration, tests, ADR, CI workflow, and scripts

- Add Api::V1::BookingsController with create action and idempotency
- Add Booking::CreateBooking service object with validation and error handling
- Add Booking::MatchProviderJob Sidekiq background job for provider matching
- Add database migration for bookings table with unique client_token constraint
- Add comprehensive RSpec tests for controller, service, and job
- Add ADR document explaining architectural decisions
- Add GitHub Actions CI workflow for automated testing
- Add setup scripts for Git repository and merge conflict resolution
- Add .gitignore for Rails 7 project with PostgreSQL and Redis
- Update README.md with complete documentation and setup instructions"

    print_success "Files committed successfully."
fi

# Check if remote origin exists
if ! git remote get-url origin &> /dev/null; then
    print_error "No remote origin configured."
    print_status "Setting up remote origin for GitHub repository..."
    git remote add origin https://github.com/fxagro/luce.git
else
    print_status "Remote origin configured: $(git remote get-url origin)"
fi

# Check if we can connect to the remote repository
print_status "Testing connection to GitHub repository..."
if ! git ls-remote origin &> /dev/null; then
    print_error "Cannot connect to remote repository. Possible issues:"
    echo "  1. Internet connection problems"
    echo "  2. GitHub repository doesn't exist: https://github.com/fxagro/luce"
    echo "  3. Repository permissions issues"
    echo ""
    print_status "Please ensure:"
    echo "  - The repository exists at https://github.com/fxagro/luce"
    echo "  - You have push permissions to the repository"
    echo "  - Your internet connection is working"
    exit 1
fi

print_status "Successfully connected to GitHub repository."

# Push to GitHub
print_status "Pushing files to GitHub main branch..."
if git push origin main; then
    print_success "Successfully pushed all files to GitHub!"
else
    print_error "Failed to push to GitHub. Possible authentication issues:"
    echo ""
    echo "🔐 Authentication Solutions:"
    echo "1. Set up Personal Access Token:"
    echo "   - Go to GitHub Settings > Developer settings > Personal access tokens"
    echo "   - Generate new token with 'repo' permissions"
    echo "   - Use as password when pushing"
    echo ""
    echo "2. Use SSH instead of HTTPS:"
    echo "   git remote set-url origin git@github.com:fxagro/luce.git"
    echo ""
    echo "3. Configure Git credentials:"
    echo "   git config user.name 'Your Name'"
    echo "   git config user.email 'your.email@example.com'"
    echo ""
    print_status "After fixing authentication, run the script again."
    exit 1
fi

echo ""
echo -e "${GREEN}🎉 All files successfully pushed to GitHub!${NC}"
echo ""
echo -e "${BLUE}📋 Verification Steps:${NC}"
echo "1. 🌐 Check repository files at: https://github.com/fxagro/luce"
echo "   Verify these key files are present:"
echo "   - app/controllers/api/v1/bookings_controller.rb"
echo "   - app/services/booking/create_booking.rb"
echo "   - app/jobs/booking/match_provider_job.rb"
echo "   - db/migrate/20250115092200_add_default_status_and_unique_client_token_to_bookings.rb"
echo "   - spec/requests/api/v1/bookings_spec.rb"
echo "   - spec/services/booking/create_booking_spec.rb"
echo "   - spec/jobs/booking/match_provider_job_spec.rb"
echo "   - doc/adr/0001-booking-refactor.md"
echo "   - .github/workflows/ci.yml"
echo ""
echo "2. 🔄 Check GitHub Actions CI at: https://github.com/fxagro/luce/actions"
echo "   - Verify all tests pass (RSpec, RuboCop, security audit)"
echo "   - Check build duration and status"
echo "   - Review test coverage reports"
echo ""
echo "3. 📊 Repository Statistics:"
echo "   - Branch: $(git branch --show-current)"
echo "   - Last commit: $(git log --oneline -1)"
echo "   - Remote URL: $(git remote get-url origin)"
echo ""

# Optional: Open repository in browser
if command -v xdg-open &> /dev/null; then
    read -p "Open repository in browser? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        xdg-open "https://github.com/fxagro/luce"
    fi
elif command -v open &> /dev/null; then
    read -p "Open repository in browser? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        open "https://github.com/fxagro/luce"
    fi
fi

print_status "Push operation completed successfully!"
echo ""
print_status "Next steps:"
echo "  - Monitor GitHub Actions for test results"
echo "  - Review any feedback or issues in the repository"
echo "  - Update documentation if needed"