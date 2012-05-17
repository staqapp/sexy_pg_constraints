require 'test_helper'

require 'test_helper'

class GeneralTest < SexyPgConstraintsTest
  def test_should_create_book
    Book.create
    assert_equal 1, Book.count
  end

  def test_block_syntax
    ActiveRecord::Migration.constrain :books do |t|
      t.title :present => true
      t.isbn :exact_length => 15
      t.author :alphanumeric => true
    end

    assert_prohibits Book, :title, :present do |book|
      book.title = '  '
    end

    assert_prohibits Book, :isbn, :exact_length do |book|
      book.isbn = 'asdf'
    end

    assert_prohibits Book, :author, :alphanumeric do |book|
      book.author = 'foo#bar'
    end

    ActiveRecord::Migration.deconstrain :books do |t|
      t.title :present
      t.isbn :exact_length
      t.author :alphanumeric
    end

    assert_allows Book do |book|
      book.title  = '  '
      book.isbn   = 'asdf'
      book.author = 'foo#bar'
    end
  end

  def test_multiple_constraints_per_line
    ActiveRecord::Migration.constrain :books do |t|
      t.title :present => true, :alphanumeric => true, :blacklist => %w(foo bar)
    end

    assert_prohibits Book, :title, [:present, :alphanumeric] do |book|
      book.title = ' '
    end

    assert_prohibits Book, :title, :alphanumeric do |book|
      book.title = 'asdf@asdf'
    end

    assert_prohibits Book, :title, :blacklist do |book|
      book.title = 'foo'
    end

    ActiveRecord::Migration.deconstrain :books do |t|
      t.title :present, :alphanumeric, :blacklist
    end

    assert_allows Book do |book|
      book.title = ' '
    end

    assert_allows Book do |book|
      book.title = 'asdf@asdf'
    end

    assert_allows Book do |book|
      book.title = 'foo'
    end
  end

  def test_multicolumn_constraint
    ActiveRecord::Migration.constrain :books, [:title, :isbn], :unique => true

    assert_allows Book do |book|
      book.title = 'foo'
      book.isbn = 'bar'
    end

    assert_allows Book do |book|
      book.title = 'foo'
      book.isbn = 'foo'
    end

    assert_prohibits Book, [:title, :isbn], :unique, 'unique', ActiveRecord::RecordNotUnique do |book|
      book.title = 'foo'
      book.isbn = 'bar'
    end

    ActiveRecord::Migration.deconstrain :books, [:title, :isbn], :unique

    assert_allows Book do |book|
      book.title = 'foo'
      book.isbn = 'bar'
    end
  end

  def test_multicolumn_constraint_block_syntax
    ActiveRecord::Migration.constrain :books do |t|
      t[:title, :isbn].all :unique => true
    end

    assert_allows Book do |book|
      book.title = 'foo'
      book.isbn = 'bar'
    end

    assert_allows Book do |book|
      book.title = 'foo'
      book.isbn = 'foo'
    end

    assert_prohibits Book, [:title, :isbn], :unique, 'unique', ActiveRecord::RecordNotUnique do |book|
      book.title = 'foo'
      book.isbn = 'bar'
    end

    ActiveRecord::Migration.deconstrain :books do |t|
      t[:title, :isbn].all :unique
    end

    assert_allows Book do |book|
      book.title = 'foo'
      book.isbn = 'bar'
    end
  end
end
