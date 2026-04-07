#!/usr/bin/env bash
set -euo pipefail

# ---------------------------
# Configuration
# ---------------------------
ORG="Illumio-Training"
TAG="ilt"
# The API key is read from an environment variable
API_KEY="${INSTRUQT_API_KEY:?Environment variable INSTRUQT_API_KEY is not set}"
# Base backup directory is your cloned GitHub repo
BASE_BACKUP_DIR="$HOME/Documents/instruqt-backup"
PARALLEL_JOBS=5

# Create a dated backup folder
BACKUP_DIR="$BASE_BACKUP_DIR/$(date +%Y-%m-%d)"
mkdir -p "$BACKUP_DIR"

echo "Fetching tracks with tag: $TAG..."

# ---------------------------
# Fetch tracks from API
# ---------------------------
RESPONSE=$(curl -s -X POST https://play.instruqt.com/graphql \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"{ tracks(organizationSlug: \\\"$ORG\\\") { slug tags } }\"}"
)

if [[ -z "$RESPONSE" ]]; then
    echo "Error: No response from API."
    exit 1
fi

# ---------------------------
# Case-insensitive tag matching
# ---------------------------
SLUGS=$(echo "$RESPONSE" | jq -r --arg TAG "$TAG" '
  .data.tracks? // [] | select(. != null) | .[] |
  select(any(.tags[]?; ascii_downcase == ($TAG | ascii_downcase))) |
  .slug
')

if [[ -z "$SLUGS" ]]; then
    echo "No tracks found with tag '$TAG'. Exiting."
    exit 0
fi

echo "Found tracks:"
echo "$SLUGS"

# ---------------------------
# Pull tracks in parallel
# ---------------------------
echo "$SLUGS" | xargs -P "$PARALLEL_JOBS" -I {} bash -c '
SLUG="$1"
ORG="$2"
BACKUP_DIR="$3"

TRACK_DIR="$BACKUP_DIR/$SLUG"
mkdir -p "$TRACK_DIR"

echo "Pulling $ORG/$SLUG..."

cd "$TRACK_DIR"

if instruqt track pull "$ORG/$SLUG" --force; then
    echo "[SUCCESS] $SLUG"
else
    echo "[FAILED] $SLUG" >> "$BACKUP_DIR/failed.log"
fi
' _ {} "$ORG" "$BACKUP_DIR"

echo "Backup finished. All files are in $BACKUP_DIR"

# ---------------------------
# Git commit & push
# ---------------------------
cd "$BASE_BACKUP_DIR"

git add .

# Only commit if there are changes
if git diff --cached --quiet; then
    echo "No changes to commit."
else
    git commit -m "Instruqt backup $(date '+%Y-%m-%d %H:%M')"
    git push origin main
    echo "Backup committed and pushed to GitHub."
fi