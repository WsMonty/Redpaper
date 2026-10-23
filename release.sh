#!/bin/bash
# Releases a version: ./release.sh 1.3
# Checks the repo, tags, builds and self-tests, then pushes the tag and publishes a GitHub release
# with that version's section of RELEASE_NOTES.md as its notes.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=${1#v}
TAG=v$VERSION
fail() { echo "$*" >&2; exit 1; }

[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]] || fail "Usage: ./release.sh <version>, e.g. ./release.sh 1.3"
command -v gh >/dev/null || fail "GitHub CLI not found. Install it with: brew install gh"
[[ "$(git branch --show-current)" == main ]] || fail "Switch to main first."
[[ -z "$(git status --porcelain)" ]] || fail "Commit or stash your changes first."
git fetch -q origin main --tags
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main isn't in sync with origin/main. Pull or push first."
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || fail "$TAG already exists."
LATEST=$(git describe --tags --abbrev=0 2>/dev/null || echo v0)
[[ "$(printf '%s\n' "${LATEST#v}" "$VERSION" | sort -V | tail -1)" == "$VERSION" ]] || fail "$TAG isn't newer than $LATEST."

# The lines under "## <version>", up to the next "## " heading.
NOTES=$(awk -v h="## $VERSION" '$0 == h { on = 1; next } /^## / { on = 0 } on' RELEASE_NOTES.md | sed '/./,$!d')
[[ -n "$NOTES" ]] || fail "Add a '## $VERSION' section with notes to RELEASE_NOTES.md and commit it first."

echo "Release notes for $TAG:"
echo "$NOTES"
echo
read -r -p "Tag, build and publish $TAG? [y/N] " answer
[[ "$answer" == [yY] ]] || fail "Cancelled."

# build.sh takes the version from the latest tag, so tag first; drop the tag again if the build fails.
git tag "$TAG"
trap 'git tag -d "$TAG" >/dev/null; echo "Build failed; removed tag $TAG." >&2' ERR
./build.sh
build/Redpaper.app/Contents/MacOS/Redpaper --selftest
trap - ERR

git push origin "$TAG"
gh release create "$TAG" --title "Redpaper $VERSION" --notes "$NOTES"
echo "Released $TAG. Run ./deploy.sh to install it here."
