##! Example: Loading Threat Intelligence from ClickHouse
##!
##! This example demonstrates how to load a threat intelligence feed
##! from a ClickHouse database and use it to alert on suspicious connections.
##!
##! Setup:
##!   1. Create a ClickHouse table:
##!      CREATE TABLE threat_intel (
##!          ip_address String,
##!          threat_type String,
##!          severity UInt8,
##!          first_seen DateTime,
##!          last_seen DateTime,
##!          description String
##!      ) ENGINE = MergeTree()
##!      ORDER BY (ip_address, last_seen);
##!
##!   2. Insert some test data:
##!      INSERT INTO threat_intel VALUES
##!          ('192.0.2.100', 'malware', 5, now() - INTERVAL 7 DAY, now(), 'Known C2 server'),
##!          ('192.0.2.101', 'scanner', 3, now() - INTERVAL 2 DAY, now(), 'Port scanner'),
##!          ('198.51.100.50', 'spam', 2, now() - INTERVAL 1 DAY, now(), 'Spam source');
##!
##!   3. Update the connection settings below
##!   4. Run: zeek -i eth0 threat-intel.zeek

@load base/frameworks/input
@load base/frameworks/notice
@load VNET/ClickHouse

module ThreatIntel;

export {
    redef enum Notice::Type += {
        ## Indicates a connection involving a known threat actor
        Threat_Connection,
        ## Indicates multiple connections from the same threat
        Repeated_Threat_Connection
    };

    ## Configuration for ClickHouse connection
    const clickhouse_host = "localhost" &redef;
    const clickhouse_port = 9000 &redef;
    const clickhouse_db = "default" &redef;
    const clickhouse_user = "default" &redef;
    const clickhouse_password = "" &redef;

    ## How often to refresh the threat intel data
    const refresh_interval = 5min &redef;

    ## Minimum severity level to alert on (1-5, where 5 is most severe)
    const alert_threshold = 3 &redef;

    ## Table index: just the IP address
    type Idx: record {
        ip: addr;
    };

    ## Table value: threat information
    type Val: record {
        threat_type: string;
        severity: count;
        first_seen: time;
        last_seen: time;
        description: string;
    };

    ## The main threat intelligence table
    global threat_table: table[addr] of Val = table();

    ## Track how many times we've seen each threat IP
    global threat_connection_counts: table[addr] of count &default=0;
}

event zeek_init()
    {
    print "ThreatIntel: Initializing threat intelligence from ClickHouse...";

    # Configure ClickHouse connection
    local ch_info = ClickHouse::Info(
        $hostname = clickhouse_host,
        $server_port = clickhouse_port,
        $database = clickhouse_db,
        $user = clickhouse_user,
        $password = clickhouse_password,
        $query = fmt("SELECT ip_address, threat_type, severity, first_seen, last_seen, description FROM threat_intel WHERE last_seen > now() - INTERVAL %d SECOND", interval_to_double(refresh_interval))
    );

    # Add the input source using the helper function
    Input::add_table(ClickHouse::table_description(
        "threat_intel_feed",
        ch_info,
        threat_table,
        Idx,
        Val
    ));

    # Schedule periodic refresh
    schedule refresh_interval { refresh_threat_intel() };
    }

event Input::end_of_data(name: string, source: string)
    {
    if ( name == "threat_intel_feed" )
        {
        print fmt("ThreatIntel: Loaded %d threat indicators from ClickHouse", |threat_table|);

        # Print some statistics
        local severity_counts: table[count] of count;
        local type_counts: table[string] of count;

        for ( ip, info in threat_table )
            {
            if ( info$severity !in severity_counts )
                severity_counts[info$severity] = 0;
            severity_counts[info$severity] += 1;

            if ( info$threat_type !in type_counts )
                type_counts[info$threat_type] = 0;
            type_counts[info$threat_type] += 1;
            }

        print "ThreatIntel: Breakdown by severity:";
        for ( sev, cnt in severity_counts )
            print fmt("  Severity %d: %d indicators", sev, cnt);

        print "ThreatIntel: Breakdown by type:";
        for ( typ, cnt in type_counts )
            print fmt("  %s: %d indicators", typ, cnt);
        }
    }

event refresh_threat_intel()
    {
    print "ThreatIntel: Refreshing threat intelligence data...";
    Input::force_update("threat_intel_feed");
    schedule refresh_interval { refresh_threat_intel() };
    }

function check_threat(ip: addr, is_orig: bool): bool
    {
    if ( ip !in threat_table )
        return F;

    local info = threat_table[ip];

    # Only alert if severity meets threshold
    if ( info$severity < alert_threshold )
        return F;

    # Increment connection counter
    threat_connection_counts[ip] += 1;

    # Generate notice
    local direction = is_orig ? "originating from" : "responding from";
    local msg = fmt("Connection %s known threat: %s (Type: %s, Severity: %d)",
                    direction, ip, info$threat_type, info$severity);

    NOTICE([$note=Threat_Connection,
            $msg=msg,
            $sub=info$description,
            $identifier=cat(ip)]);

    # Generate additional notice for repeated connections
    if ( threat_connection_counts[ip] >= 5 )
        {
        NOTICE([$note=Repeated_Threat_Connection,
                $msg=fmt("Multiple connections (%d) from threat %s",
                         threat_connection_counts[ip], ip),
                $sub=info$threat_type,
                $identifier=cat(ip, "-repeated")]);
        }

    return T;
    }

# Check originator of new connections
event connection_state_remove(c: connection)
    {
    check_threat(c$id$orig_h, T);
    check_threat(c$id$resp_h, F);
    }

# Check DNS queries for threat IPs
event dns_request(c: connection, msg: dns_msg, query: string, qtype: count, qclass: count)
    {
    check_threat(c$id$orig_h, T);
    }

# Check HTTP requests for threat IPs
event http_request(c: connection, method: string, original_URI: string,
                   unescaped_URI: string, version: string)
    {
    check_threat(c$id$orig_h, T);
    }

# Report statistics on shutdown
event zeek_done()
    {
    print "ThreatIntel: Final Statistics";
    print fmt("  Total threat indicators: %d", |threat_table|);
    print fmt("  Unique threats seen: %d", |threat_connection_counts|);

    local total_connections = 0;
    for ( ip, cnt in threat_connection_counts )
        total_connections += cnt;

    print fmt("  Total threat connections: %d", total_connections);
    }
