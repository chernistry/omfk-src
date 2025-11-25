#!/bin/bash
set -e

echo "🔍 O.M.F.K Project Verification"
echo "================================"
echo ""

# Check Xcode
echo "✓ Checking Xcode..."
xcodebuild -version | head -1

# Check Swift
echo "✓ Checking Swift..."
swift --version | head -1

# Check project structure
echo "✓ Checking project structure..."
required_files=(
    "Package.swift"
    "README.md"
    "OMFK/Sources/OMFKApp.swift"
    "OMFK/Sources/Core/LanguageDetector.swift"
    "OMFK/Sources/Core/LayoutMapper.swift"
    "OMFK/Sources/Engine/CorrectionEngine.swift"
    "OMFK/Sources/Engine/EventMonitor.swift"
    "OMFK/Sources/Settings/SettingsManager.swift"
    "OMFK/Sources/UI/MenuBarView.swift"
    "OMFK/Sources/UI/SettingsView.swift"
    "OMFK/Sources/UI/HistoryView.swift"
    "OMFK/Resources/Info.plist"
    "OMFK/Tests/LanguageDetectorTests.swift"
    "OMFK/Tests/LayoutMapperTests.swift"
)

for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        echo "❌ Missing file: $file"
        exit 1
    fi
done
echo "  All required files present"

# Build project
echo "✓ Building project..."
swift build -c release > /dev/null 2>&1
echo "  Build successful"

# Run tests
echo "✓ Running tests..."
test_output=$(swift test 2>&1)
if echo "$test_output" | grep -q "Test Suite 'All tests' passed"; then
    test_count=$(echo "$test_output" | grep -o "Executed [0-9]* tests" | grep -o "[0-9]*")
    echo "  All $test_count tests passed"
else
    echo "❌ Tests failed"
    exit 1
fi

# Check binary
echo "✓ Checking binary..."
if [ -f ".build/release/OMFK" ]; then
    size=$(du -h .build/release/OMFK | cut -f1)
    echo "  Binary size: $size"
else
    echo "❌ Binary not found"
    exit 1
fi

# Count lines of code
echo "✓ Counting lines of code..."
swift_lines=$(find OMFK/Sources -name "*.swift" -exec wc -l {} + | tail -1 | awk '{print $1}')
test_lines=$(find OMFK/Tests -name "*.swift" -exec wc -l {} + | tail -1 | awk '{print $1}')
total_lines=$((swift_lines + test_lines))
echo "  Source: $swift_lines lines"
echo "  Tests: $test_lines lines"
echo "  Total: $total_lines lines"

echo ""
echo "================================"
echo "✅ All checks passed!"
echo ""
echo "Next steps:"
echo "  1. Run: swift run"
echo "  2. Grant Accessibility permissions"
echo "  3. Grant Input Monitoring permissions"
echo "  4. Start typing!"
echo ""
