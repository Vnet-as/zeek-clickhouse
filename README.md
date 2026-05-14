# Zeek ClickHouse Input Reader Plugin

A Zeek plugin that provides an input reader for the Zeek Input Framework, allowing Zeek to read data directly from ClickHouse databases.

## Overview

This plugin enables Zeek to:
- Query ClickHouse databases and import results into Zeek tables
- Stream continuous data from ClickHouse using periodic polling
- Use ClickHouse as a data source for threat intelligence feeds, watchlists, and configuration data
- Leverage ClickHouse's analytical capabilities to enrich Zeek's network monitoring

## Features

- **Full Input Framework Integration**: Works seamlessly with Zeek's Input Framework
- **Flexible Query Support**: Execute arbitrary SQL queries against ClickHouse
- **Multiple Operation Modes**:
  - One-shot mode: Load data once and populate Zeek tables
  - Streaming mode: Continuously poll ClickHouse for updates
- **Type Conversion**: Automatic conversion between ClickHouse and Zeek data types
- **Connection Management**: Configurable connection parameters including authentication
- **Error Handling**: Robust error handling and reporting

## Requirements

- Zeek 5.0 or later
- ClickHouse C++ client library ([clickhouse-cpp](https://github.com/ClickHouse/clickhouse-cpp))
- CMake 3.15 or later
- C++17 compatible compiler

## Installation

### Installing ClickHouse C++ Client

First, install the ClickHouse C++ client library:

```bash
# Clone the repository
git clone https://github.com/ClickHouse/clickhouse-cpp.git
cd clickhouse-cpp

# Build and install
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make
sudo make install
```

### Building the Plugin

```bash
# Clone this repository
git clone <repository-url> zeek-clickhouse-plugin
cd zeek-clickhouse-plugin

# Configure and build
mkdir build && cd build
cmake ..
make

# Install the plugin
sudo make install
```

The plugin will be installed to your Zeek plugin directory (typically `/usr/local/zeek/lib/zeek/plugins/`).

### Verifying Installation

Check that Zeek recognizes the plugin:

```bash
zeek -N VNET::ClickHouse
```

You should see output similar to:

```
VNET::ClickHouse - ClickHouse input reader for Zeek Input Framework (dynamic, version 1.0.0)
```

## Usage

### Basic Configuration

The plugin is configured using the `ClickHouse::Info` record:

```zeek
module MyModule;

@load VNET/ClickHouse

# Define the ClickHouse connection configuration
local clickhouse_config = ClickHouse::Info(
    $hostname = "localhost",
    $server_port = 9000,
    $database = "default",
    $user = "default",
    $password = "",
    $query = "SELECT ip, domain FROM threat_intel"
);
```

### Example 1: Loading a Threat Intelligence Feed

This example loads IP addresses and associated domains from ClickHouse into a Zeek table:

```zeek
@load base/frameworks/input
@load VNET/ClickHouse

module ThreatIntel;

export {
    # Define the table structure
    type Idx: record {
        ip: addr;
    };
    
    type Val: record {
        domain: string;
    };
    
    # The table to populate
    global threat_table: table[addr] of Val = table();
}

event zeek_init()
    {
    # Configure ClickHouse connection
    local ch_info = ClickHouse::Info(
        $hostname = "clickhouse.example.com",
        $server_port = 9000,
        $database = "security",
        $user = "zeek_reader",
        $password = "secret",
        $query = "SELECT ip_address, domain_name FROM threat_indicators WHERE active = 1"
    );
    
    # Add the input source
    Input::add_table([
        $name = "threat_intel",
        $source = cat("clickhouse://", ch_info$hostname),
        $reader = Input::READER_CLICKHOUSE,
        $mode = Input::REREAD,
        $destination = threat_table,
        $idx = Idx,
        $val = Val,
        $config = ClickHouse::config_to_table(ch_info)
    ]);
    }

event Input::end_of_data(name: string, source: string)
    {
    if ( name == "threat_intel" )
        print fmt("Loaded %d threat indicators from ClickHouse", |threat_table|);
    }

# Use the threat intel in connection handling
event connection_established(c: connection)
    {
    if ( c$id$orig_h in threat_table )
        {
        local info = threat_table[c$id$orig_h];
        print fmt("Alert: Connection from known threat %s (domain: %s)", c$id$orig_h, info$domain);
        }
    }
```

### Example 2: Streaming Events from ClickHouse

This example continuously polls ClickHouse for new security events:

```zeek
@load base/frameworks/input
@load VNET/ClickHouse

module SecurityEvents;

export {
    type Event: record {
        timestamp: time;
        event_type: string;
        source_ip: addr;
        details: string;
    };
    
    global security_event: event(description: Input::EventDescription, t: Event);
}

event zeek_init()
    {
    # Configure ClickHouse with polling
    local ch_info = ClickHouse::Info(
        $hostname = "clickhouse.example.com",
        $server_port = 9000,
        $database = "security",
        $user = "zeek_reader",
        $password = "secret",
        $query = "SELECT timestamp, event_type, source_ip, details FROM security_events WHERE timestamp > now() - INTERVAL 5 MINUTE",
        $poll_interval = 30sec  # Poll every 30 seconds
    );
    
    # Add event stream
    Input::add_event([
        $name = "security_events",
        $source = cat("clickhouse://", ch_info$hostname),
        $reader = Input::READER_CLICKHOUSE,
        $fields = Event,
        $ev = security_event,
        $want_record = T,
        $config = ClickHouse::config_to_table(ch_info)
    ]);
    }

event security_event(description: Input::EventDescription, t: Event)
    {
    print fmt("Security event: %s from %s at %s", t$event_type, t$source_ip, t$timestamp);
    print fmt("  Details: %s", t$details);
    }
```

### Example 3: Using Helper Functions

The plugin provides helper functions to simplify configuration:

```zeek
@load VNET/ClickHouse

module Watchlist;

export {
    type WatchEntry: record {
        indicator: string;
        ioc_type: string;
        severity: count;
    };
    
    global watchlist: table[string] of WatchEntry = table();
}

event zeek_init()
    {
    local ch_info = ClickHouse::Info(
        $hostname = "localhost",
        $query = "SELECT indicator, ioc_type, severity FROM watchlist"
    );
    
    # Use the helper function
    Input::add_table(ClickHouse::table_description(
        "watchlist",
        ch_info,
        watchlist,
        WatchEntry,
        WatchEntry
    ));
    }
```

## Configuration Options

The `ClickHouse::Info` record supports the following fields:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `hostname` | string | `"localhost"` | ClickHouse server hostname or IP address |
| `server_port` | count | `9000` | ClickHouse native protocol port (not HTTP port) |
| `database` | string | `"default"` | Database name to connect to |
| `user` | string | `"default"` | Username for authentication |
| `password` | string | `""` | Password for authentication |
| `query` | string | (required) | SQL query to execute |
| `poll_interval` | interval | `0sec` | Polling interval for streaming mode (0 = one-shot) |

## Type Mapping

The plugin automatically converts between ClickHouse and Zeek types:

| ClickHouse Type | Zeek Type | Notes |
|----------------|-----------|-------|
| String, FixedString | string | Direct conversion |
| Int8, Int16, Int32, Int64 | int | Signed integers |
| UInt8, UInt16, UInt32, UInt64 | count | Unsigned integers |
| Float32, Float64 | double | Floating point |
| DateTime | time | Unix timestamp |
| Date | time | Converted to midnight of that day |
| IPv4, IPv6 | addr | IP addresses (as strings) |
| String (CIDR) | subnet | Subnet in CIDR notation |
| UInt16 | port | Port numbers (can include protocol) |
| Enum | enum | Enumeration values |

## Operation Modes

### One-Shot Mode (poll_interval = 0)

In one-shot mode, the query is executed once when the input source is added:

```zeek
local ch_info = ClickHouse::Info(
    $query = "SELECT * FROM static_data",
    $poll_interval = 0sec  # or omit, as 0sec is the default
);
```

Use this mode for:
- Static configuration data
- Historical data loading
- One-time data imports

### Streaming Mode (poll_interval > 0)

In streaming mode, the query is re-executed at regular intervals:

```zeek
local ch_info = ClickHouse::Info(
    $query = "SELECT * FROM events WHERE timestamp > now() - INTERVAL 1 MINUTE",
    $poll_interval = 30sec  # Re-query every 30 seconds
);
```

Use this mode for:
- Continuous threat intelligence updates
- Real-time event correlation
- Dynamic watchlist updates

**Best Practices for Streaming:**
- Use time-based filters in your query to avoid re-processing old data
- Set appropriate poll intervals to balance freshness vs. load
- Consider using ClickHouse's incremental views for efficient querying

## Performance Considerations

### Query Optimization

- **Use indexes**: Ensure ClickHouse tables have appropriate indexes
- **Limit result sets**: Use WHERE clauses and LIMIT to constrain results
- **Project only needed columns**: SELECT only the columns you need
- **Leverage ClickHouse features**: Use materialized views, aggregations, etc.

### Connection Management

- The plugin maintains a persistent connection to ClickHouse
- Connection errors trigger automatic reconnection attempts
- Configure ClickHouse server for appropriate connection limits

### Memory Usage

- Large result sets are processed in blocks to manage memory
- Consider paginating large queries or using multiple input sources
- Monitor Zeek's memory usage when loading large datasets

## Troubleshooting

### Plugin Not Loading

Check that the plugin is installed correctly:

```bash
zeek -N VNET::ClickHouse
```

Ensure the ClickHouse client library is in your system's library path:

```bash
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
```

### Connection Errors

Verify ClickHouse connectivity:

```bash
clickhouse-client --host=<hostname> --port=<port> --user=<user> --password=<password>
```

Common issues:
- Wrong port (native port 9000, not HTTP port 8123)
- Firewall blocking connections
- Authentication failures
- Network connectivity issues

### Query Errors

Check query syntax in ClickHouse client first:

```sql
SELECT * FROM your_table LIMIT 10;
```

Common issues:
- Invalid SQL syntax
- Table or column doesn't exist
- Insufficient permissions
- Type mismatches

### Enable Debug Logging

Add to your Zeek script:

```zeek
redef Input::accept_unsupported_types = T;
redef InputAscii::empty_field = "EMPTY";
```

Check Zeek's stderr output and reporter.log for detailed error messages.

## Security Considerations

### Credentials Management

- **Never hardcode passwords** in Zeek scripts
- Use environment variables or secure configuration files
- Restrict file permissions on configuration files containing credentials
- Consider using ClickHouse's SSL/TLS support for encrypted connections

### Query Injection

- The plugin does not perform query parameterization
- Ensure queries are constructed safely
- Do not include untrusted user input in queries
- Validate and sanitize any dynamic query components

### Network Security

- Use firewalls to restrict ClickHouse access
- Consider using SSH tunnels or VPNs for remote connections
- Enable ClickHouse authentication and access controls
- Monitor ClickHouse access logs

## Development

### Building for Development

```bash
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
make
```

### Running Tests

```bash
# After building
make test
```

### Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes with appropriate tests
4. Submit a pull request

## License

This plugin is licensed under the BSD 3-Clause License. See the `COPYING` file for details.

## Support

For issues, questions, or contributions:
- GitHub Issues: [repository-url]/issues
- Zeek Community: https://community.zeek.org/

## Acknowledgments

This plugin uses:
- [Zeek Network Security Monitor](https://zeek.org/)
- [ClickHouse C++ Client Library](https://github.com/ClickHouse/clickhouse-cpp)

## See Also

- [Zeek Input Framework Documentation](https://docs.zeek.org/en/master/frameworks/input.html)
- [ClickHouse Documentation](https://clickhouse.com/docs/)
- [Zeek Plugin Development Guide](https://docs.zeek.org/en/master/devel/plugins.html)
