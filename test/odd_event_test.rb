require 'test_helper'

class OddEventTest < SexyPgConstraintsTest
  def test_odd
    ActiveRecord::Migration.constrain :books, :quantity, :odd => true

    assert_prohibits Book, :quantity, :odd do |book|
      book.quantity = 2
    end

    assert_allows Book do |book|
      book.quantity = 1
    end

    ActiveRecord::Migration.deconstrain :books, :quantity, :odd

    assert_allows Book do |book|
      book.quantity = 2
    end
  end

  def test_odd_on_a_column_whose_name_is_a_sql_keyword
    ActiveRecord::Migration.constrain :books, :from, :odd => true

    assert_prohibits Book, :from, :odd do |book|
      book.from = 2
    end

    assert_allows Book do |book|
      book.from = 1
    end

    ActiveRecord::Migration.deconstrain :books, :from, :odd

    assert_allows Book do |book|
      book.from = 2
    end
  end

  def test_even
    ActiveRecord::Migration.constrain :books, :quantity, :even => true

    assert_prohibits Book, :quantity, :even do |book|
      book.quantity = 1
    end

    assert_allows Book do |book|
      book.quantity = 2
    end

    ActiveRecord::Migration.deconstrain :books, :quantity, :even

    assert_allows Book do |book|
      book.quantity = 1
    end
  end

  def test_even_on_a_column_whose_name_is_a_sql_keyword
    ActiveRecord::Migration.constrain :books, :from, :even => true

    assert_prohibits Book, :from, :even do |book|
      book.from = 1
    end

    assert_allows Book do |book|
      book.from = 2
    end

    ActiveRecord::Migration.deconstrain :books, :from, :even

    assert_allows Book do |book|
      book.from = 1
    end
  end
end
