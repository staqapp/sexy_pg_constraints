module SexyPgConstraints
  class Railtie < Rails::Railtie
    initializer 'sexy_pg_constraints.load_adapter' do
      ActiveSupport.on_load :active_record do
        ActiveRecord::ConnectionAdapters.module_eval do
          include SexyPgConstraints::ConnectionAdapters::SchemaDefinitions
          include SexyPgConstraints::ConnectionAdapters::SchemaStatements
        end
        ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.class_eval do
          include SexyPgConstraints::ConnectionAdapters::PostgreSQLAdapter
        end

        ActiveRecord::SchemaDumper.class_eval do
          include SexyPgConstraints::SchemaDumper
        end
      end
    end
  end
end
