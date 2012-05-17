require 'test_helper'

class StrippedTest < SexyPgConstraintsTest
  DEFAULT_PROHIBITED = [' foo', 'foo ', ' foo ']
  CONFIGURABLE_PROHIBITED = ["foo \t", "\t foo"]
  DEFAULT_ALLOWED = ['foo', 'foo \t']

  def test_stripped
    ActiveRecord::Migration.constrain :books, :author, :stripped => true

    DEFAULT_PROHIBITED.each do |prohibited|
      assert_prohibits Book, :author, :stripped do |book|
        book.author = prohibited
      end
    end

    DEFAULT_ALLOWED + CONFIGURABLE_PROHIBITED.each do |allowed|
      assert_allows Book do |book|
        book.author = allowed
      end
    end

    ActiveRecord::Migration.deconstrain :books, :author, :stripped

    DEFAULT_PROHIBITED.each do |prohibited|
      assert_allows Book do |book|
        book.author = prohibited
      end
    end
  end

  def test_stripped
    ActiveRecord::Migration.constrain :books, :author, :stripped => true

    DEFAULT_PROHIBITED.each do |prohibited|
      assert_prohibits Book, :author, :stripped do |book|
        book.author = prohibited
      end
    end

    DEFAULT_ALLOWED + CONFIGURABLE_PROHIBITED.each do |allowed|
      assert_allows Book do |book|
        book.author = allowed
      end
    end

    ActiveRecord::Migration.deconstrain :books, :author, :stripped

    DEFAULT_PROHIBITED.each do |prohibited|
      assert_allows Book do |book|
        book.author = prohibited
      end
    end
  end

  def test_stripped_on_a_column_whose_name_is_a_sql_keyword
    ActiveRecord::Migration.constrain :books, :as, :stripped => true

    DEFAULT_PROHIBITED.each do |prohibited|
      assert_prohibits Book, :as, :stripped do |book|
        book.as = prohibited
      end
    end

    DEFAULT_ALLOWED + CONFIGURABLE_PROHIBITED.each do |allowed|
      assert_allows Book do |book|
        book.as = allowed
      end
    end

    ActiveRecord::Migration.deconstrain :books, :as, :stripped

    DEFAULT_PROHIBITED.each do |prohibited|
      assert_allows Book do |book|
        book.as = prohibited
      end
    end
  end

  def test_stripped_with_a_character_list
    ActiveRecord::Migration.constrain :books, :as, :stripped => '\t '

    DEFAULT_PROHIBITED + CONFIGURABLE_PROHIBITED.each do |prohibited|
      p prohibited
      assert_prohibits Book, :as, :stripped do |book|
        book.as = prohibited
      end
    end

    DEFAULT_ALLOWED.each do |allowed|
      assert_allows Book do |book|
        book.as = allowed
      end
    end

    ActiveRecord::Migration.deconstrain :books, :as, :stripped

    DEFAULT_PROHIBITED + CONFIGURABLE_PROHIBITED.each do |prohibited|
      assert_allows Book do |book|
        book.as = prohibited
      end
    end
  end
end
