module SexyPgConstraints
  extend ActiveSupport::Autoload
  autoload :SchemaDefinitions
  autoload :SchemaDumper
  autoload :Constraints

  autoload_under 'constrainers' do
    autoload :Constrainer
    autoload :Deconstrainer
  end

  module ConnectionAdapters
    extend ActiveSupport::Autoload
    autoload :PostgreSQLAdapter, 'sexy_pg_constraints/connection_adapters/postgresql_adapter'

    autoload_under 'abstract' do
      autoload :CheckConstraintDefinition
      autoload :SchemaDefinitions
      autoload :SchemaStatements
    end
  end
end

require 'sexy_pg_constraints/railtie' if defined?(Rails)
