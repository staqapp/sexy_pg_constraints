require 'test_helper'

class PositiveTest < SexyPgConstraintsTest
  def test_positive
    ActiveRecord::Migration.constrain :books, :quantity, :positive => true

    assert_prohibits Book, :quantity, :positive do |book|
      book.quantity = -1
    end

    assert_allows Book do |book|
      book.quantity = 0
    end

    assert_allows Book do |book|
      book.quantity = 1
    end

    ActiveRecord::Migration.deconstrain :books, :quantity, :positive

    assert_allows Book do |book|
      book.quantity = -1
    end
  end

  def test_positive_on_a_column_whose_name_is_a_sql_keyword
    ActiveRecord::Migration.constrain :books, :from, :positive => true

    assert_prohibits Book, :from, :positive do |book|
      book.from = -1
    end

    assert_allows Book do |book|
      book.from = 0
    end

    assert_allows Book do |book|
      book.from = 1
    end

    ActiveRecord::Migration.deconstrain :books, :from, :positive

    assert_allows Book do |book|
      book.from = -1
    end
  end
end
