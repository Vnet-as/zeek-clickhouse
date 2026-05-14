# Development Guide - Zeek ClickHouse Input Reader Plugin

This guide is for developers who want to contribute to, extend, or understand the internals of the Zeek ClickHouse Input Reader plugin.

## Table of Contents

- [Development Environment Setup](#development-environment-setup)
- [Building for Development](#building-for-development)
- [Code Structure](#code-structure)
- [Adding New Features](#adding-new-features)
- [Testing](#testing)
- [Debugging](#debugging)
- [Code Style](#code-style)
- [Contribution Workflow](#contribution-workflow)
- [Release Process](#release-process)

## Development Environment Setup

### Required Tools

```bash
# Compiler and build tools
sudo apt-get install build-essential cmake git

# Zeek development files
sudo apt-get install zeek zeek-dev

# ClickHouse C++ client (from source)
git clone https://github.com/ClickHouse/clickhouse-cpp.git
cd clickhouse-cpp
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)
sudo make install
```

### Optional Tools

```bash
# Debugging
sudo apt-get install gdb valgrind

# Code analysis
sudo apt-get install clang-tidy cppcheck

# Documentation
sudo apt-get install doxygen graphviz

# Version control
sudo apt-get install git git-flow
```

### IDE Setup

#### Visual Studio Code

Install extensions:
- C/C++ (Microsoft)
- CMake Tools
- Zeek Language Support

`.vscode/settings.json`:
```json
{
    "cmake.configureArgs": [
        "-DCMAKE_BUILD_TYPE=Debug",
        "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
    ],
    "C_Cpp.default.compileCommands": "${workspaceFolder}/build/compile_commands.json",
    "files.associations": {
        "*.zeek": "zeek",
        "*.bif": "cpp"
    }
}
```

#### CLion

1. Open project directory
2. CLion will automatically detect CMakeLists.txt
3. Set CMake options: `-DCMAKE_BUILD_TYPE=Debug`
4. Configure Zeek paths if needed

## Building for Development

### Debug Build

```bash
mkdir build-debug && cd build-debug
cmake .. -DCMAKE_BUILD_TYPE=Debug \
         -DCMAKE_CXX_FLAGS="-g -O0 -Wall -Wextra" \
         -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
make -j$(nproc)
```

### Development Installation

```bash
# Install to local directory without sudo
export ZEEK_PLUGIN_PATH=$HOME/.zeek/plugins
mkdir -p $ZEEK_PLUGIN_PATH

# Copy plugin after building
cp -r VNET_ClickHouse $ZEEK_PLUGIN_PATH/

# Or use symbolic link for faster iteration
ln -s $(pwd)/VNET_ClickHouse $ZEEK_PLUGIN_PATH/
```

### Quick Rebuild Script

Create `rebuild.sh`:
```bash
#!/bin/bash
set -e

cd build-debug
make -j$(nproc)
cp -r VNET_ClickHouse $HOME/.zeek/plugins/

echo "Plugin rebuilt and installed"
zeek -N VNET::ClickHouse
```

## Code Structure

### Plugin Architecture

```
Plugin (Plugin.cc)
    ├── Registers Reader Component
    └── Provides Plugin Metadata

ReaderBackend (ClickHouse.cc)
    ├── Connection Management
    ├── Query Execution
    ├── Type Conversion
    └── Data Streaming
```

### Key Classes

#### Plugin Class

**Location**: `src/Plugin.h`, `src/Plugin.cc`

**Responsibilities**:
- Plugin registration
- Component registration
- Metadata provision

**Key Methods**:
```cpp
zeek::plugin::Configuration Configure() override;
```

#### ClickHouse Reader Class

**Location**: `src/ClickHouse.h`, `src/ClickHouse.cc`

**Responsibilities**:
- ClickHouse connection
- Query execution
- Data conversion
- Streaming/polling

**Key Methods**:
```cpp
// Initialization
bool DoInit(const ReaderInfo& info, int num_fields,
            const Field* const* fields) override;

// Data retrieval
bool DoUpdate() override;
bool DoHeartbeat(double network_time, double current_time) override;

// Cleanup
void DoClose() override;

// Internal methods
bool ExecuteQuery();
bool ConvertValue(const clickhouse::Column& column, size_t row,
                  const Field* field, Value* val);
```

### Data Flow

#### Initialization Phase

```cpp
// 1. Plugin loads
Plugin::Configure()
    → AddComponent(new ::input::Component("ClickHouse", ...))

// 2. User calls Input::add_table()
User Script
    → Input::add_table()
    → ClickHouse::Instantiate()
    → ClickHouse::DoInit()
        → ParseConfig()
        → Connect to ClickHouse
        → ExecuteQuery()
```

#### Query Execution Phase

```cpp
// 3. Execute query
ExecuteQuery()
    → client_->Select(query_, callback)
    → For each Block:
        → For each Row:
            → For each Column:
                → ConvertValue()
                → Put(values)
```

#### Streaming Phase

```cpp
// 4. Periodic updates (if poll_interval > 0)
DoHeartbeat()
    → Check if interval elapsed
    → ExecuteQuery()
    → Process new data
```

## Adding New Features

### Adding a Configuration Option

**1. Add to ClickHouse::Info record** (`scripts/clickhouse.zeek`):
```zeek
type Info: record {
    # ... existing fields ...
    my_new_option: string &default="default_value";
};
```

**2. Add member variable** (`src/ClickHouse.h`):
```cpp
private:
    std::string my_new_option_;
```

**3. Parse in ParseConfig()** (`src/ClickHouse.cc`):
```cpp
bool ClickHouse::ParseConfig(const ReaderInfo& info)
{
    // ... existing parsing ...
    
    else if (key == "my_new_option")
    {
        my_new_option_ = value;
    }
    
    return true;
}
```

**4. Use in implementation**:
```cpp
bool ClickHouse::DoInit(...)
{
    // Use my_new_option_ as needed
}
```

**5. Update config_to_table()** (`scripts/clickhouse.zeek`):
```zeek
function config_to_table(info: Info): table[string] of string
{
    # ... existing config ...
    config["my_new_option"] = info$my_new_option;
    return config;
}
```

### Adding Type Conversion Support

**1. Identify ClickHouse and Zeek types**

**2. Add conversion case** (`src/ClickHouse.cc`):
```cpp
bool ClickHouse::ConvertValue(const clickhouse::Column& column, size_t row,
                               const Field* field, Value* val)
{
    switch (field->type)
    {
        // ... existing cases ...
        
        case TYPE_MY_NEW_TYPE:
        {
            // Extract from ClickHouse
            auto str_val = GetColumnStringValue(column, row);
            
            // Convert to Zeek type
            // Set val->val.my_type_val = ...
            
            break;
        }
    }
    
    val->present = true;
    return true;
}
```

**3. Handle ClickHouse-specific types**:
```cpp
std::string ClickHouse::GetColumnStringValue(const clickhouse::Column& column, size_t row)
{
    auto type_code = column.Type()->GetCode();
    
    switch (type_code)
    {
        // ... existing cases ...
        
        case clickhouse::Type::MyNewType:
        {
            auto col = column.As<clickhouse::ColumnMyNewType>();
            // Extract and convert
            return converted_value;
        }
    }
}
```

### Adding an Event Handler

**1. Define event in BIF** (`src/clickhouse.bif`):
```
module ClickHouse;

export {
    ## Event raised when query completes
    global query_complete: event(name: string, rows: count);
}
```

**2. Raise event in implementation** (`src/ClickHouse.cc`):
```cpp
bool ClickHouse::ExecuteQuery()
{
    size_t total_rows = 0;
    
    client_->Select(query_, [&](const clickhouse::Block& block)
    {
        total_rows += block.GetRowCount();
        // ... process rows ...
    });
    
    // Raise event
    val_mgr->QueueEventFast(
        ClickHouse::query_complete,
        val_mgr->Count(total_rows)
    );
    
    return true;
}
```

## Testing

### Unit Testing

Currently, the plugin doesn't have automated unit tests. Here's how to add them:

**1. Create test directory**:
```bash
mkdir tests
```

**2. Add test framework** (e.g., Google Test):
```cmake
# In CMakeLists.txt
enable_testing()
find_package(GTest REQUIRED)

add_executable(plugin_tests tests/test_main.cc)
target_link_libraries(plugin_tests GTest::GTest ${_plugin_lib})
add_test(NAME plugin_tests COMMAND plugin_tests)
```

**3. Write tests**:
```cpp
// tests/test_conversion.cc
#include <gtest/gtest.h>
#include "ClickHouse.h"

TEST(ConversionTest, IntegerConversion) {
    // Test integer conversion
}

TEST(ConversionTest, StringConversion) {
    // Test string conversion
}
```

### Integration Testing

**1. Set up test ClickHouse database**:
```sql
CREATE DATABASE zeek_plugin_test;

CREATE TABLE zeek_plugin_test.test_data (
    id UInt32,
    value String
) ENGINE = Memory;

INSERT INTO zeek_plugin_test.test_data VALUES (1, 'test');
```

**2. Create test script**:
```zeek
# tests/integration/test_basic.zeek
@load VNET/ClickHouse

type TestRec: record {
    id: count;
    value: string;
};

global test_table: table[count] of TestRec;

event zeek_init()
{
    local info = ClickHouse::Info(
        $database = "zeek_plugin_test",
        $query = "SELECT id, value FROM test_data"
    );
    
    Input::add_table([...]);
}

event Input::end_of_data(name: string, source: string)
{
    if (|test_table| != 1) {
        print "FAIL: Expected 1 row";
        exit(1);
    }
    print "PASS";
    exit(0);
}
```

**3. Run test**:
```bash
zeek tests/integration/test_basic.zeek
```

### Manual Testing

```bash
# Test compilation
cd build-debug && make

# Test plugin loading
zeek -N VNET::ClickHouse

# Test with minimal script
zeek -e '@load VNET/ClickHouse; event zeek_init() { print "OK"; }'

# Test with example
zeek examples/simple-watchlist.zeek

# Test with PCAP
zeek -r test.pcap examples/threat-intel.zeek
```

## Debugging

### Using GDB

```bash
# Build with debug symbols
cmake .. -DCMAKE_BUILD_TYPE=Debug

# Run Zeek under GDB
gdb --args zeek test-script.zeek

# Set breakpoints
(gdb) break ClickHouse::DoInit
(gdb) break ClickHouse::ExecuteQuery
(gdb) run

# Inspect variables
(gdb) print hostname_
(gdb) print query_
(gdb) print *fields_[0]
```

### Debug Logging

Add debug output to code:

```cpp
#ifdef DEBUG
#define DEBUG_LOG(msg) \
    fprintf(stderr, "[ClickHouse Debug] %s:%d: %s\n", __FILE__, __LINE__, msg)
#else
#define DEBUG_LOG(msg)
#endif

bool ClickHouse::ExecuteQuery()
{
    DEBUG_LOG("Executing query");
    // ... implementation ...
}
```

### Using Valgrind

Check for memory leaks:

```bash
valgrind --leak-check=full \
         --show-leak-kinds=all \
         --track-origins=yes \
         zeek test-script.zeek
```

### Zeek Debug Output

Enable Zeek's debug output:

```bash
# Debug input framework
zeek -B input test-script.zeek

# Debug plugins
zeek -B plugin test-script.zeek

# All debug output
zeek -B all test-script.zeek
```

### Adding Error Reporting

Use Zeek's reporter:

```cpp
#include <zeek/Reporter.h>

// Error (stops processing)
Error(Fmt("Query failed: %s", error_msg));

// Warning (continues processing)
Warning(Fmt("Unexpected value: %s", value));

// Info message
Info(Fmt("Query returned %d rows", row_count));
```

## Code Style

### C++ Style

Follow Zeek's coding conventions:

```cpp
// Class names: PascalCase
class ClickHouse : public ReaderBackend { };

// Function names: PascalCase
bool DoInit(...);
bool ExecuteQuery();

// Member variables: snake_case with trailing underscore
std::string hostname_;
uint16_t port_;

// Local variables: snake_case
int num_fields = 0;
std::string query_result;

// Constants: ALL_CAPS
const int MAX_RETRIES = 3;
```

### Formatting

Use consistent formatting:

```cpp
// Indentation: 4 spaces (no tabs)
if (condition)
    {
    DoSomething();
    }

// Braces on separate lines for functions and control structures
bool MyFunction()
    {
    if (condition)
        {
        // code
        }
    return true;
    }

// Pointer/reference: attached to type
std::string* ptr;
const std::string& ref;
```

### Comments

```cpp
// Single-line comments for brief explanations
// Convert ClickHouse value to Zeek value

/**
 * Multi-line comments for detailed documentation
 * 
 * @param column The ClickHouse column
 * @param row Row index
 * @return True on success
 */
bool ConvertValue(const clickhouse::Column& column, size_t row);
```

### Zeek Script Style

```zeek
# Module names: PascalCase
module ThreatIntel;

# Record/type names: PascalCase
type MyRecord: record {
    field_name: string;  # Field names: snake_case
};

# Global variables: snake_case
global my_table: table[addr] of string;

# Functions: snake_case
function process_data(val: string): bool
    {
    # Function body indented with tabs
    return T;
    }

# Events: snake_case
event my_event(data: string)
    {
    # Event body
    }
```

## Contribution Workflow

### 1. Fork and Clone

```bash
# Fork on GitHub
# Then clone your fork
git clone https://github.com/YOUR_USERNAME/zeek-clickhouse-plugin.git
cd zeek-clickhouse-plugin
git remote add upstream https://github.com/ORIGINAL/zeek-clickhouse-plugin.git
```

### 2. Create Feature Branch

```bash
git checkout -b feature/my-new-feature
# or
git checkout -b fix/bug-description
```

### 3. Make Changes

- Write code following style guide
- Add tests if applicable
- Update documentation
- Test thoroughly

### 4. Commit Changes

```bash
git add .
git commit -m "Add feature: description of feature

Detailed explanation of what was added and why.

Fixes #123"
```

### 5. Push and Create PR

```bash
git push origin feature/my-new-feature
```

Then create Pull Request on GitHub.

### 6. Code Review

- Address reviewer feedback
- Update PR as needed
- Ensure CI passes

### PR Checklist

- [ ] Code follows style guide
- [ ] All tests pass
- [ ] Documentation updated
- [ ] CHANGELOG.md updated (if applicable)
- [ ] No compiler warnings
- [ ] Memory leaks checked
- [ ] Examples work correctly

## Release Process

### Version Numbering

Follow Semantic Versioning (semver.org):
- MAJOR.MINOR.PATCH
- Example: 1.2.3

### Creating a Release

**1. Update version**:
```bash
echo "1.2.0" > VERSION
```

**2. Update CHANGELOG.md**:
```markdown
## [1.2.0] - 2024-XX-XX

### Added
- New feature X
- Support for Y

### Fixed
- Bug Z

### Changed
- Improved performance of ABC
```

**3. Commit and tag**:
```bash
git add VERSION CHANGELOG.md
git commit -m "Release version 1.2.0"
git tag -a v1.2.0 -m "Release version 1.2.0"
git push origin main --tags
```

**4. Build packages**:
```bash
mkdir build-release && cd build-release
cmake .. -DCMAKE_BUILD_TYPE=Release
make package
```

**5. Create GitHub release**:
- Go to GitHub Releases
- Create new release from tag
- Upload packages
- Add release notes

## Documentation

### Code Documentation

Use Doxygen-style comments:

```cpp
/**
 * Execute SQL query and process results.
 * 
 * This method executes the configured SQL query against the
 * ClickHouse database and processes the returned blocks.
 * 
 * @return True if query executed successfully, false on error
 * @throws std::exception if connection fails
 */
bool ExecuteQuery();
```

### Generating API Docs

```bash
# Install doxygen
sudo apt-get install doxygen graphviz

# Generate docs
cd docs
doxygen Doxyfile

# View docs
firefox html/index.html
```

### User Documentation

When adding features, update:
- README.md - Main documentation
- INSTALL.md - If installation changes
- QUICKSTART.md - If basic usage changes
- examples/ - Add example scripts
- examples/README.md - Document examples

## Troubleshooting Development Issues

### CMake Can't Find Zeek

```bash
export ZEEK_ROOT_DIR=/usr/local/zeek
cmake .. -DZEEK_ROOT_DIR=$ZEEK_ROOT_DIR
```

### Compilation Errors

```bash
# Clean build
rm -rf build-debug
mkdir build-debug && cd build-debug
cmake .. && make
```

### Plugin Doesn't Load

```bash
# Check plugin structure
ls -R VNET_ClickHouse/

# Check dependencies
ldd VNET_ClickHouse/lib/VNET_ClickHouse.so

# Try explicit load
zeek -N VNET::ClickHouse --plugin-dir=$PWD
```

### Segmentation Faults

```bash
# Run with core dumps enabled
ulimit -c unlimited
zeek test-script.zeek
# If crash occurs:
gdb zeek core
(gdb) bt
```

## Resources

### Zeek Development
- [Zeek Plugin Development](https://docs.zeek.org/en/master/devel/plugins.html)
- [Input Framework](https://docs.zeek.org/en/master/frameworks/input.html)
- [Zeek C++ API](https://docs.zeek.org/en/master/devel/index.html)

### ClickHouse
- [ClickHouse C++ Client](https://github.com/ClickHouse/clickhouse-cpp)
- [ClickHouse Documentation](https://clickhouse.com/docs/)
- [ClickHouse SQL Reference](https://clickhouse.com/docs/en/sql-reference/)

### Tools
- [CMake Documentation](https://cmake.org/documentation/)
- [GDB Tutorial](https://www.gnu.org/software/gdb/documentation/)
- [Valgrind Quick Start](https://valgrind.org/docs/manual/quick-start.html)

## Getting Help

- GitHub Issues: For bugs and feature requests
- GitHub Discussions: For questions and ideas
- Zeek Community: https://community.zeek.org/
- Developer Chat: [if available]

## License

All contributions must be under the BSD 3-Clause License. See COPYING for details.

---

**Happy Coding!** 🚀

For questions about development, please open a GitHub issue or discussion.