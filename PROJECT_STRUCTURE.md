# Project Structure

This document describes the organization and structure of the Zeek ClickHouse Input Reader Plugin.

## Directory Tree

```
zeek_clickhouse/
├── CMakeLists.txt                 # Main build configuration
├── VERSION                        # Plugin version file
├── COPYING                        # BSD 3-Clause license
├── README.md                      # Main documentation
├── INSTALL.md                     # Installation guide
├── QUICKSTART.md                  # Quick start guide
├── PROJECT_STRUCTURE.md           # This file
├── .gitignore                     # Git ignore rules
│
├── cmake/                         # CMake helper files
│   ├── ZeekPlugin.cmake          # Zeek plugin build helpers
│   └── ConfigurePackaging.cmake  # Package generation config
│
├── src/                          # Source code
│   ├── Plugin.h                  # Plugin header
│   ├── Plugin.cc                 # Plugin implementation
│   ├── ClickHouse.h              # Reader header
│   ├── ClickHouse.cc             # Reader implementation
│   └── clickhouse.bif            # Built-in function definitions
│
├── scripts/                      # Zeek scripts
│   ├── __load__.zeek            # Auto-loader script
│   └── clickhouse.zeek          # Helper functions and types
│
└── examples/                     # Example scripts
    ├── README.md                 # Examples documentation
    ├── simple-watchlist.zeek     # Basic watchlist example
    ├── threat-intel.zeek         # Threat intelligence example
    └── security-events.zeek      # Event streaming example
```

## Core Components

### Build System

#### CMakeLists.txt
- Main build configuration file
- Configures plugin compilation
- Links ClickHouse C++ client library
- Sets up installation targets
- Integrates with Zeek's build system

#### cmake/ZeekPlugin.cmake
- Helper macros for Zeek plugin development
- Provides `zeek_plugin_begin()`, `zeek_plugin_end()`, etc.
- Handles BIF file generation
- Manages plugin distribution structure
- Finds Zeek installation and headers

#### cmake/ConfigurePackaging.cmake
- CPack configuration for package generation
- Supports RPM, DEB, and TGZ formats
- Configures package metadata
- Sets up component-based installation

### Source Code

#### src/Plugin.h & src/Plugin.cc
**Purpose**: Main plugin entry point

**Key Components**:
- `Plugin` class extending `zeek::plugin::Plugin`
- Plugin registration and initialization
- Component registration (registers the ClickHouse reader)
- Plugin metadata (name, version, description)

**Functions**:
- `Configure()`: Returns plugin configuration
- Constructor/Destructor: Plugin lifecycle management

#### src/ClickHouse.h
**Purpose**: Reader interface definition

**Key Components**:
- `ClickHouse` class extending `zeek::input::ReaderBackend`
- Configuration structure
- Connection parameters
- Field mapping definitions

**Main Methods**:
- `Instantiate()`: Factory method for reader creation
- `DoInit()`: Initialize connection and configuration
- `DoClose()`: Cleanup and disconnect
- `DoUpdate()`: Refresh data (table mode)
- `DoHeartbeat()`: Periodic polling (streaming mode)
- `ExecuteQuery()`: Execute query and process results
- `ConvertValue()`: Convert ClickHouse types to Zeek types

**Configuration Options**:
- `hostname_`: ClickHouse server address
- `server_port_`: Native protocol port (default: 9000)
- `database_`: Database name
- `user_`, `password_`: Authentication
- `query_`: SQL query to execute
- `poll_interval_`: Polling frequency (0 = one-shot)

#### src/ClickHouse.cc
**Purpose**: Reader implementation

**Key Functions**:

1. **Connection Management**:
   - `DoInit()`: Establishes connection, parses config
   - `DoClose()`: Closes connection and cleanup
   - `ParseConfig()`: Parses configuration options

2. **Data Retrieval**:
   - `ExecuteQuery()`: Executes SQL query, processes blocks
   - `DoUpdate()`: Manual refresh for table mode
   - `DoHeartbeat()`: Automatic polling for streaming mode

3. **Type Conversion**:
   - `ConvertValue()`: Main conversion dispatcher
   - `GetColumnStringValue()`: Extract string representation
   - Type-specific converters for all Zeek types

**Supported Type Mappings**:
```
ClickHouse Type          → Zeek Type
─────────────────────────────────────
String/FixedString       → string
Int8/16/32/64           → int
UInt8/16/32/64          → count
Float32/Float64         → double
DateTime                → time
Date                    → time
IPv4/IPv6 (as String)   → addr
CIDR (as String)        → subnet
Port format             → port
Enum                    → enum
```

