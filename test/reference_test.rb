require 'test_helper'

class ReferenceTest < SexyPgConstraintsTest
  def test_reference
    ActiveRecord::Migration.constrain :books, :author_id, :reference => {:authors => :id}

    assert_prohibits Book, :author_id, :reference, 'foreign key', ActiveRecord::InvalidForeignKey do |book|
      book.author_id = 1
    end

    author = Author.new
    author.name = "Mark Twain"
    author.bio = "American writer"
    assert author.save

    assert_equal 1, author.id

    assert_allows Book do |book|
      book.author_id = 1
    end

    ActiveRecord::Migration.deconstrain :books, :author_id, :reference

    assert_allows Book do |book|
      book.author_id = 2
    end
  end

  def test_reference_on_a_column_whose_name_is_a_sql_keyword
    ActiveRecord::Migration.constrain :books, :from, :reference => {:authors => :id}

    assert_prohibits Book, :from, :reference, 'foreign key', ActiveRecord::InvalidForeignKey do |book|
      book.from = 1
    end

    author = Author.new
    author.name = "Mark Twain"
    author.bio = "American writer"
    assert author.save

    assert_equal 1, author.id

    assert_allows Book do |book|
      book.from = 1
    end

    ActiveRecord::Migration.deconstrain :books, :from, :reference

    assert_allows Book do |book|
      book.from = 2
    end
  end

  def test_reference_with_on_delete
    ActiveRecord::Migration.constrain :books, :author_id, :reference => {:authors => :id, :on_delete => :cascade}

    author = Author.new
    author.name = "Mark Twain"
    author.bio = "American writer"
    assert author.save

    assert_equal 1, Author.count

    assert_allows Book do |book|
      book.title = "The Adventures of Tom Sawyer"
      book.author_id = 1
    end

    assert_allows Book do |book|
      book.title = "The Adventures of Huckleberry Finn"
      book.author_id = 1
    end

    author.destroy

    assert_equal 0, Author.count
    assert_equal 0, Book.count
  end
end
