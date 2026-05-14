// ClickHouse Input Reader Implementation for Zeek

#include "ClickHouse.h"
#include <zeek/util.h>
#include <zeek/net_util.h>
#include <clickhouse/types/types.h>
#include <netinet/in.h>
#include <sstream>

// Bring common Zeek threading/input names into scope for method bodies.
using namespace zeek::input;
using namespace zeek::threading;

namespace zeek {
namespace input {
namespace reader {

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

ReaderBackend* ClickHouse::Instantiate(ReaderFrontend* frontend)
{
    return new ClickHouse(frontend);
}

// ---------------------------------------------------------------------------
// Constructor / Destructor
// ---------------------------------------------------------------------------

ClickHouse::ClickHouse(ReaderFrontend* frontend)
    : ReaderBackend(frontend),
      hostname_("localhost"),
      server_port_(9000),
      database_("default"),
      user_("default"),
      password_(""),
      query_(""),
      poll_interval_(0.0),
      num_fields_(0),
      fields_(nullptr),
      last_execute_time_(0.0),
      stream_mode_(false),
      initialized_(false)
{
}

ClickHouse::~ClickHouse()
{
    DoClose();
}

// ---------------------------------------------------------------------------
// ReaderBackend interface
// ---------------------------------------------------------------------------

bool ClickHouse::DoInit(const ReaderInfo& info, int num_fields,
                        const Field* const* fields)
{
    num_fields_ = num_fields;
    fields_     = fields;

    if ( ! ParseConfig(info) )
        return false;

    if ( query_.empty() )
    {
        Error("query parameter is required");
        return false;
    }

    stream_mode_ = (poll_interval_ > 0.0);

    try
    {
        clickhouse::ClientOptions opts;
        opts.SetHost(hostname_);
        opts.SetPort(server_port_);
        opts.SetDefaultDatabase(database_);
        opts.SetUser(user_);
        opts.SetPassword(password_);

        client_ = std::make_unique<clickhouse::Client>(opts);
        client_->Execute("SELECT 1");   // verify connectivity
    }
    catch ( const std::exception& e )
    {
        Error(Fmt("Failed to connect to ClickHouse: %s", e.what()));
        return false;
    }

    initialized_ = true;
    return ExecuteQuery();
}

void ClickHouse::DoClose()
{
    client_.reset();
    initialized_ = false;
}

bool ClickHouse::DoUpdate()
{
    if ( stream_mode_ )
        return ExecuteQuery();
    return true;
}

bool ClickHouse::DoHeartbeat(double /* network_time */, double current_time)
{
    if ( ! stream_mode_ || ! initialized_ )
        return true;

    if ( current_time - last_execute_time_ >= poll_interval_ )
    {
        if ( ! ExecuteQuery() )
            return false;
        last_execute_time_ = current_time;
    }
    return true;
}

// ---------------------------------------------------------------------------
// Configuration parsing
// ---------------------------------------------------------------------------

bool ClickHouse::ParseConfig(const ReaderInfo& info)
{
    // config_map is std::map<const char*, const char*, CompareString> — a value,
    // not a pointer.  Keys are const char*, so use string_view for comparison.
    for ( const auto& [key, value] : info.config )
    {
        const std::string_view k = key;
        if ( k == "hostname" )
        {
            hostname_ = value;
        }
        else if ( k == "server_port" )
        {
            try   { server_port_ = static_cast<uint16_t>(std::stoi(value)); }
            catch ( ... )
            {
                Error(Fmt("Invalid port: %s", value));
                return false;
            }
        }
        else if ( k == "database" )
        {
            database_ = value;
        }
        else if ( k == "user" )
        {
            user_ = value;
        }
        else if ( k == "password" )
        {
            password_ = value;
        }
        else if ( k == "query" )
        {
            query_ = value;
        }
        else if ( k == "poll_interval" )
        {
            try   { poll_interval_ = std::stod(value); }
            catch ( ... )
            {
                Error(Fmt("Invalid poll_interval: %s", value));
                return false;
            }
        }
        else
        {
            Warning(Fmt("Unknown configuration option: %s", key));
        }
    }
    return true;
}

// ---------------------------------------------------------------------------
// Query execution
// ---------------------------------------------------------------------------

bool ClickHouse::ExecuteQuery()
{
    if ( ! initialized_ || ! client_ )
    {
        Error("ClickHouse client not initialized");
        return false;
    }

    try
    {
        client_->Select(query_, [this](const clickhouse::Block& block)
        {
            for ( size_t row = 0; row < block.GetRowCount(); ++row )
            {
                auto vals  = std::make_unique<Value*[]>(num_fields_);
                bool row_ok = true;

                for ( int fi = 0; fi < num_fields_; ++fi )
                {
                    if ( fi >= static_cast<int>(block.GetColumnCount()) )
                    {
                        Error(Fmt("Column index %d out of range (block has %zu columns)",
                                  fi, block.GetColumnCount()));
                        row_ok = false;
                        break;
                    }

                    vals[fi] = new Value(fields_[fi]->type, true);

                    if ( ! ConvertValue(*block[fi], row, fields_[fi], vals[fi]) )
                    {
                        Error(Fmt("Failed to convert value for field '%s' at row %zu",
                                  fields_[fi]->name, row));
                        row_ok = false;
                        break;
                    }
                }

                if ( row_ok )
                {
                    // Transfer ownership of the array and Value objects to
                    // the framework. Put() enqueues a PutMessage that holds
                    // this pointer and is processed asynchronously on the
                    // main thread; we must NOT free the memory afterwards.
                    Put(vals.release());
                }
                else
                {
                    // Ownership was never transferred — free what we allocated.
                    // make_unique<Value*[]> zero-initialises, so unallocated
                    // slots are nullptr and delete nullptr is a no-op.
                    for ( int i = 0; i < num_fields_; ++i )
                        delete vals[i];
                }
            }
        });

        EndCurrentSend();
    }
    catch ( const std::exception& e )
    {
        Error(Fmt("Query execution failed: %s", e.what()));
        return false;
    }

    return true;
}

// ---------------------------------------------------------------------------
// ClickHouse column cell → string helper
// ---------------------------------------------------------------------------

std::string ClickHouse::GetColumnStringValue(const clickhouse::Column& column, size_t row)
{
    std::ostringstream oss;
    const auto tc = column.Type()->GetCode();

    switch ( tc )
    {
        case clickhouse::Type::String:
            return std::string(column.As<clickhouse::ColumnString>()->At(row));

        case clickhouse::Type::FixedString:
            return std::string(column.As<clickhouse::ColumnFixedString>()->At(row));

        case clickhouse::Type::Int8:
            oss << static_cast<int>(column.As<clickhouse::ColumnInt8>()->At(row));
            return oss.str();
        case clickhouse::Type::Int16:
            oss << column.As<clickhouse::ColumnInt16>()->At(row);
            return oss.str();
        case clickhouse::Type::Int32:
            oss << column.As<clickhouse::ColumnInt32>()->At(row);
            return oss.str();
        case clickhouse::Type::Int64:
            oss << column.As<clickhouse::ColumnInt64>()->At(row);
            return oss.str();

        case clickhouse::Type::UInt8:
            oss << static_cast<unsigned>(column.As<clickhouse::ColumnUInt8>()->At(row));
            return oss.str();
        case clickhouse::Type::UInt16:
            oss << column.As<clickhouse::ColumnUInt16>()->At(row);
            return oss.str();
        case clickhouse::Type::UInt32:
            oss << column.As<clickhouse::ColumnUInt32>()->At(row);
            return oss.str();
        case clickhouse::Type::UInt64:
            oss << column.As<clickhouse::ColumnUInt64>()->At(row);
            return oss.str();

        case clickhouse::Type::Float32:
            oss << column.As<clickhouse::ColumnFloat32>()->At(row);
            return oss.str();
        case clickhouse::Type::Float64:
            oss << column.As<clickhouse::ColumnFloat64>()->At(row);
            return oss.str();

        case clickhouse::Type::DateTime:
            oss << column.As<clickhouse::ColumnDateTime>()->At(row);
            return oss.str();
        case clickhouse::Type::Date:
            oss << column.As<clickhouse::ColumnDate>()->At(row);
            return oss.str();

        default:
            return "";
    }
}

// ---------------------------------------------------------------------------
// ClickHouse column cell → Zeek threading::Value
// ---------------------------------------------------------------------------

bool ClickHouse::ConvertValue(const clickhouse::Column& column, size_t row,
                               const Field* field, Value* val)
{
    const auto tc = column.Type()->GetCode();

    try
    {
        switch ( field->type )
        {
            // ── bool ───────────────────────────────────────────────────────
            case TYPE_BOOL:
            {
                if ( tc == clickhouse::Type::UInt8 )
                    val->val.int_val = column.As<clickhouse::ColumnUInt8>()->At(row) ? 1 : 0;
                else
                {
                    const auto s = GetColumnStringValue(column, row);
                    val->val.int_val = ( ! s.empty() && s != "0" ) ? 1 : 0;
                }
                break;
            }

            // ── int ────────────────────────────────────────────────────────
            case TYPE_INT:
            {
                switch ( tc )
                {
                    case clickhouse::Type::Int64:
                        val->val.int_val = column.As<clickhouse::ColumnInt64>()->At(row); break;
                    case clickhouse::Type::Int32:
                        val->val.int_val = column.As<clickhouse::ColumnInt32>()->At(row); break;
                    case clickhouse::Type::Int16:
                        val->val.int_val = column.As<clickhouse::ColumnInt16>()->At(row); break;
                    case clickhouse::Type::Int8:
                        val->val.int_val = column.As<clickhouse::ColumnInt8>()->At(row);  break;
                    default:
                        val->val.int_val = std::stoll(GetColumnStringValue(column, row));
                }
                break;
            }

            // ── count / counter ────────────────────────────────────────────
            case TYPE_COUNT:
            {
                switch ( tc )
                {
                    case clickhouse::Type::UInt64:
                        val->val.uint_val = column.As<clickhouse::ColumnUInt64>()->At(row); break;
                    case clickhouse::Type::UInt32:
                        val->val.uint_val = column.As<clickhouse::ColumnUInt32>()->At(row); break;
                    case clickhouse::Type::UInt16:
                        val->val.uint_val = column.As<clickhouse::ColumnUInt16>()->At(row); break;
                    case clickhouse::Type::UInt8:
                        val->val.uint_val = column.As<clickhouse::ColumnUInt8>()->At(row);  break;
                    default:
                        val->val.uint_val = std::stoull(GetColumnStringValue(column, row));
                }
                break;
            }

            // ── double / interval ──────────────────────────────────────────
            case TYPE_DOUBLE:
            case TYPE_INTERVAL:
            {
                switch ( tc )
                {
                    case clickhouse::Type::Float64:
                        val->val.double_val =
                            column.As<clickhouse::ColumnFloat64>()->At(row); break;
                    case clickhouse::Type::Float32:
                        val->val.double_val =
                            static_cast<double>(column.As<clickhouse::ColumnFloat32>()->At(row));
                        break;
                    default:
                        val->val.double_val = std::stod(GetColumnStringValue(column, row));
                }
                break;
            }

            // ── time ───────────────────────────────────────────────────────
            case TYPE_TIME:
            {
                if ( tc == clickhouse::Type::DateTime )
                    val->val.double_val =
                        static_cast<double>(column.As<clickhouse::ColumnDateTime>()->At(row));
                else if ( tc == clickhouse::Type::Date )
                    val->val.double_val =
                        static_cast<double>(column.As<clickhouse::ColumnDate>()->At(row)) * 86400.0;
                else
                    val->val.double_val = std::stod(GetColumnStringValue(column, row));
                break;
            }

            // ── string ─────────────────────────────────────────────────────
            case TYPE_STRING:
            {
                const auto s = GetColumnStringValue(column, row);
                val->val.string_val.data   = zeek::util::copy_string(s.c_str());
                val->val.string_val.length = static_cast<int>(s.size());
                break;
            }

            // ── port ───────────────────────────────────────────────────────
            // Expected column format: "80/tcp", "443/tcp", "53/udp", or bare "80".
            // Protocol values follow IP protocol numbers (TCP=6, UDP=17, ICMP=1).
            case TYPE_PORT:
            {
                const auto s    = GetColumnStringValue(column, row);
                const auto slash = s.find('/');

                uint64_t       port_num = 0;
                TransportProto proto    = TRANSPORT_UNKNOWN;

                if ( slash != std::string::npos )
                {
                    port_num = std::stoull(s.substr(0, slash));
                    const auto ps = s.substr(slash + 1);
                    if      ( ps == "tcp"  ) proto = TRANSPORT_TCP;
                    else if ( ps == "udp"  ) proto = TRANSPORT_UDP;
                    else if ( ps == "icmp" ) proto = TRANSPORT_ICMP;
                }
                else
                {
                    port_num = std::stoull(s);
                }

                val->val.port_val.port  = port_num;
                val->val.port_val.proto = proto;
                break;
            }

            // ── addr ───────────────────────────────────────────────────────
            // addr_t = { IPFamily family; union { in_addr in4; in6_addr in6; } in; }
            // Use inet_pton to fill the correct union member directly.
            case TYPE_ADDR:
            {
                const auto s = GetColumnStringValue(column, row);
                if ( inet_pton(AF_INET, s.c_str(),
                               &val->val.addr_val.in.in4) == 1 )
                {
                    val->val.addr_val.family = IPv4;
                }
                else if ( inet_pton(AF_INET6, s.c_str(),
                                    &val->val.addr_val.in.in6) == 1 )
                {
                    val->val.addr_val.family = IPv6;
                }
                else
                {
                    Error(Fmt("Invalid IP address: %s", s.c_str()));
                    return false;
                }
                break;
            }

            // ── subnet ─────────────────────────────────────────────────────
            // subnet_t = { addr_t prefix; uint8_t length; }
            // addr_t has the same layout as above — no separate family field
            // on subnet_t itself.
            case TYPE_SUBNET:
            {
                const auto s     = GetColumnStringValue(column, row);
                const auto slash = s.find('/');
                if ( slash == std::string::npos )
                {
                    Error(Fmt("Invalid subnet (missing /): %s", s.c_str()));
                    return false;
                }
                const auto addr_str   = s.substr(0, slash);
                const uint8_t pfx_len = static_cast<uint8_t>(
                    std::stoul(s.substr(slash + 1)));

                if ( inet_pton(AF_INET, addr_str.c_str(),
                               &val->val.subnet_val.prefix.in.in4) == 1 )
                {
                    val->val.subnet_val.prefix.family = IPv4;
                }
                else if ( inet_pton(AF_INET6, addr_str.c_str(),
                                    &val->val.subnet_val.prefix.in.in6) == 1 )
                {
                    val->val.subnet_val.prefix.family = IPv6;
                }
                else
                {
                    Error(Fmt("Invalid subnet address: %s", addr_str.c_str()));
                    return false;
                }
                val->val.subnet_val.length = pfx_len;
                break;
            }

            // ── enum ───────────────────────────────────────────────────────
            // enum_val was removed in Zeek 8.x; enum names are passed as strings.
            case TYPE_ENUM:
            {
                const auto s = GetColumnStringValue(column, row);
                val->val.string_val.data   = zeek::util::copy_string(s.c_str());
                val->val.string_val.length = static_cast<int>(s.size());
                break;
            }

            default:
                Error(Fmt("Unsupported Zeek type %d for field '%s'",
                          field->type, field->name));
                return false;
        }
    }
    catch ( const std::exception& e )
    {
        Error(Fmt("Value conversion error for field '%s': %s",
                  field->name, e.what()));
        return false;
    }

    val->present = true;
    return true;
}

} // namespace reader
} // namespace input
} // namespace zeek
