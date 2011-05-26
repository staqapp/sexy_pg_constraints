require 'test_helper'

class WhitelistTest < SexyPgConstraintsTest
  def test_whitelist
    ActiveRecord::Migration.constrain :books, :author, :whitelist => %w(whitelisted1 whitelisted2 whitelisted3)

    assert_prohibits Book, :author, :whitelist do |book|
      book.author = 'not_whitelisted'
    end

    assert_allows Book do |book|
      book.author = 'whitelisted2'
    end

    ActiveRecord::Migration.deconstrain :books, :author, :whitelist

    assert_allows Book do |book|
      book.author = 'not_whitelisted'
    end
  end

  def test_whitelist_on_a_column_whose_name_is_a_sql_keyword
    ActiveRecord::Migration.constrain :books, :as, :whitelist => %w(whitelisted1 whitelisted2 whitelisted3)

    assert_prohibits Book, :as, :whitelist do |book|
      book.as = 'not_whitelisted'
    end

    assert_allows Book do |book|
      book.as = 'whitelisted2'
    end

    ActiveRecord::Migration.deconstrain :books, :as, :whitelist

    assert_allows Book do |book|
      book.as = 'not_whitelisted'
    end
  end
end
