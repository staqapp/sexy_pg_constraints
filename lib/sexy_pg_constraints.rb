module SexyPgConstraints
  extend ActiveSupport::Autoload
  autoload :SchemaDefinitions
  autoload :Constrainer
  autoload :Deconstrainer
  autoload :Constraints
  autoload :Helpers
end

require 'sexy_pg_constraints/initializer'
