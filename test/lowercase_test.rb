require 'test_helper'

class LowercaseTest < SexyPgConstraintsTest
  def test_lowercase
    ActiveRecord::Migration.add_constraint :books, :author, :lowercase => true

    assert_prohibits Book, :author, :lowercase do |book|
      book.author = 'UPPER'
    end

    assert_allows Book do |book|
      book.author = 'lower with 1337'
    end

    ActiveRecord::Migration.drop_constraint :books, :author, :lowercase

    assert_allows Book do |book|
      book.author = 'UPPER'
    end
  end
end
