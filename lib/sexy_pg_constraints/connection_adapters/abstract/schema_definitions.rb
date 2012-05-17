module SexyPgConstraints
  module ConnectionAdapters
    module SchemaDefinitions
      def self.included(base)
        base::Table.class_eval do
          include SexyPgConstraints::ConnectionAdapters::Table
        end
      end
    end

    module Table
      extend ActiveSupport::Concern

      def constrain(column, constraints)
        @base.add_constraint @table_name, column, constraints
      end

      def deconstrain(column, *constraints)
        @base.drop_constraint @table_name, column, *constraints
      end
    end
  end
end
