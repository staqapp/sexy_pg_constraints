module SexyPgConstraints
  extend ActiveSupport::Autoload
  autoload :SchemaDefinitions
  autoload :SchemaDumper
  autoload :Constraints
end

require 'sexy_pg_constraints/railtie' if defined?(Rails)
