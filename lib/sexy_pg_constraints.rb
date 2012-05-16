module SexyPgConstraints
  extend ActiveSupport::Autoload
  autoload :SchemaDefinitions
  autoload :Constraints

  autoload_under 'constrainers' do
    autoload :Constrainer
    autoload :Deconstrainer
    autoload :Helpers
  end
end

require 'sexy_pg_constraints/railtie' if defined?(Rails)
