require 'test_helper'

class WithinTest < SexyPgConstraintsTest
  def test_within_inclusive
    ActiveRecord::Migration.constrain :books, :quantity, :within => 5..11

    assert_prohibits Book, :quantity, :within do |book|
      book.quantity = 12
    end

    assert_prohibits Book, :quantity, :within do |book|
      book.quantity = 4
    end

    assert_allows Book do |book|
      book.quantity = 7
    end

    ActiveRecord::Migration.deconstrain :books, :quantity, :within

    assert_allows Book do |book|
      book.quantity = 12
    end
  end

  def test_within_inclusive_on_a_column_whose_name_is_a_sql_keyword
    ActiveRecord::Migration.constrain :books, :from, :within => 5..11

    assert_prohibits Book, :from, :within do |book|
      book.from = 12
    end

    assert_prohibits Book, :from, :within do |book|
      book.from = 4
    end

    assert_allows Book do |book|
      book.from = 7
    end

    ActiveRecord::Migration.deconstrain :books, :from, :within

    assert_allows Book do |book|
      book.from = 12
    end
  end

  def test_within_non_inclusive
    ActiveRecord::Migration.constrain :books, :quantity, :within => 5...11

    assert_prohibits Book, :quantity, :within do |book|
      book.quantity = 11
    end

    assert_prohibits Book, :quantity, :within do |book|
      book.quantity = 4
    end

    assert_allows Book do |book|
      book.quantity = 10
    end

    ActiveRecord::Migration.deconstrain :books, :quantity, :within

    assert_allows Book do |book|
      book.quantity = 11
    end
  end

  def test_within_non_inclusive_on_a_column_whose_name_is_a_sql_keyword
    ActiveRecord::Migration.constrain :books, :from, :within => 5...11

    assert_prohibits Book, :from, :within do |book|
      book.from = 11
    end

    assert_prohibits Book, :from, :within do |book|
      book.from = 4
    end

    assert_allows Book do |book|
      book.from = 10
    end

    ActiveRecord::Migration.deconstrain :books, :from, :within

    assert_allows Book do |book|
      book.from = 11
    end
  end

  def test_within_exclude_beginning
    ActiveRecord::Migration.constrain :books, :from, :within => {:range => 5...11, :exclude_beginning => true}

    assert_prohibits Book, :from, :within do |book|
      book.from = 11
    end

    assert_prohibits Book, :from, :within do |book|
      book.from = 5
    end

    assert_allows Book do |book|
      book.from = 10
    end

    ActiveRecord::Migration.deconstrain :books, :from, :within

    assert_allows Book do |book|
      book.from = 5
    end
  end

  def test_within_exclude_end_overrides_range
    ActiveRecord::Migration.constrain :books, :from, :within => {:range => 5...11, :exclude_end => false}

    assert_prohibits Book, :from, :within do |book|
      book.from = 12
    end

    assert_prohibits Book, :from, :within do |book|
      book.from = 4
    end

    assert_allows Book do |book|
      book.from = 11
    end

    ActiveRecord::Migration.deconstrain :books, :from, :within

    assert_allows Book do |book|
      book.from = 12
    end
  end
end
