module SexyPgConstraints
  module SchemaDefinitions
    def constrain(*args)
      if block_given?
        yield SexyPgConstraints::Constrainer.new(args[0].to_s)
      else
        SexyPgConstraints::Constrainer::add_constraints(*args)
      end
    end

    def deconstrain(*args)
      if block_given?
        yield SexyPgConstraints::Deconstrainer.new(args[0])
      else
        SexyPgConstraints::Deconstrainer::drop_constraints(*args)
      end
    end
  end
end
