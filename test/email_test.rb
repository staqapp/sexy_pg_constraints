require 'test_helper'

class EmailTest < SexyPgConstraintsTest
  def test_email
    ActiveRecord::Migration.constrain :books, :author, :email => true

    assert_prohibits Book, :author, :email do |book|
      book.author = 'blah@example'
    end

    assert_allows Book do |book|
      book.author = 'blah@example.com'
    end

    ActiveRecord::Migration.deconstrain :books, :author, :email

    assert_allows Book do |book|
      book.author = 'blah@example'
    end
  end

  def test_email_on_a_column_whose_name_is_a_sql_keyword
    ActiveRecord::Migration.constrain :books, :as, :email => true

    assert_prohibits Book, :as, :email do |book|
      book.as = 'blah@example'
    end

    assert_allows Book do |book|
      book.as = 'blah@example.com'
    end

    ActiveRecord::Migration.deconstrain :books, :as, :email

    assert_allows Book do |book|
      book.as = 'blah@example'
    end
  end
end