#### src/clickhouse.bif
**Purpose**: Built-in function and type definitions

**Contents**:
- `ClickHouse::Config` record type
- Configuration field definitions
- Default values for connection parameters
- Type annotations for Zeek's BIF compiler

### Zeek Scripts

#### scripts/__load__.zeek
**Purpose**: Plugin loader script

**Function**:
- Automatically loaded when plugin is available
- Loads main script files
- Simple one-line loader

#### scripts/clickhouse.zeek
**Purpose**: High-level Zeek interface

**Exports**:
- `ClickHouse::Info`: Configuration record type
- `config_to_table()`: Convert Info to config table
- `table_description()`: Helper for `Input::add_table()`
- `event_description()`: Helper for `Input::add_event()`

**Key Features**:
- Simplifies configuration
- Provides convenience functions
- Type-safe configuration records
- Environment variable support

### Examples

#### examples/simple-watchlist.zeek
**Complexity**: Beginner  
**Lines**: ~100  
**Purpose**: Basic IP watchlist monitoring

**Features**:
- Minimal configuration
- One-shot data loading
- Connection monitoring
- Alert generation

**Use Cases**:
- Quick start demonstration
- Basic threat detection
- Learning the plugin API

#### examples/threat-intel.zeek
**Complexity**: Intermediate  
**Lines**: ~200  
**Purpose**: Full threat intelligence system

**Features**:
- Multi-field threat records
- Severity-based filtering
- Automatic refresh scheduling
- Notice framework integration
- Statistics tracking
- Type categorization

**Use Cases**:
- Production threat intel feeds
- Complex alerting logic
- Periodic data updates

#### examples/security-events.zeek
**Complexity**: Advanced  
**Lines**: ~300  
**Purpose**: Real-time event streaming

**Features**:
- Continuous polling mode
- Event correlation with connections
- Type-specific handlers
- Duplicate detection
- Memory management
- Advanced statistics

**Use Cases**:
- SIEM integration
- Real-time event processing
- Cross-system correlation

### Documentation

#### README.md
**Content**: Main plugin documentation

**Sections**:
- Overview and features
- Requirements
- Installation instructions
- Usage examples (3 detailed examples)
- Configuration options reference
- Type mapping table
- Operation modes explanation
- Performance considerations
- Troubleshooting guide
- Security considerations

#### INSTALL.md
**Content**: Detailed installation guide

**Sections**:
- Prerequisites checklist
- Dependency installation (ClickHouse C++ client)
- Building from source (step-by-step)
- Installation methods (system-wide, user, Docker)
- Verification procedures
- Troubleshooting (7+ common issues)
- Platform-specific notes (Ubuntu, CentOS, macOS, FreeBSD)

#### QUICKSTART.md
**Content**: 15-minute getting started guide

**Sections**:
- Prerequisites check
- 5-step setup process
- Test database creation
- First script creation
- Running and verifying
- Next steps and examples

#### examples/README.md
**Content**: Examples documentation

**Sections**:
- Example descriptions with difficulty levels
- Setup instructions for each example
- Common patterns and templates
- Configuration examples
- Testing procedures
- Troubleshooting
- Customization guide

## Build Artifacts

When built, the following structure is generated:

```
build/
├── VNET_ClickHouse/          # Plugin distribution
│   ├── lib/
│   │   └── VNET_ClickHouse.so  # Plugin shared library
│   ├── scripts/
│   │   ├── __load__.zeek
│   │   └── clickhouse.zeek
│   ├── README.md
│   ├── COPYING
│   └── VERSION
│
├── clickhouse.bif.cc              # Generated BIF implementation
├── clickhouse.bif.h               # Generated BIF header
└── ...                            # CMake build files
```

## Installation Layout

After `make install`, files are placed as:

```
/usr/local/zeek/lib/zeek/plugins/VNET_ClickHouse/
├── lib/
│   └── VNET_ClickHouse.so
├── scripts/
│   ├── __load__.zeek
│   └── VNET/ClickHouse/
│       └── clickhouse.zeek
├── README.md
├── COPYING
└── VERSION
```

## Code Flow

### Initialization Flow
```
1. Zeek starts
2. Plugin::Configure() called
   - Registers ClickHouse reader component
3. User script loads @load VNET/ClickHouse
4. Input::add_table() or Input::add_event() called
5. ClickHouse::Instantiate() creates reader instance
6. ClickHouse::DoInit() called
   - Parses configuration
   - Connects to ClickHouse
   - Executes initial query
7. Data processing begins
```

