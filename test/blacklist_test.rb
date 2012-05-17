require 'test_helper'

class BlacklistTest < SexyPgConstraintsTest
  def test_blacklist
    ActiveRecord::Migration.add_constraint :books, :author, :blacklist => %w(blacklisted1 blacklisted2 blacklisted3)

    assert_prohibits Book, :author, :blacklist do |book|
      book.author = 'blacklisted2'
    end

    assert_allows Book do |book|
      book.author = 'not_blacklisted'
    end

    ActiveRecord::Migration.drop_constraint :books, :author, :blacklist

    assert_allows Book do |book|
      book.author = 'blacklisted2'
    end
  end

  def test_blacklist_on_a_column_whose_name_is_a_sql_keyword
    ActiveRecord::Migration.add_constraint :books, :as, :blacklist => %w(blacklisted1 blacklisted2 blacklisted3)

    assert_prohibits Book, :as, :blacklist do |book|
      book.as = 'blacklisted2'
    end

    assert_allows Book do |book|
      book.as = 'not_blacklisted'
    end

    ActiveRecord::Migration.drop_constraint :books, :as, :blacklist

    assert_allows Book do |book|
      book.as = 'blacklisted2'
    end
  end
end
