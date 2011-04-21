if defined?(Rails)
  module SexyPgConstraints
    class Railtie < Rails::Railtie
      config.after_initialize do
        ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.send(:include, SexyPgConstraints::SchemaDefinitions)
      end
    end
  end
else
  ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.send(:include, SexyPgConstraints::SchemaDefinitions)
end
