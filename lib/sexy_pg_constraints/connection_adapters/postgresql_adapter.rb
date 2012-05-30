module SexyPgConstraints
  module ConnectionAdapters
    module PostgreSQLAdapter
      def constrain(*args)
        if block_given?
          yield SexyPgConstraints::Constrainer.new(args[0].to_s)
        else
          add_constraint(*args)
        end
      end

      def deconstrain(*args)
        if block_given?
          yield SexyPgConstraints::Deconstrainer.new(args[0])
        else
          drop_constraint(*args)
        end
      end

      def add_constraint(table, column, constraints)
        if name = constraints.delete(:name)
          raise 'Expected one constraint for #{name}' if constraints.size > 1
          type, options = constraints.first
          execute "alter table #{table} add constraint #{name} " \
              + SexyPgConstraints::Constraints.send(type, column, options) + ';'
        else
          constraints.each_pair do |type, options|
            execute "alter table #{table} add constraint #{CheckConstraintDefinition.make_constraint_title(table, column, type)} " \
              + SexyPgConstraints::Constraints.send(type, column, options) + ';'
          end
        end
      end

      def drop_constraint(table, column, *constraints)
        constraints.each do |type|
          execute "alter table #{table} drop constraint #{CheckConstraintDefinition.make_constraint_title(table, column, type)};"
        end
      end

      def check_constraints(table_name)
        constraint_info = select_all %{
          SELECT a.attname AS column, c.conname AS name, c.consrc AS expression
          FROM pg_constraint c
          JOIN pg_class t ON c.conrelid = t.oid
          JOIN pg_attribute a ON a.attnum = c.conkey[1] AND a.attrelid = t.oid
          JOIN pg_namespace ns ON c.connamespace = ns.oid
          WHERE c.contype = 'c'
            AND t.relname = '#{table_name}'
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
