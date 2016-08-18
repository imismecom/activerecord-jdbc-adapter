ArJdbc.load_java_part :H2
require 'arjdbc/hsqldb/adapter'

module ArJdbc
  module H2
    include HSQLDB

    JdbcConnection = ::ActiveRecord::ConnectionAdapters::H2JdbcConnection

    # @see ActiveRecord::ConnectionAdapters::JdbcAdapter#jdbc_connection_class
    def self.jdbc_connection_class; JdbcConnection end

    # @see ActiveRecord::ConnectionAdapters::JdbcColumn#column_types
    def self.column_selector
      [ /\.h2\./i, lambda { |config, column| column.extend(ColumnMethods) } ]
    end

    # @since 1.4.0
    # @private Internal - mostly due {#column_selector}.
    # @see ActiveRecord::ConnectionAdapters::JdbcColumn
    module ColumnMethods

      private

      def extract_limit(sql_type)
        limit = super
        case @sql_type = sql_type.downcase
        # NOTE: JDBC driver f*cks sql_type up with limits (just like HSQLDB) :
        when /^tinyint/i       then @sql_type = 'tinyint'; limit = 1
        when /^smallint|int2/i then @sql_type = 'smallint'; limit = 2
        when /^bigint|int8/i   then @sql_type = 'bigint'; limit = 8
        when /^int|int4/i      then @sql_type = 'int'; limit = 4
        when /^double/i        then @sql_type = 'double'; limit = 8
        when /^real/i          then @sql_type = 'real'; limit = 4
        when /^date/i          then @sql_type = 'date'; limit = nil
        when /^timestamp/i     then @sql_type = 'timestamp'; limit = nil
        when /^time/i          then @sql_type = 'time'; limit = nil
        when /^boolean/i       then @sql_type = 'boolean'; limit = nil
        when /^binary|bytea/i; then @sql_type = 'binary'; limit = 2 * 1024 * 1024
        when /blob|image|oid/i then @sql_type = 'blob'; limit = nil
        when /clob|text/i      then @sql_type = 'clob'; limit = nil
        # NOTE: use lower-case due SchemaDumper not handling it's decimal/integer
        # optimization case-insensitively due : column.type == :integer &&
        # [/^numeric/, /^decimal/].any? { |e| e.match(column.sql_type) }
        when /^decimal\(65535,32767\)/i
          @sql_type = 'decimal'; nil
        end
        limit
      end

      def simplified_type(field_type)
        case field_type
        when /^bit|bool/i         then :boolean
        when /^signed|year/i      then :integer
        when /^real|double/i      then :float
        when /^varchar/i          then :string
        when /^longvarchar/i      then :text
        when /^binary|raw|bytea/i then :binary
        when /varbinary/i         then :binary # longvarbinary, varbinary
        when /^blob|image|oid/i   then :binary
        else
          super
        end
      end

      # Post process default value from JDBC into a Rails-friendly format (columns{-internal})
      def default_value(value)
        # H2 auto-generated key default value
        return nil if value =~ /^\(NEXT VALUE FOR/i
        # JDBC returns column default strings with actual single quotes around the value.
        return $1 if value =~ /^'(.*)'$/
        value
      end

    end

    # H2's (JDBC) column class
    # @since 1.4.0
    class Column < ::ActiveRecord::ConnectionAdapters::JdbcColumn
      include ColumnMethods
    end

    # @see ActiveRecord::ConnectionAdapters::Jdbc::ArelSupport
    def self.arel_visitor_type(config = nil)
      require 'arel/visitors/h2'; ::Arel::Visitors::H2
    end

    ADAPTER_NAME = 'H2'.freeze

    # @override
    def adapter_name
      ADAPTER_NAME
    end

    NATIVE_DATABASE_TYPES = {
      # "integer GENERATED BY DEFAULT AS IDENTITY(START WITH 0) PRIMARY KEY"
      :primary_key => "bigint identity",
      :boolean     => { :name => "boolean" },
      :tinyint     => { :name => "tinyint", :limit => 1 },
      :smallint    => { :name => "smallint", :limit => 2 },
      :bigint      => { :name => "bigint", :limit => 8 },
      :integer     => { :name => "int", :limit => 4 },
      :decimal     => { :name => "decimal" }, # :limit => 2147483647
      :numeric     => { :name => "numeric" }, # :limit => 2147483647
      :float       => { :name => "float", :limit => 8 },
      :double      => { :name => "double", :limit => 8 },
      :real        => { :name => "real", :limit => 4 }, # :limit => 8
      :date        => { :name => "date" },
      :time        => { :name => "time" },
      :timestamp   => { :name => "timestamp" },
      :datetime    => { :name => "timestamp" },
      :binary      => { :name => "binary" },
      :string      => { :name => "varchar", :limit => 255 },
      :char        => { :name => "char" }, # :limit => 2147483647
      :blob        => { :name => "blob" },
      :text        => { :name => "clob" },
      :clob        => { :name => "clob" },
      :uuid        => { :name => "uuid" }, # :limit => 2147483647
      :other       => { :name => "other" }, # java.lang.Object
      :array       => { :name => "array" }, # java.lang.Object[]
      # NOTE: would be great if AR allowed as to refactor as :
      #   t.column :string, :ignorecase => true
      :varchar_casesensitive => { :name => 'varchar_casesensitive' },
      :varchar_ignorecase => { :name => 'varchar_ignorecase' },
      # :identity : { :name=>"identity", :limit => 19 }
      # :result_set : { :name=>"result_set" }
    }

    # @override
    def native_database_types
      NATIVE_DATABASE_TYPES
    end

    # @override
    def type_to_sql(type, limit = nil, precision = nil, scale = nil)
      case type.to_sym
      when :integer
        case limit
        when 1; 'tinyint'
        when 2; 'smallint'
        when nil, 3, 4; 'int'
        when 5..8; 'bigint'
        else raise(ActiveRecordError, "No integer type has byte size #{limit}")
        end
      when :float
        case limit
        when 1..4; 'real'
        when 5..8; 'double'
        else raise(ActiveRecordError, "No float type has byte size #{limit}")
        end
      when :binary
        if limit && limit < 2 * 1024 * 1024
          'binary'
        else
          'blob'
        end
      else
        super
      end
    end

    # @override
    def empty_insert_statement_value
      "VALUES ()"
    end

    # @override
    def tables(schema = current_schema)
      @connection.tables(nil, schema)
    end

    # @override
    def columns(table_name, name = nil)
      schema, table = extract_schema_and_table(table_name.to_s)
      schema = current_schema if schema.nil?
      @connection.columns_internal(table, nil, schema || '')
    end

    # @override
    def change_column(table_name, column_name, type, options = {})
      execute "ALTER TABLE #{table_name} ALTER COLUMN #{column_name} #{type_to_sql(type, options[:limit])}"
      change_column_default(table_name, column_name, options[:default]) if options_include_default?(options)
      change_column_null(table_name, column_name, options[:null], options[:default]) if options.key?(:null)
    end

    # @return [String] the current schema name
    def current_schema
      @current_schema ||= execute('CALL SCHEMA()', 'SCHEMA')[0].values[0] # PUBLIC (default)
    end

    # Change the (current) schema to be used for this connection.
    def set_schema(schema = 'PUBLIC')
      @current_schema = nil
      execute "SET SCHEMA #{schema}", 'SCHEMA'
    end
    alias_method :current_schema=, :set_schema

    def create_schema(schema)
      execute "CREATE SCHEMA #{schema}", 'SCHEMA'
    end

    def drop_schema(schema)
      @current_schema = nil if current_schema == schema
      execute "DROP SCHEMA #{schema}", 'SCHEMA'
    end

    def configure_connection
      # NOTE: just to support the config[:schema] setting
      # it's likely better to append this to the JDBC URL :
      # jdbc:h2:test;SCHEMA=MY_SCHEMA
      if schema = config[:schema]
        set_schema(schema) # if schema.uppercase != 'PUBLIC'
      end
    end

    # @override
    def quote(value, column = nil)
      case value
      when String
        if value.empty?
          "''"
        else
          super
        end
      else
        super
      end
    end

    # @override
    def supports_views?; true end

    # EXPLAIN support :

    # @override
    def supports_explain?; true end

    # @override
    def explain(arel, binds = [])
      sql = "EXPLAIN #{to_sql(arel, binds)}"
      raw_result = exec_query_raw(sql, "EXPLAIN", binds)
      raw_result[0].values.join("\n") # [ "SELECT \n ..." ].to_s
    end

    # @override
    def structure_dump
      execute('SCRIPT SIMPLE').map do |result|
        # [ { 'script' => SQL }, { 'script' ... }, ... ]
        case sql = result.first[1] # ['script']
        when /CREATE USER IF NOT EXISTS SA/i then nil
        else sql
        end
      end.compact.join("\n\n")
    end

    # @see #structure_dump
    def structure_load(dump)
      dump.each_line("\n\n") { |ddl| execute(ddl) }
    end

    def shutdown
      execute 'SHUTDOWN COMPACT'
    end

    # @private
    def recreate_database(name = nil, options = {})
      drop_database(name)
      create_database(name, options)
    end

    # @private
    def create_database(name = nil, options = {}); end

    # @private
    def drop_database(name = nil)
      execute('DROP ALL OBJECTS')
    end

    # @private
    def database_path(base_only = false)
      db_path = jdbc_connection(true).getSession.getDataHandler.getDatabasePath
      return db_path if base_only
      if File.exist?(mv_path = "#{db_path}.mv.db")
        return mv_path
      else
        "#{db_path}.h2.db"
      end
    end

    # @override
    def jdbc_connection(unwrap = nil)
      java_connection = raw_connection.connection
      return java_connection unless unwrap
      if java_connection.java_class.name == 'org.h2.jdbc.JdbcConnection'
        return java_connection
      end
      connection_class = java.sql.Connection.java_class
      if java_connection.wrapper_for?(connection_class)
        java_connection.unwrap(connection_class) # java.sql.Wrapper.unwrap
      elsif java_connection.respond_to?(:connection)
        # e.g. org.apache.tomcat.jdbc.pool.PooledConnection
        java_connection.connection # getConnection
      else
        java_connection
      end
    end

    private

    def change_column_null(table_name, column_name, null, default = nil)
      if !null && !default.nil?
        execute("UPDATE #{table_name} SET #{column_name}=#{quote(default)} WHERE #{column_name} IS NULL")
      end
      if null
        execute "ALTER TABLE #{table_name} ALTER COLUMN #{column_name} SET NULL"
      else
        execute "ALTER TABLE #{table_name} ALTER COLUMN #{column_name} SET NOT NULL"
      end
    end

    def extract_schema_and_table(name)
      result = name.scan(/[^".\s]+|"[^"]*"/)[0, 2]
      result.each { |m| m.gsub!(/(^"|"$)/, '') }
      result.unshift(nil) if result.size == 1 # schema == nil
      result # [schema, table]
    end

  end
end

module ActiveRecord::ConnectionAdapters
  class H2Adapter < JdbcAdapter
    include ::ArJdbc::H2
  end
  # @private
  H2Column = ::ArJdbc::H2::Column
end
