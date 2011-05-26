require 'test_helper'

class BlacklistTest < SexyPgConstraintsTest
  def test_blacklist
    ActiveRecord::Migration.constrain :books, :author, :blacklist => %w(blacklisted1 blacklisted2 blacklisted3)

    assert_prohibits Book, :author, :blacklist do |book|
      book.author = 'blacklisted2'
    end

    assert_allows Book do |book|
      book.author = 'not_blacklisted'
    end

    ActiveRecord::Migration.deconstrain :books, :author, :blacklist

    assert_allows Book do |book|
      book.author = 'blacklisted2'
    end
  end

  def test_blacklist_on_a_column_whose_name_is_a_sql_keyword
    ActiveRecord::Migration.constrain :books, :as, :blacklist => %w(blacklisted1 blacklisted2 blacklisted3)

    assert_prohibits Book, :as, :blacklist do |book|
      book.as = 'blacklisted2'
    end

    assert_allows Book do |book|
      book.as = 'not_blacklisted'
    end

    ActiveRecord::Migration.deconstrain :books, :as, :blacklist

    assert_allows Book do |book|
      book.as = 'blacklisted2'
    end
  end
end
