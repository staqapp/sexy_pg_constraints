module SexyPgConstraints
  module ConnectionAdapters
    module PostgreSQLAdapter
      def check_constraints(table_name)
        constraint_info = select_all %{
          SELECT a.attname AS column, c.conname AS name, c.consrc AS expression
          FROM pg_constraint c
          JOIN pg_class t ON c.conrelid = t.oid
          JOIN pg_attribute a ON a.attnum = c.conkey[1] AND a.attrelid = t.oid
          JOIN pg_namespace ns ON c.connamespace = ns.oid
          WHERE c.contype = 'c'
            AND t.relname = 'catalog_items'
            AND ns.nspname = ANY (current_schemas(false))
          ORDER BY c.conname
        }
        constraint_info.map do |row|
          CheckConstraintDefinition.new(table_name, row['column'], row['name'], row['expression'])
        end
      end
    end
  end
end
