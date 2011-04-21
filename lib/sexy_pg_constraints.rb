require 'sexy_pg_constraints/initializer'
require "sexy_pg_constraints/helpers"
require "sexy_pg_constraints/constrainer"
require "sexy_pg_constraints/deconstrainer"
require "sexy_pg_constraints/constraints"

module SexyPgConstraints
  def constrain(*args)
    if block_given?
      yield SexyPgConstraints::Constrainer.new(args[0].to_s)
    else
      SexyPgConstraints::Constrainer::add_constraints(*args)
    end
  end

  def deconstrain(*args)
    if block_given?
      yield SexyPgConstraints::DeConstrainer.new(args[0])
    else
      SexyPgConstraints::DeConstrainer::drop_constraints(*args)
    end
  end
end
