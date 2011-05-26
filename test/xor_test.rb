require 'test_helper'

class XorTest < SexyPgConstraintsTest
  def test_xor
    ActiveRecord::Migration.constrain :books, [:xor_col_1, :xor_col_2], :xor => true

    assert_prohibits Book, [:xor_col_1, :xor_col_2], :xor do |book|
      book.xor_col_1 = 123
      book.xor_col_2 = 321
    end

    assert_allows Book do |book|
      book.xor_col_1 = 123
    end

    assert_allows Book do |book|
      book.xor_col_2 = 123
    end

    ActiveRecord::Migration.deconstrain :books, [:xor_col_1, :xor_col_2], :xor

    assert_allows Book do |book|
      book.xor_col_1 = 123
      book.xor_col_2 = 123
    end
  end
end
