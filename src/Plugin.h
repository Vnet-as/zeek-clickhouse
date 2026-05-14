// Plugin header for Zeek ClickHouse Input Reader
//
// This plugin provides an input reader for the Zeek Input Framework
// that allows reading data from ClickHouse databases.

#pragma once

#include <zeek/plugin/Plugin.h>
#include <zeek/input/Component.h>

namespace plugin {
namespace VNET_ClickHouse {

class Plugin : public zeek::plugin::Plugin
{
public:
    Plugin();
    ~Plugin();

protected:
    // Overridden from zeek::plugin::Plugin
    zeek::plugin::Configuration Configure() override;
};

extern Plugin plugin;

} // namespace VNET_ClickHouse
} // namespace plugin
