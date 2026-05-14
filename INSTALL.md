# Installation Guide for Zeek ClickHouse Input Reader Plugin

This guide provides detailed instructions for installing the Zeek ClickHouse Input Reader plugin.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installing Dependencies](#installing-dependencies)
  - [ClickHouse C++ Client Library](#clickhouse-c-client-library)
  - [Zeek](#zeek)
- [Building the Plugin](#building-the-plugin)
- [Installation](#installation)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Platform-Specific Notes](#platform-specific-notes)

## Prerequisites

Before installing the plugin, ensure you have:

- **Operating System**: Linux (Ubuntu, Debian, CentOS, RHEL, etc.) or macOS
- **Zeek**: Version 5.0 or later installed
- **CMake**: Version 3.15 or later
- **C++ Compiler**: GCC 8+, Clang 7+, or compatible with C++17 support
- **Git**: For cloning repositories
- **ClickHouse Server**: Access to a ClickHouse database (local or remote)

### System Requirements

- Minimum 2 GB RAM
- 500 MB free disk space for compilation
- Network access to ClickHouse server

## Installing Dependencies

### ClickHouse C++ Client Library

The plugin requires the ClickHouse C++ client library. Follow these steps to install it:

#### Option 1: Build from Source (Recommended)

```bash
# Install build dependencies
# On Ubuntu/Debian:
sudo apt-get update
sudo apt-get install -y git cmake g++ libssl-dev

# On CentOS/RHEL:
sudo yum install -y git cmake gcc-c++ openssl-devel

# Clone the ClickHouse C++ client repository
git clone https://github.com/ClickHouse/clickhouse-cpp.git
cd clickhouse-cpp

# Create build directory
mkdir build && cd build

# Configure with CMake
cmake .. -DCMAKE_BUILD_TYPE=Release \
         -DCMAKE_INSTALL_PREFIX=/usr/local

# Build (this may take several minutes)
make -j$(nproc)

# Install
sudo make install

# Update library cache
sudo ldconfig
```

#### Option 2: Using Package Managers

Some distributions may have packages available:

```bash
# Arch Linux (AUR)
yay -S clickhouse-cpp

# Note: Most distributions don't have pre-built packages
# Building from source is usually required
```

#### Verify ClickHouse C++ Installation

```bash
# Check if the library is installed
ldconfig -p | grep clickhouse

# Check if headers are available
ls /usr/local/include/clickhouse/
```

You should see output showing the clickhouse-cpp library and header files.

### Zeek

If you don't have Zeek installed, install it from the official repositories or build from source.

#### Using Package Managers

```bash
# Ubuntu/Debian
echo 'deb http://download.opensuse.org/repositories/security:/zeek/xUbuntu_22.04/ /' | \
    sudo tee /etc/apt/sources.list.d/security:zeek.list
curl -fsSL https://download.opensuse.org/repositories/security:zeek/xUbuntu_22.04/Release.key | \
    gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/security_zeek.gpg > /dev/null
sudo apt-get update
sudo apt-get install -y zeek

# CentOS/RHEL
sudo yum install -y zeek

# macOS (Homebrew)
brew install zeek
```

#### From Source

```bash
git clone --recursive https://github.com/zeek/zeek
cd zeek
./configure --prefix=/usr/local/zeek
make -j$(nproc)
sudo make install

# Add Zeek to PATH
echo 'export PATH=/usr/local/zeek/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

#### Verify Zeek Installation

```bash
zeek --version
```

You should see output showing Zeek version 5.0 or later.

## Building the Plugin

### 1. Clone the Plugin Repository

```bash
git clone <repository-url> zeek-clickhouse-plugin
cd zeek-clickhouse-plugin
```

Or if you received the plugin as a source archive:

```bash
tar xzf zeek-clickhouse-plugin.tar.gz
cd zeek-clickhouse-plugin
```

### 2. Configure the Build

```bash
# Create a build directory
mkdir build && cd build

# Configure with CMake
cmake ..
```

#### Configuration Options

You can customize the build with various CMake options:

```bash
# Specify Zeek installation directory
cmake .. -DZEEK_ROOT_DIR=/usr/local/zeek

# Specify ClickHouse library location
cmake .. -DCLICKHOUSE_CPP_LIB=/usr/local/lib/libclickhouse-cpp-lib.so \
         -DCLICKHOUSE_CPP_INCLUDE=/usr/local/include

# Debug build
cmake .. -DCMAKE_BUILD_TYPE=Debug

# Custom installation prefix
cmake .. -DCMAKE_INSTALL_PREFIX=/opt/zeek-plugins
```

### 3. Build the Plugin

```bash
# Build using all available CPU cores
make -j$(nproc)
```

The build process typically takes 1-5 minutes depending on your system.

### 4. Verify the Build

After building, check that the plugin library was created:

```bash
ls -lh VNET_ClickHouse/lib/
```

You should see a file named `VNET_ClickHouse.so` (or `.dylib` on macOS).

## Installation

### System-Wide Installation

Install the plugin to the default Zeek plugin directory:

```bash
sudo make install
```

This installs the plugin to `/usr/local/zeek/lib/zeek/plugins/` (or your Zeek installation's plugin directory).

### User-Local Installation

If you don't have root access, install to a user directory:

```bash
# Set custom plugin directory
export ZEEK_PLUGIN_PATH=$HOME/.zeek/plugins

# Create directory if it doesn't exist
mkdir -p $ZEEK_PLUGIN_PATH

# Copy the plugin
cp -r VNET_ClickHouse $ZEEK_PLUGIN_PATH/

# Make the setting permanent
echo 'export ZEEK_PLUGIN_PATH=$HOME/.zeek/plugins' >> ~/.bashrc
source ~/.bashrc
```

### Docker Installation

For Docker deployments, add these lines to your Dockerfile:

```dockerfile
# Install ClickHouse C++ client
RUN git clone https://github.com/ClickHouse/clickhouse-cpp.git && \
    cd clickhouse-cpp && mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release && \
    make -j$(nproc) && make install && \
    ldconfig

# Install Zeek ClickHouse plugin
COPY zeek-clickhouse-plugin /opt/zeek-clickhouse-plugin
RUN cd /opt/zeek-clickhouse-plugin && \
    mkdir build && cd build && \
    cmake .. && make -j$(nproc) && make install
```

## Verification

### 1. Check Plugin Recognition

Verify that Zeek recognizes the plugin:

```bash
zeek -N VNET::ClickHouse
```

Expected output:

```
VNET::ClickHouse - ClickHouse input reader for Zeek Input Framework (dynamic, version 1.0.0)
    [Reader] ClickHouse (READER_CLICKHOUSE)
```

### 2. List All Plugins

See all installed plugins including the ClickHouse reader:

```bash
zeek -NN
```

Look for `VNET::ClickHouse` in the output.

### 3. Test with a Simple Script

Create a test script (`test-clickhouse.zeek`):

```zeek
@load VNET/ClickHouse

event zeek_init()
    {
    print "ClickHouse plugin loaded successfully!";
    print fmt("Reader available: %s", Input::READER_CLICKHOUSE);
    }
```

Run the test:

```bash
zeek test-clickhouse.zeek
```

Expected output:

```
ClickHouse plugin loaded successfully!
Reader available: Input::READER_CLICKHOUSE
```

### 4. Test Database Connection

Create a connection test script (`test-connection.zeek`):

```zeek
@load base/frameworks/input
@load VNET/ClickHouse

module TestConnection;

type TestRecord: record {
    value: count;
};

global test_table: table[count] of TestRecord = table();

event zeek_init()
    {
    local ch_info = ClickHouse::Info(
        $hostname = "localhost",
        $server_port = 9000,
        $database = "default",
        $query = "SELECT 1 as value"
    );

    Input::add_table([
        $name = "test",
        $source = "clickhouse://localhost",
        $reader = Input::READER_CLICKHOUSE,
        $mode = Input::REREAD,
        $destination = test_table,
        $idx = TestRecord,
        $val = TestRecord,
        $config = ClickHouse::config_to_table(ch_info)
    ]);
    }

event Input::end_of_data(name: string, source: string)
    {
    print "Connection successful!";
    print fmt("Retrieved %d rows", |test_table|);
    terminate();
    }
```

Run the connection test (requires running ClickHouse server):

```bash
zeek test-connection.zeek
```

## Troubleshooting

### Plugin Not Found

**Problem**: `zeek -N VNET::ClickHouse` shows no output or error.

**Solutions**:

1. Check plugin installation directory:
   ```bash
   ls -la $(zeek-config --plugin_dir)/
   ```

2. Verify `ZEEK_PLUGIN_PATH` environment variable:
   ```bash
   echo $ZEEK_PLUGIN_PATH
   ```

3. Manually specify plugin directory:
   ```bash
   zeek -N VNET::ClickHouse --plugin-dir=/path/to/plugins
   ```

### ClickHouse Library Not Found

**Problem**: Error during build or runtime: `cannot find -lclickhouse-cpp-lib`

**Solutions**:

1. Verify library installation:
   ```bash
   ldconfig -p | grep clickhouse
   ```

2. Add library path to `LD_LIBRARY_PATH`:
   ```bash
   export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
   echo 'export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH' >> ~/.bashrc
   ```

3. Update library cache:
   ```bash
   sudo ldconfig
   ```

4. Rebuild with explicit library path:
   ```bash
   cmake .. -DCLICKHOUSE_CPP_LIB=/usr/local/lib/libclickhouse-cpp-lib.so
   ```

### Connection Refused

**Problem**: "Failed to connect to ClickHouse: Connection refused"

**Solutions**:

1. Verify ClickHouse is running:
   ```bash
   ps aux | grep clickhouse
   # or
   sudo systemctl status clickhouse-server
   ```

2. Check port (native protocol uses 9000, not HTTP 8123):
   ```bash
   netstat -tlnp | grep 9000
   ```

3. Test connection with clickhouse-client:
   ```bash
   clickhouse-client --host localhost --port 9000
   ```

4. Check firewall rules:
   ```bash
   sudo iptables -L | grep 9000
   ```

### CMake Configuration Fails

**Problem**: CMake can't find Zeek or ClickHouse

**Solutions**:

1. Explicitly set paths:
   ```bash
   cmake .. \
       -DZEEK_ROOT_DIR=/usr/local/zeek \
       -DCLICKHOUSE_CPP_LIB=/usr/local/lib/libclickhouse-cpp-lib.so \
       -DCLICKHOUSE_CPP_INCLUDE=/usr/local/include
   ```

2. Check zeek-config availability:
   ```bash
   which zeek-config
   zeek-config --zeek_dist
   ```

3. Install zeek-devel package (if using package installation):
   ```bash
   sudo apt-get install zeek-dev
   # or
   sudo yum install zeek-devel
   ```

### Compilation Errors

**Problem**: C++ compilation errors during build

**Solutions**:

1. Ensure C++17 support:
   ```bash
   g++ --version  # Should be 8.0 or later
   ```

2. Update compiler:
   ```bash
   # Ubuntu/Debian
   sudo apt-get install g++-9
   export CXX=g++-9
   ```

3. Clean and rebuild:
   ```bash
   rm -rf build
   mkdir build && cd build
   cmake .. && make
   ```

### Runtime Symbol Errors

**Problem**: "undefined symbol" errors when loading plugin

**Solutions**:

1. Rebuild with matching Zeek version:
   ```bash
   zeek --version
   # Ensure plugin built against same version
   ```

2. Check ABI compatibility:
   ```bash
   ldd VNET_ClickHouse/lib/VNET_ClickHouse.so
   ```

3. Rebuild Zeek and plugin with same compiler/flags

## Platform-Specific Notes

### Ubuntu 22.04 / Debian 11

```bash
# Install all dependencies
sudo apt-get update
sudo apt-get install -y build-essential cmake git \
    libssl-dev zeek zeek-dev

# Follow standard build instructions
```

### CentOS 8 / RHEL 8

```bash
# Enable PowerTools repository
sudo dnf config-manager --set-enabled powertools

# Install dependencies
sudo dnf install -y gcc-c++ cmake git openssl-devel zeek

# Follow standard build instructions
```

### macOS

```bash
# Install dependencies via Homebrew
brew install cmake zeek openssl

# Set OpenSSL path for ClickHouse build
export OPENSSL_ROOT_DIR=$(brew --prefix openssl)

# Follow standard build instructions
```

### FreeBSD

```bash
# Install dependencies
sudo pkg install cmake git openssl zeek

# Follow standard build instructions
```

## Uninstallation

To remove the plugin:

```bash
# System-wide installation
sudo rm -rf $(zeek-config --plugin_dir)/VNET_ClickHouse

# User-local installation
rm -rf $ZEEK_PLUGIN_PATH/VNET_ClickHouse
```

## Next Steps

After successful installation:

1. Read the [README.md](README.md) for usage examples
2. Review the [examples/](examples/) directory for sample scripts
3. Configure your ClickHouse database and test queries
4. Start integrating ClickHouse data into your Zeek deployment

## Getting Help

If you encounter issues not covered here:

- Check the GitHub Issues page
- Visit the Zeek Community forum at https://community.zeek.org/
- Review Zeek plugin development documentation
- Verify ClickHouse C++ client documentation

## Additional Resources

- [Zeek Documentation](https://docs.zeek.org/)
- [Zeek Plugin Development](https://docs.zeek.org/en/master/devel/plugins.html)
- [ClickHouse Documentation](https://clickhouse.com/docs/)
- [ClickHouse C++ Client](https://github.com/ClickHouse/clickhouse-cpp)
