##! Example: Streaming Security Events from ClickHouse
##!
##! This example demonstrates how to continuously poll ClickHouse for
##! security events and process them in Zeek in real-time.
##!
##! Use Case: You have a SIEM or security platform that writes events
##! to ClickHouse, and you want Zeek to consume and act on those events.
##!
##! Setup:
##!   1. Create a ClickHouse table:
##!      CREATE TABLE security_events (
##!          event_id UInt64,
##!          timestamp DateTime,
##!          event_type String,
##!          source_ip String,
##!          dest_ip String,
##!          severity UInt8,
##!          username String,
##!          details String,
##!          tags Array(String)
##!      ) ENGINE = MergeTree()
##!      ORDER BY (timestamp, event_id);
##!
##!   2. Insert some test data:
##!      INSERT INTO security_events VALUES
##!          (1, now(), 'login_failure', '192.0.2.100', '10.0.0.1', 3, 'admin', 'Failed login attempt', ['authentication', 'failed']),
##!          (2, now(), 'suspicious_traffic', '192.0.2.101', '10.0.0.2', 4, '', 'Unusual port scan detected', ['scan', 'recon']),
##!          (3, now(), 'malware_detected', '192.0.2.102', '10.0.0.3', 5, 'user1', 'Malware signature match', ['malware', 'trojan']);
##!
##!   3. Update the connection settings below
##!   4. Run: zeek -i eth0 security-events.zeek

@load base/frameworks/input
@load base/frameworks/notice
@load VNET/ClickHouse

module SecurityEvents;

export {
    redef enum Notice::Type += {
        ## High severity security event from external source
        External_Security_Event,
        ## Critical security event requiring immediate attention
        Critical_Security_Event,
        ## Correlated event: security event involving currently active connection
        Correlated_Security_Event
    };

    ## Configuration for ClickHouse connection
    const clickhouse_host = "localhost" &redef;
    const clickhouse_port = 9000 &redef;
    const clickhouse_db = "default" &redef;
    const clickhouse_user = "default" &redef;
    const clickhouse_password = "" &redef;

    ## How often to poll for new events
    const poll_interval = 30sec &redef;

    ## How far back to look for events (prevents re-processing old events)
    const lookback_window = 2min &redef;

    ## Minimum severity to process (1-5, where 5 is most critical)
    const min_severity = 2 &redef;

    ## Event record structure matching ClickHouse query
    type Event: record {
        event_id: count;
        timestamp: time;
        event_type: string;
        source_ip: addr;
        dest_ip: addr;
        severity: count;
        username: string;
        details: string;
    };

    ## Event handler for security events from ClickHouse
    global security_event: event(description: Input::EventDescription, t: Event);

    ## Track processed event IDs to avoid duplicates
    global processed_events: set[count] = set();

    ## Track event statistics
    global event_stats: table[string] of count &default=0;
    global total_events_processed: count = 0;
}

event zeek_init()
    {
    print "SecurityEvents: Starting to stream security events from ClickHouse...";
    print fmt("  Poll interval: %s", poll_interval);
    print fmt("  Lookback window: %s", lookback_window);
    print fmt("  Minimum severity: %d", min_severity);

    # Configure ClickHouse connection for streaming
    local ch_info = ClickHouse::Info(
        $hostname = clickhouse_host,
        $server_port = clickhouse_port,
        $database = clickhouse_db,
        $user = clickhouse_user,
        $password = clickhouse_password,
        # Query events from the lookback window with minimum severity
        $query = fmt("SELECT event_id, timestamp, event_type, source_ip, dest_ip, severity, username, details FROM security_events WHERE timestamp > now() - INTERVAL %d SECOND AND severity >= %d ORDER BY timestamp DESC",
                     interval_to_double(lookback_window),
                     min_severity),
        # Enable streaming mode with polling
        $poll_interval = poll_interval
    );

    # Add event stream using helper function
    Input::add_event(ClickHouse::event_description(
        "security_event_stream",
        ch_info,
        Event,
        security_event
    ));
    }

event security_event(description: Input::EventDescription, t: Event)
    {
    # Skip if we've already processed this event
    if ( t$event_id in processed_events )
        return;

    # Mark as processed
    add processed_events[t$event_id];
    total_events_processed += 1;

    # Update statistics
    event_stats[t$event_type] += 1;

    # Log the event
    print fmt("SecurityEvents: [%s] Type=%s, Severity=%d, Source=%s, Dest=%s",
              strftime("%Y-%m-%d %H:%M:%S", t$timestamp),
              t$event_type,
              t$severity,
              t$source_ip,
              t$dest_ip);

    if ( t$username != "" )
        print fmt("  User: %s", t$username);
    print fmt("  Details: %s", t$details);

    # Generate notices for high severity events
    if ( t$severity >= 4 )
        {
        local notice_type = t$severity >= 5 ? Critical_Security_Event : External_Security_Event;

        NOTICE([$note=notice_type,
                $msg=fmt("External security event: %s (severity %d)", t$event_type, t$severity),
                $sub=t$details,
                $src=t$source_ip,
                $identifier=cat(t$event_id)]);
        }

    # Check if this event correlates with active connections
    check_correlation(t);

    # Take specific actions based on event type
    handle_event_type(t);
    }

