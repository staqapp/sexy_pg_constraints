require 'test_helper'

class NotBlankTest < SexyPgConstraintsTest
  def test_not_blank
    ActiveRecord::Migration.constrain :books, :author, :not_blank => true

    assert_prohibits Book, :author, :not_blank do |book|
      book.author = ' '
    end

    assert_allows Book do |book|
      book.author = 'foo'
    end

    ActiveRecord::Migration.deconstrain :books, :author, :not_blank

    assert_allows Book do |book|
      book.author = ' '
    end
  end

  def test_not_blank_on_a_column_whose_name_is_a_sql_keyword
    ActiveRecord::Migration.constrain :books, :as, :not_blank => true

    assert_prohibits Book, :as, :not_blank do |book|
      book.as = ' '
    end

    assert_allows Book do |book|
      book.as = 'foo'
    end

    ActiveRecord::Migration.deconstrain :books, :as, :not_blank

    assert_allows Book do |book|
      book.as = ' '
    end
  end
end
