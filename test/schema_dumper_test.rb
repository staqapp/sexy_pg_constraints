require 'test_helper'

class SexyPgConstraints::SchemaDumperTest < ActiveSupport::TestCase

  class MockConnection
    def tables
      [ 'foo', 'bar' ]
    end

    def constraints(table_name)
      []
    end
  end

  class MockSchemaDumper
    def initialize
      @connection = MockConnection.new
    end

    def table(table_name, stream)
    end

    include SexyPgConstraints::SchemaDumper
  end

  test 'name excluded when standard' do
    assert_dump %{add_constraint "foos", "city", :present => true},
      SexyPgConstraints::ConnectionAdapters::CheckConstraintDefinition.new('foos', 'city', 'foos_city_present', "(length(btrim((city)::text)) > 0)")
  end

  test 'name included when unusual' do
    assert_dump %{add_constraint "foos", "city", :stripped => true, :name => "crazy_name"},
      SexyPgConstraints::ConnectionAdapters::CheckConstraintDefinition.new('foos', 'city', 'crazy_name', "(length((city)::text) = length(btrim((city)::text)))")
  end

  test 'dump check constraint' do
    assert_dump %{add_constraint "foos", "city", :stripped => "Hello"},
      SexyPgConstraints::ConnectionAdapters::CheckConstraintDefinition.new('foos', 'city', 'foos_city_stripped', "(length((city)::text) = length(btrim((city)::text, E'Hello')))")
    assert_dump %{add_constraint "foos", "city", :greater_than => 1},
      SexyPgConstraints::ConnectionAdapters::CheckConstraintDefinition.new('foos', 'city', 'foos_city_greater_than', "(city > 1)")
  end

private
  def assert_dump(expected, definition)
    assert_equal [expected], MockSchemaDumper.dump_constraints(definition.table_name, definition.column_name, [definition])
  end
end
