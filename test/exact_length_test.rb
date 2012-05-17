require 'test_helper'

class ExactLengthTest < SexyPgConstraintsTest
  def test_exact_length
    ActiveRecord::Migration.add_constraint :books, :isbn, :exact_length => 5

    assert_prohibits Book, :isbn, :exact_length do |book|
      book.isbn = '123456'
    end

    assert_prohibits Book, :isbn, :exact_length do |book|
      book.isbn = '1234'
    end

    assert_allows Book do |book|
      book.isbn = '12345'
    end

    ActiveRecord::Migration.drop_constraint :books, :isbn, :exact_length

    assert_allows Book do |book|
      book.isbn = '123456'
    end
  end

  def test_exact_length_on_a_column_whose_name_is_a_sql_keyword
    ActiveRecord::Migration.add_constraint :books, :as, :exact_length => 5

    assert_prohibits Book, :as, :exact_length do |book|
      book.as = '123456'
    end

    assert_prohibits Book, :as, :exact_length do |book|
      book.as = '1234'
    end

    assert_allows Book do |book|
      book.as = '12345'
    end

    ActiveRecord::Migration.drop_constraint :books, :as, :exact_length

    assert_allows Book do |book|
      book.as = '123456'
    end
  end
end
