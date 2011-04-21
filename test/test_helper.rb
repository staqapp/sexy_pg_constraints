require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'active_support/core_ext/class/attribute_accessors'
require 'active_support/core_ext/module/delegation'
require 'active_record'
require 'test/unit'
require 'shoulda'

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require "sexy_pg_constraints"
require 'support/models'
require 'support/assert_prohibits_allows'

db_config_path = File.join(File.dirname(__FILE__), 'support', 'database.yml')
ActiveRecord::Base.establish_connection(YAML::load(open(db_config_path)))
ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.send(:include, SexyPgConstraints)

class Test::Unit::TestCase
end