### Data Loading Flow (One-Shot)
```
1. DoInit() executes query
2. ExecuteQuery() processes blocks
3. For each row:
   a. ConvertValue() for each field
   b. Put() sends data to Zeek
4. EndCurrentSend() signals completion
5. Input::end_of_data event raised
```

### Data Streaming Flow (Polling)
```
1. DoInit() executes initial query
2. DoHeartbeat() called periodically
3. If poll_interval elapsed:
   a. ExecuteQuery() re-executes query
   b. New data processed as above
4. EndCurrentSend() after each poll
5. Repeat until Zeek shutdown
```

### Type Conversion Flow
```
1. ClickHouse returns typed column
2. GetColumnStringValue() extracts value
3. ConvertValue() dispatches by Zeek type:
   - TYPE_INT → extract Int64/Int32/etc.
   - TYPE_COUNT → extract UInt64/UInt32/etc.
   - TYPE_DOUBLE → extract Float64/Float32
   - TYPE_STRING → copy string
   - TYPE_ADDR → parse IP address
   - TYPE_SUBNET → parse CIDR
   - TYPE_PORT → parse port/proto
   - TYPE_TIME → extract DateTime
4. Value packaged in threading::Value
5. Sent to Zeek core via Put()
```

## Key Design Decisions

### Why C++17?
- Required by ClickHouse C++ client library
- Modern language features improve code quality
- Better error handling with exceptions

### Why Native Protocol (Port 9000)?
- More efficient than HTTP interface
- Binary protocol reduces overhead
- Better performance for large result sets

### Why ReaderBackend Architecture?
- Integrates with Zeek's Input Framework
- Consistent with other input readers
- Leverages existing infrastructure
- Automatic threading and buffering

### Why Helper Functions in Zeek?
- Simplifies user scripts
- Provides type safety
- Reduces configuration errors
- Allows future extensions without breaking changes

## Extension Points

### Adding New Type Conversions
Edit `src/ClickHouse.cc`, `ConvertValue()` function:
```cpp
case TYPE_YOUR_TYPE:
    // Add conversion logic
    break;
```

### Adding Configuration Options
1. Add field to `ClickHouse::Info` in `scripts/clickhouse.zeek`
2. Add parsing in `ParseConfig()` in `src/ClickHouse.cc`
3. Use in connection setup

### Custom Event Handlers
Users can add in their scripts:
```zeek
event Input::end_of_data(name: string, source: string)
    { /* custom logic */ }
```

## Testing

### Unit Testing
Currently, testing is manual. Future enhancements could include:
- Unit tests for type conversion
- Integration tests with test database
- Mock ClickHouse server for CI/CD

### Manual Testing
```bash
# Build and install
mkdir build && cd build
cmake .. && make && sudo make install

# Verify plugin
zeek -N VNET::ClickHouse

# Run examples
zeek examples/simple-watchlist.zeek
```

## Dependencies

### Build-time Dependencies
- CMake 3.15+
- C++17 compiler (GCC 8+, Clang 7+)
- Zeek 5.0+ headers
- ClickHouse C++ client headers

### Runtime Dependencies
- Zeek 5.0+
- ClickHouse C++ client library
- ClickHouse server (local or remote)

### Optional Dependencies
- Git (for cloning)
- Doxygen (for generating docs)
- Package tools (rpmbuild, dpkg-deb)

## Version History

### 1.0.0 (Initial Release)
- ClickHouse input reader implementation
- Support for all major Zeek types
- One-shot and streaming modes
- Configuration helpers
- Example scripts
- Comprehensive documentation

## Future Enhancements

### Potential Features
- SSL/TLS connection support
- Parameterized queries
- Batch updates for better performance
- Asynchronous query execution
- Connection pooling
- Query result caching
- Metrics and monitoring
- Enhanced error recovery

### Documentation Improvements
- Video tutorials
- More examples (DNS, HTTP, SSL)
- Integration guides (SIEM, TIP)
- Performance tuning guide
- Architecture diagrams

## Contributing

When contributing, please maintain this structure:

1. **Source code** in `src/`
2. **Scripts** in `scripts/` (user-facing APIs)
3. **Examples** in `examples/` (with documentation)
4. **Tests** (future: in `tests/`)
5. **Documentation** at root level

Follow existing patterns:
- Use consistent naming conventions
- Add error handling
- Update documentation
- Provide examples for new features

## License

All files are under BSD 3-Clause license. See `COPYING` for full text.

---

**Last Updated**: 2024  
**Plugin Version**: 1.0.0  
**Zeek Compatibility**: 5.0+
