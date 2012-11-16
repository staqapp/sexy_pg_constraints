require 'test_helper'

class LikeTest < SexyPgConstraintsTest
   def assert_protects_from(contraint, test, allows, disallows)
    column = :title
    constraint = {contraint => test}
    ActiveRecord::Migration.constrain :books, column, constraint
    
    assert_prohibits Book, column, constraint.keys.first do |book|
      book.send("#{column}=", disallows)
    end

    assert_allows Book do |book|
      book.send("#{column}=", allows)
    end

    ActiveRecord::Migration.deconstrain :books, column, contraint

    assert_allows Book do |book|
      book.send("#{column}=", disallows)
    end
  end

  def test_protects_from_vanilla_like
    assert_protects_from :like, '%FUN%', 'HAPPY FUN TIME', 'No Fun'
  end

  def test_protects_from_quotey_like
    assert_protects_from :like, "%'FUN'%", "HAPPY 'FUN' TIME", 'No FUN`'
  end

  def test_protects_from_vanilla_not_like
    assert_protects_from :not_like, '%FUN%', 'No Fun', 'HAPPY FUN TIME' 
  end

  def test_protects_from_quotey_not_like
    assert_protects_from :not_like, "%'FUN'%", 'No FUN`', "HAPPY 'FUN' TIME"
  end
end
