// Plugin implementation for Zeek ClickHouse Input Reader
//
// This plugin provides an input reader for the Zeek Input Framework
// that allows reading data from ClickHouse databases.

#include "Plugin.h"
#include "ClickHouse.h"

namespace plugin {
namespace VNET_ClickHouse {

Plugin plugin;

Plugin::Plugin()
{
    // Plugin initialization
}

Plugin::~Plugin()
{
    // Plugin cleanup
}

zeek::plugin::Configuration Plugin::Configure()
{
    AddComponent(new zeek::input::Component("ClickHouse",
                 zeek::input::reader::ClickHouse::Instantiate));

    zeek::plugin::Configuration config;
    config.name = "VNET::ClickHouse";
    config.description = "ClickHouse input reader for Zeek Input Framework";
    config.version.major = 1;
    config.version.minor = 0;
    config.version.patch = 0;

    return config;
}

} // namespace VNET_ClickHouse
} // namespace plugin
