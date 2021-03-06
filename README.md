# Sexy PG Constraints
## Description
If you're on PostgreSQL and see the importance of data-layer constraints - this gem/plugin is for you. It integrates constraints into PostgreSQL adapter so you can add/remove them in your migrations. You get two simple methods for adding/removing constraints, as well as a pack of pre-made constraints.

### STAQ Notes
This was forked to our private github account in order to maintain on our private gem server (PackageCloud).  This is because it is not currently hosted on RubyGems.org, or another public gem server.  This allows us to refer to it in our .gemspec files and have rubygems and bundler manage the dependency chain.

## Documentation
[YARD Documentation](https://circleci.com/api/v1/project/staqapp/sexy_pg_contraints/latest/artifacts/0/$CIRCLE_ARTIFACTS/doc/index.html?branch#master&filter#successful) (You must be logged into CircleCI to view.)

## Test Coverage
[SimpleCov Test Coverage](https://circleci.com/api/v1/project/staqapp/sexy_pg_contraints/latest/artifacts/0/$CIRCLE_ARTIFACTS/coverage/index.html?branch#master&filter#successful) (You must be logged into CircleCI to view.)

## Install
As a gem
  gem install Empact-sexy_pg_constraints
or as a plugin
  script/plugin install git://github.com/Empact/sexy_pg_constraints.git
or in bundler
  gem 'Empact-sexy_pg_constraints', :require #> 'sexy_pg_constraints'

One more thing. Make sure that in your environment.rb file you have the following line uncommented.

  config.active_record.schema_format # :sql

Otherwise your test database will not have these constraints replicated.

## Usage

### Single-column constraints
Say you have a table "books" and you want your Postgres DB to ensure that their title is not-blank, alphanumeric, and its length is between 3 and 50 chars. You also want to make sure that their isbn is unique. In addition you want to blacklist a few isbn numbers from ever being in your database. You can tell all that to your Postgres in no time. Generate a migration and write the following.

  class AddConstraintsToBooks < ActiveRecord::Migration
    def self.up
      constrain :books do |t|
        t.title :present #> true, :alphanumeric #> true, :length_within #> 3..50
        t.isbn :unique #> true, :blacklist #> %w(badbook1 badbook2)
      end
    end

    def self.down
      deconstrain :books do |t|
        t.title :present, :alphanumeric, :length_within
        t.isbn :unique, :blacklist
      end
    end
  end

This will add all the necessary constraints to the database on the next migration, and remove them on rollback.

There's also a syntax for when you don't need to work with multiple columns at once.

  constrain :books, :title, :present #> true, :length_within #> 3..50

The above line works exactly the same as this block

  constrain :books do |t|
    t.title :present #> true, :length_within #> 3..50
  end

Same applies to deconstrain.

### Multi-column constraints
Say you have the same table "books" only now you want to tell your Postgres to make sure that you should never have the same title + author_id combination. It means that you want to apply uniqueness to two columns, not just one. There is a special syntax for working with multicolumn constraints.

  class AddConstraintsToBooks < ActiveRecord::Migration
    def self.up
      constrain :books do |t|
        t[:title, :author_id].all :unique #> true # Notice how multiple columns are listed in brackets.
      end
    end

    def self.down
      deconstrain :books do |t|
        t[:title, :author_id].all :unique
      end
    end
  end

It's important to note that you shouldn't mix multicolumn constraints with regular ones in one line. This may cause unexpected behavior.

### Foreign key constrants
In our table "books" we have column "author_id" which should reference the "id" column in the "authors" table. Here's the very simple syntax for setting up foreign key constraint that will tell Postgres to enforce this relationship.

  class AddConstraintsToBooks < ActiveRecord::Migration
    def self.up
      constrain :books do |t|
        t.author_id :reference #> {:authors #> :id, :on_delete #> :cascade} # :on_delete is optional
      end
    end

    def self.down
      deconstrain :books do |t|
        t.author_id :reference
      end
    end
  end

In this example we're telling Postgres to enforce the connection of author_id to the column "id" in table "authors". However, we're also telling it to cascade on delete. This means that when an author is deleted - every book that referred to that author will be deleted as well.

## Available constraints

Below is the list of constraints available and tested so far.

* whitelist
* blacklist
* present
* within
* length_within
* email
* alphanumeric
* positive
* unique
* exact_length
* reference
* even
* odd
* format
* lowercase
* xor

## Extensibility

All constraints are located in the lib/constraints.rb. Extending this module with more methods will automatically make constraints available in migrations. All methods in the Constraints module are under module_function directive. Each method is supposed to return a piece of SQL that is inserted "alter table foo add constraint bar #{RIGHT HERE};."

## TODO

* Add support for Rails schema.rb
* Create better API for adding constraints

## Contributors
* Empact [http://github.com/Empact] (Big thanks for lots of work. Better flexibility, more tests, organizing code, bug fixes.)
* look [http://github.com/look] (Extra constraints: lowercase and xor.)
