require 'test_helper'

class LengthWithinTest < SexyPgConstraintsTest
  def test_length_within_inclusive
    ActiveRecord::Migration.constrain :books, :title, :length_within => 5..11

    assert_prohibits Book, :title, :length_within do |book|
      book.title = 'abcdefghijkl'
    end

    assert_prohibits Book, :title, :length_within do |book|
      book.title = 'abcd'
    end

    assert_allows Book do |book|
      book.title = 'abcdefg'
    end

    ActiveRecord::Migration.deconstrain :books, :title, :length_within

    assert_allows Book do |book|
      book.title = 'abcdefghijkl'
    end
  end

  def test_length_within_inclusive_on_a_column_whose_name_is_a_sql_keyword
    ActiveRecord::Migration.constrain :books, :as, :length_within => 5..11

    assert_prohibits Book, :as, :length_within do |book|
      book.as = 'abcdefghijkl'
    end

    assert_prohibits Book, :as, :length_within do |book|
      book.as = 'abcd'
    end

    assert_allows Book do |book|
      book.as = 'abcdefg'
    end

    ActiveRecord::Migration.deconstrain :books, :as, :length_within

    assert_allows Book do |book|
      book.as = 'abcdefghijkl'
    end
  end

  def test_length_within_non_inclusive
    ActiveRecord::Migration.constrain :books, :title, :length_within => 5...11

    assert_prohibits Book, :title, :length_within do |book|
      book.title = 'abcdefghijk'
    end

    assert_prohibits Book, :title, :length_within do |book|
      book.title = 'abcd'
    end

    assert_allows Book do |book|
      book.title = 'abcdefg'
    end

    ActiveRecord::Migration.deconstrain :books, :title, :length_within

    assert_allows Book do |book|
      book.title = 'abcdefghijk'
    end
  end

  def test_length_within_non_inclusive_on_a_column_whose_name_is_a_sql_keyword
    ActiveRecord::Migration.constrain :books, :as, :length_within => 5...11

    assert_prohibits Book, :as, :length_within do |book|
      book.as = 'abcdefghijk'
    end

    assert_prohibits Book, :as, :length_within do |book|
      book.as = 'abcd'
    end

    assert_allows Book do |book|
      book.as = 'abcdefg'
    end

    ActiveRecord::Migration.deconstrain :books, :as, :length_within

    assert_allows Book do |book|
      book.as = 'abcdefghijk'
    end
  end
end
