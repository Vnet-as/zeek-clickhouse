##! ClickHouse input reader support for Zeek.
##!
##! This module provides helper functions and types for using the
##! ClickHouse input reader with Zeek's Input Framework.

module ClickHouse;

export {
	## Configuration record for ClickHouse input reader connections.
	## This record is used to specify connection parameters and query details.
	type Info: record {
		## ClickHouse server hostname or IP address
		hostname: string &default="localhost";
		## ClickHouse native protocol port (default 9000, not the HTTP port 8123)
		server_port: count &default=9000;
		## Database name to connect to
		database: string &default="default";
		## Username for authentication
		user: string &default="default";
		## Password for authentication
		password: string &default="";
		## SQL query to execute
		query: string;
		## Polling interval for continuous updates (0sec = one-shot mode)
		poll_interval: interval &default=0sec;
	};

	## Convert a ClickHouse::Info record to a configuration table
	## suitable for use with Input::add_table() or Input::add_event().
	##
	## info: The ClickHouse configuration information
	##
	## Returns: A table mapping configuration keys to string values
	global config_to_table: function(info: Info): table[string] of string;

	## Helper function to create an Input::TableDescription for reading
	## from ClickHouse into a Zeek table.
	##
	## name: Unique name for this input stream
	## info: ClickHouse connection and query configuration
	## destination: The Zeek table to populate with results
	## idx: Record type describing the table's index
	## val: Record type describing the table's value
	## ev: Optional event to raise for each row (default: none)
	## want_record: Whether to pass full records to the event (default: true)
	##
	## Returns: An Input::TableDescription ready for Input::add_table()
	global table_description: function(name: string, info: Info,
	                                   destination: any,
	                                   idx: any, val: any,
	                                   ev: any &default=Input::EVENT_NEW,
	                                   want_record: bool &default=T): Input::TableDescription;

	## Helper function to create an Input::EventDescription for reading
	## streaming data from ClickHouse.
	##
	## name: Unique name for this input stream
	## info: ClickHouse connection and query configuration (should have poll_interval > 0sec)
	## fields: Record type describing the event fields
	## ev: Event to raise for each row
	## want_record: Whether to pass full records to the event (default: true)
	##
	## Returns: An Input::EventDescription ready for Input::add_event()
	global event_description: function(name: string, info: Info,
	                                   fields: any, ev: any,
	                                   want_record: bool &default=T): Input::EventDescription;
}

function config_to_table(info: Info): table[string] of string
	{
	local config: table[string] of string = table();

	config["hostname"]     = info$hostname;
	config["server_port"]  = cat(info$server_port);
	config["database"]     = info$database;
	config["user"]         = info$user;
	config["password"]     = info$password;
	config["query"]        = info$query;
	config["poll_interval"] = cat(interval_to_double(info$poll_interval));

	return config;
	}

function table_description(name: string, info: Info,
                           destination: any,
                           idx: any, val: any,
                           ev: any,
                           want_record: bool): Input::TableDescription
	{
	local config = config_to_table(info);

	return Input::TableDescription(
		$name        = name,
		$source      = cat("clickhouse://", info$hostname, ":", info$server_port,
		                   "/", info$database),
		$reader      = Input::READER_CLICKHOUSE,
		$mode        = Input::REREAD,
		$destination = destination,
		$idx         = idx,
		$val         = val,
		$ev          = ev,
		$want_record = want_record,
		$config      = config
	);
	}

function event_description(name: string, info: Info,
                           fields: any, ev: any,
                           want_record: bool): Input::EventDescription
	{
	local config = config_to_table(info);

	return Input::EventDescription(
		$name        = name,
		$source      = cat("clickhouse://", info$hostname, ":", info$server_port,
		                   "/", info$database),
		$reader      = Input::READER_CLICKHOUSE,
		$fields      = fields,
		$ev          = ev,
		$want_record = want_record,
		$config      = config
	);
	}
