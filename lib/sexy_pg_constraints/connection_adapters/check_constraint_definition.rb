module SexyPgConstraints
  module ConnectionAdapters
    CheckConstraintDefinition = Struct.new(:table_name, :column_name, :name, :expression) #:nodoc:
  end
end
