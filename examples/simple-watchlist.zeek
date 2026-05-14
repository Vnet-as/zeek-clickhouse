##! Example: Simple IP Watchlist from ClickHouse
##!
##! This is a minimal example showing how to load a simple IP watchlist
##! from ClickHouse and alert when connections involve watchlisted IPs.
##!
##! Setup:
##!   1. Create a ClickHouse table:
##!      CREATE TABLE ip_watchlist (
##!          ip_address String,
##!          reason String,
##!          added_date DateTime
##!      ) ENGINE = MergeTree()
##!      ORDER BY ip_address;
##!
##!   2. Insert some test data:
##!      INSERT INTO ip_watchlist VALUES
##!          ('192.0.2.100', 'Previous incident', now()),
##!          ('192.0.2.101', 'Suspicious behavior', now()),
##!          ('198.51.100.50', 'Known bad actor', now());
##!
##!   3. Update the connection settings below
##!   4. Run: zeek -i eth0 simple-watchlist.zeek

@load base/frameworks/input
@load VNET/ClickHouse

module Watchlist;

export {
    ## Configuration - adjust these for your environment
    const clickhouse_host = "localhost" &redef;
    const clickhouse_port = 9000 &redef;
    const clickhouse_db = "default" &redef;

    ## Simple watchlist entry
    type Entry: record {
        ip: addr;
        reason: string;
        added_date: time;
    };

    ## The watchlist table (indexed by IP)
    global watchlist: table[addr] of Entry = table();
}

event zeek_init()
    {
    print "Loading IP watchlist from ClickHouse...";

    # Configure ClickHouse connection
    local ch_info = ClickHouse::Info(
        $hostname = clickhouse_host,
        $server_port = clickhouse_port,
        $database = clickhouse_db,
        $query = "SELECT ip_address, reason, added_date FROM ip_watchlist"
    );

    # Load the watchlist into our table
    Input::add_table([
        $name = "watchlist",
        $source = cat("clickhouse://", clickhouse_host),
        $reader = Input::READER_CLICKHOUSE,
        $mode = Input::REREAD,
        $destination = watchlist,
        $idx = Entry,
        $val = Entry,
        $config = ClickHouse::config_to_table(ch_info)
    ]);
    }

event Input::end_of_data(name: string, source: string)
    {
    if ( name == "watchlist" )
        {
        print fmt("Loaded %d IPs into watchlist", |watchlist|);

        # Print the watchlist for verification
        for ( ip, entry in watchlist )
            print fmt("  %s: %s (added %s)", ip, entry$reason,
                      strftime("%Y-%m-%d", entry$added_date));
        }
    }

# Check connections against the watchlist
event connection_established(c: connection)
    {
    local orig = c$id$orig_h;
    local resp = c$id$resp_h;

    if ( orig in watchlist )
        {
        local entry = watchlist[orig];
        print fmt("ALERT: Connection from watchlisted IP %s -> %s:%s (Reason: %s)",
                  orig, resp, c$id$resp_p, entry$reason);
        }

    if ( resp in watchlist )
        {
        local entry = watchlist[resp];
        print fmt("ALERT: Connection to watchlisted IP %s -> %s:%s (Reason: %s)",
                  orig, resp, c$id$resp_p, entry$reason);
        }
    }
