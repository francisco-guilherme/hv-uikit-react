#!/bin/bash

set -euo pipefail

# Configuration
GITHUB_REPO_URL=${GITHUB_REPO_URL:-"https://github.com/francisco-guilherme/hv-uikit-react"}

# Version packages using Lerna
version_packages() {
    pre_release=false
    [[ ${1:-} == "--next" ]] && pre_release=true

    # Construct the versioning command based on the pre_release flag
    publish_command="npx lerna publish"
    if [[ $pre_release == true ]]; then
        publish_command+=" --conventional-prerelease"
    else
        publish_command+=" --conventional-graduate --force-conventional-graduate"
    fi

    echo "=== Versioning packages with command: $publish_command"

    # Execute the versioning command
    if ! eval "$publish_command"; then
        echo -e "Failed to version packages"
    fi

    # Get the new version
    new_version=$(npx lerna ls --json | jq -r '.[0].version')
}

# Commit and tag changes
commit_and_tag() {
    echo -e "\n=== Committing and tagging: 'v$new_version' \n"

    commit_message="chore: release v$new_version"

    # Commit and tag changes
    git add . && git commit -m "$commit_message" || roll_back "Failed to commit changes."

    # Tag the commit
    git tag "v$new_version" || roll_back "Failed to tag changes."
}

# Create a GitHub release
create_github_release() {
    echo -e "\n=== Creating GitHub release: 'v$new_version' \n"

    # Create temporary files for changelog and package commits
    changelog=$(mktemp)
    package_commits_file=$(mktemp)
    create_release=false

    # Get the previous tag
    previous_tag=$(git describe --tags $(git tag --sort=-creatordate | sed -n 2p))

    # Generate the changelog
    generate_changelog

    # Check if there are any valid commits to create a release
    if [[ $create_release == false ]]; then
        rm "$package_commits_file" "$changelog"
        roll_back "No valid commits found to create release."
    fi

    # Append package commits to changelog
    cat "$package_commits_file" >>"$changelog"

    # Add compare changes link
    echo "##### [View changes on GitHub]($GITHUB_REPO_URL/compare/$previous_tag...v$new_version)" >>"$changelog"

    # Read the changelog into a variable and remove temporary files
    release_notes=$(<"$changelog")
    rm "$package_commits_file" "$changelog"

    # Create GitHub release
    if ! gh release create "v$new_version" --title "v$new_version" --notes "$release_notes"; then
        roll_back "Failed to create GitHub release."
    fi

    # Push changes to the remote repository
    if ! git push origin master; then
        roll_back "Failed to push changes to the remote repository."
    fi
}

# Generate changelog
generate_changelog() {
    # Initialize changelog with the current date
    echo "_$(date +'%b %d, %Y')_" >"$changelog"

    # Loop through all packages listed by lerna
    for pkg in $(npx lerna ls --all --json | jq -r '.[].location'); do
        pkg_name=$(basename "$pkg")
        pkg_version=$(jq -r '.version' "$pkg/package.json")

        # Get commits for the package since the last tag, excluding chore commits
        commits=$(git log "$previous_tag..HEAD" --pretty=format:"%h %s -" -- "$pkg" | grep -v "chore") || continue

        [[ -n "$commits" ]] && {
            echo "### $pkg_name@$pkg_version" >>"$package_commits_file"
            echo "$commits" | while read -r commit; do
                commit_hash=$(echo "$commit" | awk '{print $1}')
                commit_message=$(echo "$commit" | sed -e 's/^.*[0-9a-f]\{7\} //')

                # Add commit message to the package commits file
                echo "- $commit_message [\`$commit_hash\`]($GITHUB_REPO_URL/commit/$commit_hash)" >>"$package_commits_file"
            done
            echo "" >>"$package_commits_file"

            # Set flag to create release if there are valid commits
            create_release=true
        }
    done
}

# Rollback changes
roll_back() {
    echo -e "$1"
    echo -e "\n=== Rolling back... \n"

    git reset --hard HEAD~1
    git tag -d "v$new_version"

    exit 1
}

# Main script execution
version_packages "${1:-}"
commit_and_tag
create_github_release
