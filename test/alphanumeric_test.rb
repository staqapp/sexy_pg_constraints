require 'test_helper'

class AlphanumericTest < SexyPgConstraintsTest
  def test_alphanumeric
    ActiveRecord::Migration.constrain :books, :title, :alphanumeric => true

    assert_prohibits Book, :title, :alphanumeric do |book|
      book.title = 'asdf@asdf'
    end

    assert_allows Book do |book|
      book.title = 'asdf'
    end

    ActiveRecord::Migration.deconstrain :books, :title, :alphanumeric

    assert_allows Book do |book|
      book.title = 'asdf@asdf'
    end
  end

  def test_alphanumeric_on_a_column_whose_name_is_a_sql_keyword
    ActiveRecord::Migration.constrain :books, :as, :alphanumeric => true

    assert_prohibits Book, :as, :alphanumeric do |book|
      book.as = 'asdf@asdf'
    end

    assert_allows Book do |book|
      book.as = 'asdf'
    end

    ActiveRecord::Migration.deconstrain :books, :as, :alphanumeric

    assert_allows Book do |book|
      book.as = 'asdf@asdf'
    end
  end
end