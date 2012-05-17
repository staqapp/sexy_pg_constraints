module SexyPgConstraints
  class Railtie < Rails::Railtie
    initializer 'sexy_pg_constraints.load_adapter' do
      ActiveSupport.on_load :active_record do
        ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.class_eval do
          include SexyPgConstraints::SchemaDefinitions
          include SexyPgConstraints::ConnectionAdapters::PostgreSQLAdapter
        end

        ActiveRecord::SchemaDumper.class_eval do
          include SexyPgConstraints::SchemaDumper
        end
      end
    end
  end
end
