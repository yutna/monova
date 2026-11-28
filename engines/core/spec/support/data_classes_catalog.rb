# frozen_string_literal: true

require "yaml"

# DATA-11, ARCH-07: every column of every engine's tables has a data class
# in the engine's db/data_classes.yml. The check reads the columns from
# PostgreSQL's catalog, so a column that a migration created but the file
# does not classify fails, and so does a listed table or column that no
# longer exists. A table belongs to the engine whose name prefixes it.
class DataClassesCatalog
  RULE_ID = "DATA-11"
  CLASSES = %w[public internal personal sensitive secret].freeze
  # Rails' own tables are not engine tables (DATA-03, ARCH-07).
  RAILS_TABLES = %w[ar_internal_metadata schema_migrations].freeze

  # Raised when the check found no table, so an empty input fails.
  class EmptyCatalog < StandardError; end

  # Raised with a DATA-11 message when at least one column breaks the rule.
  class Violation < StandardError; end

  attr_reader :connection, :root, :schema

  def initialize(connection, root: Rails.root, schema: "public", definitions: nil)
    @connection = connection
    @root = Pathname(root)
    @schema = schema
    @definitions = definitions
  end

  # Returns one message per column or table that breaks DATA-11 and raises
  # when the schema holds no table at all.
  def violations
    tables = catalog_columns
    raise EmptyCatalog, "#{RULE_ID}: found no table in schema #{schema.inspect}" if tables.empty?

    prefix_violations +
      unclaimed_violations(tables) +
      class_violations(tables) +
      listed_violations(tables)
  end

  # Raises a Violation whose message names DATA-11, so a spec failure
  # reports the rule the catalog broke.
  def check!
    found = violations
    return if found.empty?

    raise Violation, "#{RULE_ID}: #{found.join("; ")}"
  end

  private

  # The table and column names the database holds, in catalog order, keyed
  # by table. pg_attribute is used instead of information_schema.columns so
  # the check still sees a column the runtime role cannot read.
  def catalog_columns
    connection.select_all(<<~SQL).to_a
      SELECT table_class.relname AS table_name,
             attribute.attname AS column_name
      FROM pg_attribute attribute
      JOIN pg_class table_class ON table_class.oid = attribute.attrelid
      JOIN pg_namespace table_namespace ON table_namespace.oid = table_class.relnamespace
      WHERE table_namespace.nspname = #{connection.quote(schema)}
        AND table_class.relkind IN ('r', 'p')
        AND attribute.attnum > 0
        AND NOT attribute.attisdropped
      ORDER BY table_class.relname, attribute.attnum
    SQL
      .group_by { |row| row["table_name"] }
      .transform_values { |rows| rows.map { |row| row["column_name"] } }
  end

  # Every engine file names only tables that its engine owns (ARCH-07).
  def prefix_violations
    definitions.flat_map do |engine, tables|
      tables.keys.reject { |table| table.start_with?("#{engine}_") }.map do |table|
        "#{data_classes_path(engine)} lists #{table}, which the #{engine} engine does not own"
      end
    end
  end

  # Every table in the schema belongs to an engine, or to Rails.
  def unclaimed_violations(tables)
    tables.keys.filter_map do |table|
      next if RAILS_TABLES.include?(table) || engine_for(table)

      "#{schema}.#{table} is not claimed by any engine"
    end
  end

  # Every column of an engine table has one of the five classes.
  def class_violations(tables)
    tables.flat_map do |table, columns|
      engine = engine_for(table)
      next [] if RAILS_TABLES.include?(table) || engine.nil?

      listed = definitions.dig(engine, table) || {}
      columns.filter_map { |column| class_violation(engine, table, column, listed) }
    end
  end

  def class_violation(engine, table, column, listed)
    unless listed.key?(column) && !listed[column].nil?
      return "#{schema}.#{table}.#{column} has no data class in #{data_classes_path(engine)}"
    end

    data_class = listed[column]
    return if CLASSES.include?(data_class)

    "#{schema}.#{table}.#{column} has class #{data_class.inspect}, not one of #{CLASSES.join(", ")}"
  end

  # Every listed table and column must still exist, and a listed table must
  # belong to the engine whose file lists it.
  def listed_violations(tables)
    definitions.flat_map do |engine, listed_tables|
      listed_tables.flat_map do |table, columns|
        next [] unless engine_for(table) == engine

        missing = missing_table_or_columns(tables, engine, table, columns || {})
        missing
      end
    end
  end

  def missing_table_or_columns(tables, engine, table, columns)
    unless tables.key?(table)
      return [ "#{schema}.#{table} is listed in #{data_classes_path(engine)} but does not exist" ]
    end

    columns.keys.reject { |column| tables[table].include?(column) }.map do |column|
      "#{schema}.#{table}.#{column} is listed in #{data_classes_path(engine)} but does not exist"
    end
  end

  # The engine whose name prefixes the table, longest name first so an
  # engine such as billing_report wins over billing (ARCH-07).
  def engine_for(table)
    engines.select { |engine| table.start_with?("#{engine}_") }.max_by(&:length)
  end

  def engines
    @engines ||= root.glob("engines/*").select(&:directory?).map { |directory| directory.basename.to_s }.sort
  end

  def definitions
    @definitions ||= load_definitions
  end

  def load_definitions
    root.glob("engines/*/db/data_classes.yml").sort.to_h do |path|
      engine = path.dirname.dirname.basename.to_s
      [ engine, YAML.safe_load_file(path) || {} ]
    end
  end

  def data_classes_path(engine)
    "engines/#{engine}/db/data_classes.yml"
  end
end
