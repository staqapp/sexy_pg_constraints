module SexyPgConstraints
  module Helpers
    def make_title(table, column, type)
      column = column.join('_') if column.respond_to?(:join)

      "#{table}_#{column}_#{type}"
    end

    def execute(*args)
      ActiveRecord::Base.connection.execute(*args)
    end
  end
end