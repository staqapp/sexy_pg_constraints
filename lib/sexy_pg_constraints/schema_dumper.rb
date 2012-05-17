module SexyPgConstraints
  module SchemaDumper
    extend ActiveSupport::Concern

    included do
      alias_method_chain :table, :sexy_pg_constraints
    end

    module ClassMethods
      def dump_constraint(constraint)
        %{add_constraint "#{constraint.table_name}", :check => "#{constraint.expression}", :name => "#{constraint.name}"}
      end
    end

    def table_with_sexy_pg_constraints(table_name, stream)
      table_without_sexy_pg_constraints(table_name, stream)
      table_constraints(table_name, stream)
    end

  private
    def table_constraints(table_name, stream)
      if (constraints = @connection.check_constraints(table_name)).any?
        constrain_statements = constraints.map do |constraint|
          '  ' + self.class.dump_constraint(constraint)
        end

        stream.puts constrain_statements.sort.join("\n")
        stream.puts
      end
    end
  end
end
