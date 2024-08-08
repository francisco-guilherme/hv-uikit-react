#!/bin/bash

if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "Error: GITHUB_TOKEN environment variable is not set."
    exit 1
fi

# Version packages using lerna
version_packages() {
    local version_command="npx lerna version"
    [[ ${1:-} == "--next" ]] && version_command+=" --conventional-prerelease" || version_command+=" --conventional-graduate --force-conventional-graduate"

    echo "=== Versioning packages with command: $version_command"
    if ! eval "$version_command"; then
        echo "Failed to version packages"
        exit 1
    fi
}

# Get the new version from the next-ui-core package
get_new_version() {
    npx lerna ls --json | jq -r '.[0].version'
}

# Commit and push changes to the remote repository
commit_and_push_changes() {
    local new_version=$1
    local commit_message="chore: release v$new_version"
    local current_branch=$(git rev-parse --abbrev-ref HEAD)

    echo -e "\n=== Committing and pushing changes: 'v$new_version' \n"
    git add . && git commit -m "$commit_message" && git tag "v$new_version" || {
        echo "Failed to commit changes."
        exit 1
    }

    git push francisco-guilherme $current_branch --tags || {
        echo "Failed to push changes to the remote repository."
        rollback "$new_version"
        exit 1
    }
}

# Create GitHub release using changelogithub
create_github_release() {
    local new_version=$1

    echo -e "\n=== Creating GitHub release \n"
    if ! npx changelogithub; then
        echo "Failed to create GitHub release."
        rollback "$new_version"
        exit 1
    fi
}

# Rollback function to undo changes
rollback() {
    local new_version=$1

    echo "Rolling back changes..."
    git reset --hard HEAD~1
    git tag -d "v$new_version"
    echo "Rollback completed."
}

# Main script execution
version_packages "$1"
new_version=$(get_new_version)
commit_and_push_changes "$new_version"
create_github_release "$new_version"