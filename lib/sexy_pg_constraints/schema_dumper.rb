module SexyPgConstraints
  module SchemaDumper
    extend ActiveSupport::Concern

    included do
      alias_method_chain :table, :sexy_pg_constraints
    end

    module ClassMethods
      def dump_constraint(table, constraint)
        column_names = table.columns.map {|column| column.name }
        match = constraint.match(/^CONSTRAINT #{table.name}_(#{column_names.join('|')})_(a-z_) CHECK /)

        "constrain :#{table.name}, :#{match[1]}, #{match[2]} => true"
      end
    end

    def table_with_sexy_pg_constraints(table_name, stream)
      table_without_sexy_pg_constraints(table_name, stream)
      table_constraints(table_name, stream)
    end

    private
      def table_constraints(table_name, stream)
        if (constraints = @connection.constraints(table_name)).any?
          constrain_statements = constraints.map do |constraint|
            '  ' + self.class.dump_constraint(table_name, constraint)
          end

          stream.puts constrain_statements.sort.join("\n")
          stream.puts
        end
      end
  end
end
