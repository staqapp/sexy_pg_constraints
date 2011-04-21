module SexyPgConstraints
  class Railtie < Rails::Railtie
    initializer 'sexy_pg_constraints.load_adapter' do
      ActiveSupport.on_load :active_record do
        ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.send(:include, SexyPgConstraints::SchemaDefinitions)
      end
    end
  end
end
