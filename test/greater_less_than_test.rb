require 'test_helper'

class GreaterLessThanTest < SexyPgConstraintsTest
  def test_greater_than
    ActiveRecord::Migration.constrain :books, :quantity, :greater_than => 5

    assert_prohibits Book, :quantity, :greater_than do |book|
      book.quantity = 5
    end

    assert_allows Book do |book|
      book.quantity = 6
    end

    ActiveRecord::Migration.deconstrain :books, :quantity, :greater_than

    assert_allows Book do |book|
      book.quantity = 5
    end
  end

  def test_less_than
    ActiveRecord::Migration.constrain :books, :quantity, :less_than => 5

    assert_prohibits Book, :quantity, :less_than do |book|
      book.quantity = 5
    end

    assert_allows Book do |book|
      book.quantity = 4
    end

    ActiveRecord::Migration.deconstrain :books, :quantity, :less_than

    assert_allows Book do |book|
      book.quantity = 5
    end
  end

  def test_greater_than_or_equal_to
    ActiveRecord::Migration.constrain :books, :quantity, :greater_than_or_equal_to => 5

    assert_prohibits Book, :quantity, :greater_than_or_equal_to do |book|
      book.quantity = 4
    end

    assert_allows Book do |book|
      book.quantity = 5
    end

    assert_allows Book do |book|
      book.quantity = 6
    end

    ActiveRecord::Migration.deconstrain :books, :quantity, :greater_than_or_equal_to

    assert_allows Book do |book|
      book.quantity = 4
    end
  end

  def test_less_than_or_equal_to
    ActiveRecord::Migration.constrain :books, :quantity, :less_than_or_equal_to => 5

    assert_prohibits Book, :quantity, :less_than_or_equal_to do |book|
      book.quantity = 6
    end

    assert_allows Book do |book|
      book.quantity = 5
    end

    assert_allows Book do |book|
      book.quantity = 4
    end

    ActiveRecord::Migration.deconstrain :books, :quantity, :less_than_or_equal_to

    assert_allows Book do |book|
      book.quantity = 6
    end
  end
end
