// ClickHouse Input Reader for Zeek
//
// This reader implements the Zeek Input Framework interface to read
// data from ClickHouse databases.

#pragma once

#include <zeek/input/ReaderBackend.h>
#include <zeek/IPAddr.h>
#include <clickhouse/client.h>
#include <memory>
#include <string>
#include <vector>

namespace zeek {
namespace input {
namespace reader {

/**
 * ClickHouse reader for Zeek Input Framework
 *
 * Configuration options (passed via Input::add_table/add_event):
 *   - hostname:      ClickHouse server hostname (default: "localhost")
 *   - server_port:   ClickHouse server port     (default: 9000)
 *   - database:      Database name              (default: "default")
 *   - user:          Username                   (default: "default")
 *   - password:      Password                   (default: "")
 *   - query:         SQL query to execute       (required)
 *   - poll_interval: Seconds between re-queries in streaming mode
 *                    (default: 0 = one-shot)
 */
class ClickHouse : public zeek::input::ReaderBackend
{
public:
    explicit ClickHouse(zeek::input::ReaderFrontend* frontend);
    ~ClickHouse() override;

    // Factory method used during plugin component registration
    static zeek::input::ReaderBackend* Instantiate(zeek::input::ReaderFrontend* frontend);

protected:
    // ReaderBackend interface
    bool DoInit(const ReaderInfo& info, int num_fields,
                const zeek::threading::Field* const* fields) override;
    void DoClose() override;
    bool DoUpdate() override;
    bool DoHeartbeat(double network_time, double current_time) override;

private:
    // Parse configuration entries from ReaderInfo::config
    bool ParseConfig(const ReaderInfo& info);

    // Execute the configured SQL query and stream results into Zeek
    bool ExecuteQuery();

    // Convert a single ClickHouse column cell to a Zeek threading::Value
    bool ConvertValue(const clickhouse::Column& column, size_t row,
                      const zeek::threading::Field* field,
                      zeek::threading::Value* val);

    // Return a string representation of any ClickHouse column cell
    std::string GetColumnStringValue(const clickhouse::Column& column, size_t row);

    // ── Connection parameters ──────────────────────────────────────────────
    std::string hostname_;
    uint16_t    server_port_;
    std::string database_;
    std::string user_;
    std::string password_;
    std::string query_;
    double      poll_interval_;

    // ── ClickHouse client ──────────────────────────────────────────────────
    std::unique_ptr<clickhouse::Client> client_;

    // ── Field metadata (owned by the framework, not by us) ────────────────
    int                                  num_fields_;
    const zeek::threading::Field* const* fields_;

    // ── Polling state ──────────────────────────────────────────────────────
    double last_execute_time_;
    bool   stream_mode_;   ///< true when poll_interval_ > 0
    bool   initialized_;
};

} // namespace reader
} // namespace input
} // namespace zeek
