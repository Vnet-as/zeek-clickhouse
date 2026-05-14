# Quick Start Guide - Zeek ClickHouse Input Reader Plugin

Get up and running with the Zeek ClickHouse Input Reader plugin in 15 minutes.

## Prerequisites Check

Before starting, verify you have:

```bash
# Check Zeek installation
zeek --version  # Should be 5.0 or later

# Check ClickHouse server is running
clickhouse-client --query "SELECT 1"  # Should return: 1

# Check build tools
cmake --version  # Should be 3.15 or later
g++ --version    # Should be 8.0 or later
```

## Step 1: Install ClickHouse C++ Client (5 minutes)

```bash
# Clone and build
git clone https://github.com/ClickHouse/clickhouse-cpp.git
cd clickhouse-cpp
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
sudo make install
sudo ldconfig

cd ../..
```

## Step 2: Build and Install the Plugin (3 minutes)

```bash
# Navigate to plugin directory
cd zeek-clickhouse-plugin

# Build
mkdir build && cd build
cmake ..
make -j$(nproc)

# Install
sudo make install

# Verify
zeek -N VNET::ClickHouse
```

Expected output:
```
VNET::ClickHouse - ClickHouse input reader for Zeek Input Framework (dynamic, version 1.0.0)
    [Reader] ClickHouse (READER_CLICKHOUSE)
```

## Step 3: Create Test Database (2 minutes)

```bash
# Connect to ClickHouse
clickhouse-client

# Create test table
CREATE TABLE test_watchlist (
    ip_address String,
    threat_level UInt8,
    description String,
    added_date DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY ip_address;

# Insert sample data
INSERT INTO test_watchlist (ip_address, threat_level, description) VALUES
    ('192.0.2.100', 5, 'Known malware C2'),
    ('192.0.2.101', 3, 'Suspicious scanner'),
    ('198.51.100.50', 4, 'Phishing infrastructure');

# Verify data
SELECT * FROM test_watchlist;

# Exit
exit
```

## Step 4: Create Your First Zeek Script (2 minutes)

Create a file named `my-first-clickhouse.zeek`:

```zeek
@load base/frameworks/input
@load VNET/ClickHouse

module MyTest;

export {
    type WatchlistEntry: record {
        ip: addr;
        threat_level: count;
        description: string;
        added_date: time;
    };

    global watchlist: table[addr] of WatchlistEntry = table();
}

event zeek_init()
    {
    print "Loading watchlist from ClickHouse...";

    local ch_info = ClickHouse::Info(
        $hostname = "localhost",
        $server_port = 9000,
        $database = "default",
        $query = "SELECT ip_address, threat_level, description, added_date FROM test_watchlist"
    );

    Input::add_table([
        $name = "watchlist",
        $source = "clickhouse://localhost",
        $reader = Input::READER_CLICKHOUSE,
        $mode = Input::REREAD,
        $destination = watchlist,
        $idx = WatchlistEntry,
        $val = WatchlistEntry,
        $config = ClickHouse::config_to_table(ch_info)
    ]);
    }

event Input::end_of_data(name: string, source: string)
    {
    if ( name == "watchlist" )
        {
        print fmt("SUCCESS! Loaded %d entries from ClickHouse:", |watchlist|);
        for ( ip, entry in watchlist )
            print fmt("  %s (Level %d): %s", ip, entry$threat_level, entry$description);
        }
    }
```

## Step 5: Run It! (1 minute)

```bash
zeek my-first-clickhouse.zeek
```

Expected output:
```
Loading watchlist from ClickHouse...
SUCCESS! Loaded 3 entries from ClickHouse:
  192.0.2.100 (Level 5): Known malware C2
  192.0.2.101 (Level 3): Suspicious scanner
  198.51.100.50 (Level 4): Phishing infrastructure
```

## 🎉 Congratulations!

You've successfully:
- ✅ Installed the ClickHouse C++ client
- ✅ Built and installed the Zeek plugin
- ✅ Created a ClickHouse database with test data
- ✅ Loaded data from ClickHouse into Zeek

## Next Steps

### Try Streaming Mode

Modify your script to continuously poll for updates:

```zeek
local ch_info = ClickHouse::Info(
    $hostname = "localhost",
    $query = "SELECT ip_address, threat_level, description, added_date FROM test_watchlist WHERE added_date > now() - INTERVAL 5 MINUTE",
    $poll_interval = 30sec  # Poll every 30 seconds
);
```

### Use in Real Monitoring

Check connections against the watchlist:

```zeek
event connection_established(c: connection)
    {
    if ( c$id$orig_h in watchlist )
        {
        local entry = watchlist[c$id$orig_h];
        print fmt("ALERT: Connection from watchlisted IP %s (Level %d: %s)",
                  c$id$orig_h, entry$threat_level, entry$description);
        }
    }
```

### Explore Examples

Check the `examples/` directory for more advanced use cases:

```bash
cd examples/
ls -la
```

- `simple-watchlist.zeek` - Basic IP watchlist
- `threat-intel.zeek` - Full threat intelligence integration
- `security-events.zeek` - Streaming security events

### Read the Documentation

- **README.md** - Complete usage guide with all features
- **INSTALL.md** - Detailed installation instructions
- **examples/** - Working examples for various use cases

## Common Issues

### Plugin Not Found

```bash
# Set plugin path if needed
export ZEEK_PLUGIN_PATH=$HOME/.zeek/plugins
zeek -N VNET::ClickHouse
```

### Connection Refused

```bash
# Check ClickHouse is running
ps aux | grep clickhouse-server

# Test connection
clickhouse-client --host localhost --port 9000
```

### Library Not Found

```bash
# Add library path
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

# Update cache
sudo ldconfig
```

## Getting Help

- **GitHub Issues**: Report bugs or request features
- **Zeek Community**: https://community.zeek.org/
- **Examples**: See `examples/` directory for more scripts

## Quick Reference

### Configuration Options

```zeek
ClickHouse::Info(
    $hostname = "localhost",     # ClickHouse server
    $server_port = 9000,         # Native protocol port
    $database = "default",       # Database name
    $user = "default",           # Username
    $password = "",              # Password
    $query = "SELECT ...",       # SQL query (required)
    $poll_interval = 0sec        # 0 = one-shot, >0 = streaming
)
```

### Common Patterns

**Load once:**
```zeek
Input::add_table([...])
```

**Continuous polling:**
```zeek
Input::add_event([...])  # with poll_interval > 0
```

**Manual refresh:**
```zeek
Input::force_update("stream_name")
```

## Testing Your Setup

Run the included examples to verify everything works:

```bash
# Simple watchlist
zeek examples/simple-watchlist.zeek

# Threat intelligence (requires data)
zeek examples/threat-intel.zeek

# Security events streaming (requires data)
zeek examples/security-events.zeek
```

## Performance Tips

1. **Use indexes** in ClickHouse tables
2. **Limit result sets** with WHERE clauses
3. **Project only needed columns** in SELECT
4. **Set appropriate poll_interval** (don't poll too frequently)
5. **Use time-based filters** for streaming queries

## Security Notes

- **Never hardcode passwords** in scripts
- **Use environment variables** for credentials:
  ```zeek
  $password = getenv("CLICKHOUSE_PASSWORD")
  ```
- **Restrict ClickHouse access** with firewall rules
- **Use SSL/TLS** for production deployments

## You're Ready!

You now have a working Zeek ClickHouse integration. Start building your own scripts and integrate your ClickHouse data into Zeek's powerful network monitoring capabilities!

Happy monitoring! 🚀
