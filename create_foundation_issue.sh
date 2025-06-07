#!/bin/bash

# Script to create GitHub issue for Foundation ExUnit race condition
# Usage: ./create_foundation_issue.sh

REPO="nshkrdotcom/foundation"
TITLE="Foundation Telemetry Handlers Cause Race Condition with ExUnit Lifecycle"
LABELS="bug,priority:urgent,telemetry,testing"

echo "Creating GitHub issue for Foundation ExUnit race condition..."
echo "Repository: $REPO"
echo "Title: $TITLE"
echo ""

# Check if GitHub CLI is available
if command -v gh &> /dev/null; then
    echo "Using GitHub CLI to create issue..."
    gh issue create \
        --repo "$REPO" \
        --title "$TITLE" \
        --body-file "foundation_exunit_race_condition_issue.md" \
        --label "$LABELS"
    
    if [ $? -eq 0 ]; then
        echo "✅ Issue created successfully!"
    else
        echo "❌ Failed to create issue with GitHub CLI"
        echo "📋 Manual creation instructions below:"
    fi
else
    echo "GitHub CLI not found. Manual creation instructions:"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 MANUAL GITHUB ISSUE CREATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Go to: https://github.com/$REPO/issues/new"
echo "2. Title: $TITLE"
echo "3. Labels: $LABELS"
echo "4. Body: Copy content from foundation_exunit_race_condition_issue.md"
echo ""
echo "📄 Issue content file: foundation_exunit_race_condition_issue.md"
echo "📏 File size: $(wc -l < foundation_exunit_race_condition_issue.md) lines"
echo ""
echo "🔗 Direct link: https://github.com/$REPO/issues/new?title=$(echo "$TITLE" | sed 's/ /%20/g')&labels=$LABELS"
echo ""
echo "✅ Ready to create issue!" 