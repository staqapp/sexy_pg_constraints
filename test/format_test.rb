require 'test_helper'

class FormatTest < SexyPgConstraintsTest
  def test_format_case_insensitive
    ActiveRecord::Migration.constrain :books, :title, :format => /^[a-z]+$/i

    assert_prohibits Book, :title, :format do |book|
      book.title = 'abc3'
    end

    assert_prohibits Book, :title, :format do |book|
      book.title = ''
    end

    assert_allows Book do |book|
      book.title = 'abc'
    end

    assert_allows Book do |book|
      book.title = 'ABc'
    end

    ActiveRecord::Migration.deconstrain :books, :title, :format

    assert_allows Book do |book|
      book.title = 'abc3'
    end
  end

  def test_format_case_insensitive_on_a_column_whose_name_is_a_sql_keyword
    ActiveRecord::Migration.constrain :books, :as, :format => /^[a-z]+$/i

    assert_prohibits Book, :as, :format do |book|
      book.as = 'abc3'
    end

    assert_prohibits Book, :as, :format do |book|
      book.as = ''
    end

    assert_allows Book do |book|
      book.as = 'abc'
    end

    assert_allows Book do |book|
      book.as = 'ABc'
    end

    ActiveRecord::Migration.deconstrain :books, :as, :format

    assert_allows Book do |book|
      book.as = 'abc3'
    end
  end

  def test_format_case_sensitive
    ActiveRecord::Migration.constrain :books, :title, :format => /^[a-z]+$/

    assert_prohibits Book, :title, :format do |book|
      book.title = 'aBc'
    end

    assert_allows Book do |book|
      book.title = 'abc'
    end

    ActiveRecord::Migration.deconstrain :books, :title, :format

    assert_allows Book do |book|
      book.title = 'aBc'
    end
  end

  def test_format_case_sensitive_on_a_column_whose_name_is_a_sql_keyword
    ActiveRecord::Migration.constrain :books, :as, :format => /^[a-z]+$/

    assert_prohibits Book, :as, :format do |book|
      book.as = 'aBc'
    end

    assert_allows Book do |book|
      book.as = 'abc'
    end

    ActiveRecord::Migration.deconstrain :books, :as, :format

    assert_allows Book do |book|
      book.as = 'aBc'
    end
  end
end
