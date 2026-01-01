# OMFK Tests

## Structure

```
tests/
├── run_tests.py                    # Main E2E test runner
├── test_github_issues.py           # GitHub issues validation
├── test_cases.json                 # Comprehensive test cases
├── github_issues_test_cases.json   # Issue-specific test cases
├── utils/                          # Test utilities
│   ├── real_typing.py             # Keyboard simulation
│   ├── keycodes.json              # Keycode mappings
│   └── generate_keycodes.py       # Keycode generator
└── archived/                       # Deprecated test data
```

## Running Tests

### Main E2E Tests
```bash
# Run all tests
python3 tests/run_tests.py

# Run specific category
python3 tests/run_tests.py --real-typing single_words
python3 tests/run_tests.py --real-typing cycling
python3 tests/run_tests.py --real-typing paragraphs

# Run with specific test file
python3 tests/run_tests.py --test-file tests/github_issues_test_cases.json
```

### GitHub Issues Tests
```bash
python3 tests/test_github_issues.py
```

### Swift Unit Tests
```bash
# Run all unit tests
swift test

# Run specific test
swift test --filter LayoutVariantFallbackTests
```

## Test Types

### E2E Tests (Python)
- **Location**: `tests/`
- **Purpose**: End-to-end testing with real keyboard events
- **Test Data**: JSON files with input/expected pairs
- **Runner**: `run_tests.py`

### Unit Tests (Swift)
- **Location**: `OMFK/Tests/`
- **Purpose**: Component-level testing
- **Framework**: XCTest
- **Run**: `swift test`

## Adding New Tests

### E2E Test Cases
Add to `test_cases.json` or `github_issues_test_cases.json`:
```json
{
  "category_name": {
    "description": "Category description",
    "cases": [
      {
        "input": "ghbdtn",
        "expected": "привет",
        "desc": "Test description"
      }
    ]
  }
}
```

### Swift Unit Tests
Add new test file to `OMFK/Tests/`:
```swift
import XCTest
@testable import OMFK

final class MyFeatureTests: XCTestCase {
    func testSomething() {
        // Test code
    }
}
```

## Utilities

- `utils/real_typing.py` - Keyboard event simulation
- `utils/keycodes.json` - Physical keycode mappings
- `utils/generate_keycodes.py` - Generate keycode mappings from Swift
