#!/bin/bash

# Luce Booking Subsystem - Merge Conflict Resolution and Push Script
# This script resolves merge conflicts in README.md and pushes to GitHub

set -e  # Exit on any error

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 Luce Booking Subsystem - Merge Conflict Resolution${NC}"
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

# Check if Git is installed
if ! command -v git &> /dev/null; then
    print_error "Git is not installed. Please install Git first."
    exit 1
fi

# Check if we're in a Git repository
if [ ! -d .git ]; then
    print_error "Not in a Git repository. Please run this script from the project root."
    exit 1
fi

print_status "Git repository detected."

# Configure Git for Windows line ending handling
print_status "Configuring Git for cross-platform compatibility..."
git config core.autocrlf true

# Check if there are any merge conflicts
if git diff --name-only | grep -q "README.md"; then
    print_warning "Merge conflict detected in README.md"
elif git diff --cached --name-only | grep -q "README.md"; then
    print_warning "Staged changes detected in README.md"
else
    print_status "No merge conflicts detected in README.md"
fi

# Check if README.md exists
if [ ! -f "README.md" ]; then
    print_error "README.md file not found in the current directory."
    exit 1
fi

print_status "README.md file found."

# Check if remote origin exists
if ! git remote get-url origin &> /dev/null; then
    print_error "No remote origin configured."
    print_status "Setting up remote origin for GitHub repository..."
    git remote add origin https://github.com/fxagro/luce.git
else
    print_status "Remote origin already configured: $(git remote get-url origin)"
fi

# Check if we can connect to the remote repository
print_status "Testing connection to GitHub repository..."
if ! git ls-remote origin &> /dev/null; then
    print_error "Cannot connect to remote repository. Please check:"
    echo "  1. Internet connection"
    echo "  2. GitHub repository exists: https://github.com/fxagro/luce"
    echo "  3. Repository permissions"
    exit 1
fi

print_status "Successfully connected to GitHub repository."

# Check current branch
CURRENT_BRANCH=$(git branch --show-current)
print_status "Current branch: $CURRENT_BRANCH"

# Check if we're on main branch
if [ "$CURRENT_BRANCH" != "main" ]; then
    print_warning "Not on main branch. Switching to main branch..."
    git checkout main
fi

# Fetch latest changes from remote
print_status "Fetching latest changes from remote repository..."
git fetch origin

# Check if there are differences between local and remote
REMOTE_COMMIT=$(git rev-parse origin/main 2>/dev/null || echo "")
LOCAL_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "")

if [ "$REMOTE_COMMIT" != "$LOCAL_COMMIT" ] && [ ! -z "$REMOTE_COMMIT" ]; then
    print_warning "Local and remote branches differ."

    # Try to merge remote changes
    print_status "Attempting to merge remote changes..."
    if git merge origin/main; then
        print_status "Successfully merged remote changes."
    else
        print_warning "Merge conflict detected. Resolving conflict..."

        # Check if README.md has conflicts
        if grep -q "<<<<<<< HEAD\|=======\|>>>>>>> " README.md; then
            print_status "Resolving merge conflict in README.md..."

            # Create backup of current README.md
            cp README.md README.md.backup.$(date +%Y%m%d_%H%M%S)

            # Remove conflict markers and keep local version
            awk '
            /^<<<<<<< HEAD/ { in_conflict=1; next }
            /^=======$/ { if (in_conflict) { next } }
            /^>>>>>>> / { in_conflict=0; next }
            { print }
            ' README.md > README.md.tmp

            mv README.md.tmp README.md

            print_status "Merge conflict resolved. Local version of README.md preserved."
            print_status "Backup saved as: README.md.backup.$(date +%Y%m%d_%H%M%S)"

            # Mark as resolved
            git add README.md

            # Commit the merge resolution
            git commit -m "Resolve merge conflict in README.md

- Keep local version of README.md
- Discard remote changes to avoid conflicts
- Backup of original file created"

            print_status "Merge conflict resolved and committed."
        else
            print_error "Merge failed but no conflict markers found in README.md"
            print_error "Please resolve conflicts manually and run the script again."
            exit 1
        fi
    fi
else
    print_status "Local and remote branches are in sync."
fi

# Push changes to GitHub
print_status "Pushing changes to GitHub..."
if git push origin main; then
    print_status "Successfully pushed changes to GitHub!"
else
    print_error "Failed to push to GitHub. Possible reasons:"
    echo "  1. Authentication issues (configure Git credentials)"
    echo "  2. Permission issues (check repository access)"
    echo "  3. Network connectivity issues"
    echo ""
    echo "To fix authentication, try:"
    echo "  git config user.name 'Your Name'"
    echo "  git config user.email 'your.email@example.com'"
    echo ""
    echo "Or use SSH instead of HTTPS:"
    echo "  git remote set-url origin git@github.com:fxagro/luce.git"
    exit 1
fi

echo ""
echo -e "${GREEN}🎉 Merge conflict resolution and push completed successfully!${NC}"
echo ""
echo -e "${BLUE}📋 Next steps for verification:${NC}"
echo "1. Check your repository on GitHub: https://github.com/fxagro/luce"
echo "2. Verify GitHub Actions CI is running: https://github.com/fxagro/luce/actions"
echo "3. Check that README.md displays correctly on GitHub"
echo "4. Ensure all tests pass in the CI pipeline"
echo ""
echo -e "${BLUE}🔧 Troubleshooting:${NC}"
echo "- If you see line ending issues, the script configured 'core.autocrlf true'"
echo "- If authentication fails, configure your Git credentials"
echo "- For SSH access, use: git remote set-url origin git@github.com:fxagro/luce.git"
echo ""
echo -e "${BLUE}📊 Repository Status:${NC}"
echo "Repository URL: https://github.com/fxagro/luce"
echo "Branch: $(git branch --show-current)"
echo "Last commit: $(git log --oneline -1)"

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

print_status "Script completed successfully!"