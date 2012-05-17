module SexyPgConstraints
  extend ActiveSupport::Autoload
  autoload :SchemaDefinitions
  autoload :SchemaDumper
  autoload :Constraints

  module ConnectionAdapters
    extend ActiveSupport::Autoload
    autoload :CheckConstraintDefinition
    autoload :PostgreSQLAdapter, 'sexy_pg_constraints/connection_adapters/postgresql_adapter'
  end
end

require 'sexy_pg_constraints/railtie' if defined?(Rails)
