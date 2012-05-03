require 'test_helper'

class NotBlankTest < SexyPgConstraintsTest
  def assert_protects_from_blank(column, contraint)
    ActiveRecord::Migration.constrain :books, column, contraint => true

    assert_prohibits Book, column, contraint do |book|
      book.send("#{column}=", ' ')
    end

    assert_allows Book do |book|
      book.send("#{column}=", 'foo')
    end

    ActiveRecord::Migration.deconstrain :books, column, contraint

    assert_allows Book do |book|
      book.send("#{column}=", ' ')
    end
  end

  def test_not_blank
    assert_protects_from_blank(:author, :not_blank)
  end

  def test_present
    assert_protects_from_blank(:author, :present)
  end

  def test_not_blank_on_a_column_whose_name_is_a_sql_keyword
    assert_protects_from_blank(:as, :not_blank)
  end
end
