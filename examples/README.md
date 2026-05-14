# ClickHouse Plugin Examples

This directory contains example Zeek scripts demonstrating various use cases for the ClickHouse Input Reader plugin.

## Available Examples

### 1. simple-watchlist.zeek

**Difficulty**: Beginner  
**Use Case**: Basic IP address watchlist monitoring

A minimal example showing how to:
- Load a simple IP watchlist from ClickHouse
- Check connections against the watchlist
- Alert when watchlisted IPs are detected

**Setup**:
```sql
CREATE TABLE ip_watchlist (
    ip_address String,
    reason String,
    added_date DateTime
) ENGINE = MergeTree()
ORDER BY ip_address;

INSERT INTO ip_watchlist VALUES
    ('192.0.2.100', 'Previous incident', now()),
    ('192.0.2.101', 'Suspicious behavior', now()),
    ('198.51.100.50', 'Known bad actor', now());
```

**Run**:
```bash
zeek -i eth0 simple-watchlist.zeek
```

---

### 2. threat-intel.zeek

**Difficulty**: Intermediate  
**Use Case**: Comprehensive threat intelligence integration

A complete threat intelligence system that:
- Loads threat indicators from ClickHouse
- Categorizes threats by type and severity
- Generates Zeek notices for detected threats
- Tracks connection statistics
- Periodically refreshes threat data

**Features**:
- Severity-based filtering
- Automatic refresh scheduling
- Multiple threat types (malware, scanner, spam, etc.)
- Notice framework integration
- Detailed statistics and reporting

**Setup**:
```sql
CREATE TABLE threat_intel (
    ip_address String,
    threat_type String,
    severity UInt8,
    first_seen DateTime,
    last_seen DateTime,
    description String
) ENGINE = MergeTree()
ORDER BY (ip_address, last_seen);

INSERT INTO threat_intel VALUES
    ('192.0.2.100', 'malware', 5, now() - INTERVAL 7 DAY, now(), 'Known C2 server'),
    ('192.0.2.101', 'scanner', 3, now() - INTERVAL 2 DAY, now(), 'Port scanner'),
    ('198.51.100.50', 'spam', 2, now() - INTERVAL 1 DAY, now(), 'Spam source');
```

**Configuration**:
```zeek
# Adjust these in your local.zeek or directly in the script
redef ThreatIntel::clickhouse_host = "your-server.example.com";
redef ThreatIntel::refresh_interval = 5min;
redef ThreatIntel::alert_threshold = 3;
```

**Run**:
```bash
zeek -i eth0 threat-intel.zeek
```

---

### 3. security-events.zeek

**Difficulty**: Advanced  
**Use Case**: Streaming security events from external systems

Demonstrates real-time event streaming from ClickHouse:
- Continuously polls ClickHouse for new security events
- Correlates events with active Zeek connections
- Processes different event types with custom handlers
- Tracks processed events to avoid duplicates
- Generates notices for critical events

**Features**:
- Streaming mode with configurable polling
- Event correlation with network traffic
- Type-specific event handlers
- Duplicate detection
- Statistics tracking and reporting
- Memory management for long-running deployments

**Setup**:
```sql
CREATE TABLE security_events (
    event_id UInt64,
    timestamp DateTime,
    event_type String,
    source_ip String,
    dest_ip String,
    severity UInt8,
    username String,
    details String,
    tags Array(String)
) ENGINE = MergeTree()
ORDER BY (timestamp, event_id);

INSERT INTO security_events VALUES
    (1, now(), 'login_failure', '192.0.2.100', '10.0.0.1', 3, 'admin', 'Failed login attempt', ['authentication', 'failed']),
    (2, now(), 'suspicious_traffic', '192.0.2.101', '10.0.0.2', 4, '', 'Unusual port scan detected', ['scan', 'recon']),
    (3, now(), 'malware_detected', '192.0.2.102', '10.0.0.3', 5, 'user1', 'Malware signature match', ['malware', 'trojan']);
```

**Configuration**:
```zeek
redef SecurityEvents::clickhouse_host = "your-server.example.com";
redef SecurityEvents::poll_interval = 30sec;
redef SecurityEvents::lookback_window = 2min;
redef SecurityEvents::min_severity = 2;
```

**Run**:
```bash
zeek -i eth0 security-events.zeek
```

---

## Quick Start

### For Beginners

Start with `simple-watchlist.zeek`:
1. Create the database table
2. Insert test data
3. Update the hostname in the script
4. Run the script

### For Intermediate Users

Try `threat-intel.zeek`:
1. Set up the threat intelligence database
2. Configure connection parameters
3. Adjust severity thresholds
4. Run on live traffic or PCAP

### For Advanced Users

Implement `security-events.zeek`:
1. Set up event ingestion pipeline
2. Configure streaming parameters
3. Customize event handlers
4. Deploy in production environment

---

## Common Patterns

### Loading Static Data (One-Shot)

```zeek
local ch_info = ClickHouse::Info(
    $hostname = "localhost",
    $query = "SELECT * FROM static_config",
    $poll_interval = 0sec  # One-time load
);

Input::add_table([...]);
```

### Streaming Updates (Polling)

```zeek
local ch_info = ClickHouse::Info(
    $hostname = "localhost",
    $query = "SELECT * FROM events WHERE timestamp > now() - INTERVAL 5 MINUTE",
    $poll_interval = 30sec  # Poll every 30 seconds
);

Input::add_event([...]);
```

### Manual Refresh

```zeek
# In zeek_init()
schedule 5min { refresh_data() };

event refresh_data()
    {
    Input::force_update("my_stream");
    schedule 5min { refresh_data() };
    }
```

