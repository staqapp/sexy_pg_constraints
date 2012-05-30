module SexyPgConstraints
  module SchemaDumper
    extend ActiveSupport::Concern

    included do
      alias_method_chain :table, :sexy_pg_constraints
    end

    module ClassMethods
      def dump_constraints(table_name, column_name, constraints)
        standard_constraints, constraints_with_irregular_names =
          constraints.partition do |constraint|
            constraint.name == make_constraint_title(table_name, column_name, constraint.constraint)
          end

        constraint_statements = []
        if standard_constraints.present?
          constraint_statements << %{add_constraint#{'s' if standard_constraints.many?} "#{table_name}", "#{column_name}", }.tap do |statement|
            statement << standard_constraints.map do |constraint|
              ":#{constraint.constraint} => #{constraint.argument.inspect}"
            end.join(', ')
          end
        end
        if constraints_with_irregular_names.present?
          constraint_statements += constraints_with_irregular_names.map do |constraint|
            %{add_constraint "#{table_name}", "#{column_name}", :#{constraint.constraint} => #{constraint.argument.inspect}, :name => "#{constraint.name}"}
          end
        end
        constraint_statements
      end

      def make_constraint_title(table_name, column_name, constraint)
        ConnectionAdapters::CheckConstraintDefinition.make_constraint_title(table_name, column_name, constraint)
      end
    end

    def table_with_sexy_pg_constraints(table_name, stream)
      table_without_sexy_pg_constraints(table_name, stream)
      table_constraints(table_name, stream)
    end

  private
    def table_constraints(table_name, stream)
      if (constraints = @connection.check_constraints(table_name)).any?
        constraints_by_column = constraints.group_by {|constraint| constraint.column_name }
        constrain_statements = constraints_by_column.flat_map do |column_name, constraints|
          self.class.dump_constraints(table_name, column_name, constraints).map do |constraint_statement|
            '  ' + constraint_statement
          end
        end

        stream.puts constrain_statements.sort.join("\n")
        stream.puts
      end
    end
  end
end