function check_correlation(ev: Event)
    {
    # Check if there are any active connections involving the source or dest IP
    local found = F;

    for ( id in Conn::conn_store )
        {
        if ( id$orig_h == ev$source_ip || id$resp_h == ev$source_ip ||
             id$orig_h == ev$dest_ip || id$resp_h == ev$dest_ip )
            {
            found = T;

            NOTICE([$note=Correlated_Security_Event,
                    $msg=fmt("Security event correlates with active connection: %s", ev$event_type),
                    $sub=fmt("Connection: %s -> %s", id$orig_h, id$resp_h),
                    $conn=Conn::conn_store[id],
                    $identifier=cat(ev$event_id, "-", id$orig_h, "-", id$resp_h)]);

            print fmt("  ** CORRELATION: Event involves active connection %s:%s -> %s:%s",
                      id$orig_h, id$orig_p, id$resp_h, id$resp_p);
            }
        }

    if ( found )
        print "  ** This event correlates with current network activity!";
    }

function handle_event_type(ev: Event)
    {
    # Take specific actions based on event type
    switch ( ev$event_type )
        {
        case "login_failure":
            handle_login_failure(ev);
            break;
        case "suspicious_traffic":
            handle_suspicious_traffic(ev);
            break;
        case "malware_detected":
            handle_malware_detected(ev);
            break;
        case "data_exfiltration":
            handle_data_exfiltration(ev);
            break;
        default:
            # Generic handling for unknown event types
            break;
        }
    }

function handle_login_failure(ev: Event)
    {
    print fmt("  -> Processing login failure from %s (user: %s)", ev$source_ip, ev$username);
    # Could implement brute force detection, add to watchlist, etc.
    }

function handle_suspicious_traffic(ev: Event)
    {
    print fmt("  -> Processing suspicious traffic: %s -> %s", ev$source_ip, ev$dest_ip);
    # Could trigger additional monitoring, packet capture, etc.
    }

function handle_malware_detected(ev: Event)
    {
    print fmt("  -> MALWARE ALERT: %s detected on %s", ev$details, ev$source_ip);
    # Could isolate host, trigger incident response, etc.
    }

function handle_data_exfiltration(ev: Event)
    {
    print fmt("  -> DATA EXFILTRATION WARNING: %s -> %s", ev$source_ip, ev$dest_ip);
    # Critical event - might want to block traffic, alert SOC, etc.
    }

# Periodic statistics reporting
event print_statistics()
    {
    print "";
    print "========== Security Events Statistics ==========";
    print fmt("Total events processed: %d", total_events_processed);
    print fmt("Unique events: %d", |processed_events|);
    print "";
    print "Breakdown by event type:";

    # Sort by count (descending)
    local sorted_types: vector of string = vector();
    for ( event_type in event_stats )
        sorted_types += event_type;

    for ( i in sorted_types )
        {
        local event_type = sorted_types[i];
        print fmt("  %-30s : %5d events", event_type, event_stats[event_type]);
        }
    print "================================================";
    print "";

    # Schedule next report
    schedule 5min { print_statistics() };
    }

# Start periodic reporting after initial data load
event Input::end_of_data(name: string, source: string)
    {
    if ( name == "security_event_stream" )
        {
        print fmt("SecurityEvents: Initial data load complete (%d events)", total_events_processed);

        # Schedule first statistics report
        schedule 5min { print_statistics() };
        }
    }

# Cleanup old processed event IDs to prevent memory growth
event cleanup_processed_events()
    {
    # Keep only recent event IDs (e.g., last 10,000)
    if ( |processed_events| > 10000 )
        {
        print fmt("SecurityEvents: Cleaning up old event IDs (current: %d)", |processed_events|);
        # In a real implementation, you'd want to be smarter about this
        # (e.g., remove oldest IDs, or use a time-based cleanup)
        # For now, just clear all and start fresh
        clear_table(processed_events);
        print "SecurityEvents: Event ID cache cleared";
        }

    schedule 1hr { cleanup_processed_events() };
    }

event zeek_init() &priority=-5
    {
    # Schedule periodic cleanup (lower priority so it runs after main init)
    schedule 1hr { cleanup_processed_events() };
    }

# Final statistics on shutdown
event zeek_done()
    {
    print "";
    print "========== SecurityEvents Final Report ==========";
    print fmt("Total events processed: %d", total_events_processed);
    print fmt("Unique events tracked: %d", |processed_events|);
    print "";
    print "Event type breakdown:";
    for ( event_type, count in event_stats )
        print fmt("  %s: %d", event_type, count);
    print "==================================================";
    }