---

## Configuration Templates

### Minimal Configuration

```zeek
local ch_info = ClickHouse::Info(
    $query = "SELECT * FROM my_table"
);
```

### Full Configuration

```zeek
local ch_info = ClickHouse::Info(
    $hostname = "clickhouse.example.com",
    $server_port = 9000,
    $database = "security",
    $user = "zeek_reader",
    $password = getenv("CLICKHOUSE_PASSWORD"),
    $query = "SELECT ip, threat_type, severity FROM threats WHERE active = 1",
    $poll_interval = 60sec
);
```

### Using Environment Variables

```zeek
local ch_info = ClickHouse::Info(
    $hostname = getenv("CLICKHOUSE_HOST") != "" ? getenv("CLICKHOUSE_HOST") : "localhost",
    $server_port = to_count(getenv("CLICKHOUSE_PORT") != "" ? getenv("CLICKHOUSE_PORT") : "9000"),
    $database = getenv("CLICKHOUSE_DB") != "" ? getenv("CLICKHOUSE_DB") : "default",
    $user = getenv("CLICKHOUSE_USER") != "" ? getenv("CLICKHOUSE_USER") : "default",
    $password = getenv("CLICKHOUSE_PASSWORD"),
    $query = "SELECT * FROM my_table"
);
```

---

## Testing Examples

### Test with Sample Data

```bash
# 1. Start ClickHouse
sudo systemctl start clickhouse-server

# 2. Create test database
clickhouse-client < setup-test-data.sql

# 3. Run example in test mode
zeek -r test.pcap simple-watchlist.zeek

# 4. Or run on live interface
sudo zeek -i eth0 simple-watchlist.zeek
```

### Verify Data Loading

Add debug output to your script:

```zeek
event Input::end_of_data(name: string, source: string)
    {
    print fmt("Loaded data from: %s", name);
    print fmt("Table size: %d entries", |my_table|);
    
    # Print first few entries
    local count = 0;
    for ( idx, val in my_table )
        {
        print fmt("  Entry %d: %s", count, idx);
        if ( ++count >= 5 )
            break;
        }
    }
```

---

## Performance Tuning

### Optimize Queries

```sql
-- Bad: Full table scan
SELECT * FROM threat_intel;

-- Good: Use indexes and filters
SELECT ip_address, threat_type, severity 
FROM threat_intel 
WHERE last_seen > now() - INTERVAL 1 DAY 
  AND severity >= 3;
```

### Adjust Polling Intervals

```zeek
# High-frequency updates (more load)
$poll_interval = 10sec

# Moderate updates (balanced)
$poll_interval = 60sec

# Low-frequency updates (less load)
$poll_interval = 5min
```

### Limit Result Sets

```sql
-- Use LIMIT for testing
SELECT * FROM events LIMIT 1000;

-- Use time windows for streaming
SELECT * FROM events 
WHERE timestamp > now() - INTERVAL 1 MINUTE;
```

---

## Troubleshooting

### Script Doesn't Load Data

1. Check ClickHouse connectivity:
   ```bash
   clickhouse-client --host localhost --port 9000
   ```

2. Verify query syntax:
   ```bash
   clickhouse-client --query "SELECT * FROM your_table LIMIT 5"
   ```

3. Enable debug output in script:
   ```zeek
   print "Attempting to connect...";
   # Add after Input::add_table()
   ```

### Connection Errors

```bash
# Check ClickHouse is listening
netstat -tlnp | grep 9000

# Check firewall
sudo iptables -L | grep 9000

# Test with clickhouse-client
clickhouse-client --host your-server --port 9000 --user your-user --password your-password
```

### No Alerts Generated

1. Verify data is loaded: Add `end_of_data` event
2. Check filter conditions: Ensure IPs/data match
3. Test with known-good data
4. Add debug prints in event handlers

---

## Customization

### Create Your Own Example

Template for new scripts:

```zeek
@load base/frameworks/input
@load VNET/ClickHouse

module MyModule;

export {
    # Define your types
    type MyRecord: record {
        field1: string;
        field2: count;
    };
    
    # Define your table
    global my_table: table[string] of MyRecord = table();
}

event zeek_init()
    {
    # Configure ClickHouse
    local ch_info = ClickHouse::Info(
        $hostname = "localhost",
        $query = "SELECT field1, field2 FROM my_table"
    );
    
    # Add input source
    Input::add_table([
        $name = "my_input",
        $source = "clickhouse://localhost",
        $reader = Input::READER_CLICKHOUSE,
        $mode = Input::REREAD,
        $destination = my_table,
        $idx = MyRecord,
        $val = MyRecord,
        $config = ClickHouse::config_to_table(ch_info)
    ]);
    }

event Input::end_of_data(name: string, source: string)
    {
    if ( name == "my_input" )
        print fmt("Loaded %d records", |my_table|);
    }

# Add your custom logic here
```

---

## Additional Resources

- **Main README**: `../README.md` - Full plugin documentation
- **Installation Guide**: `../INSTALL.md` - Setup instructions
- **Quick Start**: `../QUICKSTART.md` - Get running in 15 minutes
- **Zeek Input Framework**: https://docs.zeek.org/en/master/frameworks/input.html
- **ClickHouse SQL**: https://clickhouse.com/docs/en/sql-reference/

---

## Contributing Examples

Have a useful example? Contributions are welcome!

1. Create a well-documented script
2. Include SQL setup commands
3. Test with sample data
4. Add description to this README
5. Submit a pull request

---

## License

All examples are provided under the same license as the plugin (BSD 3-Clause).
See `../COPYING` for details.
