require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'rake'

require 'jeweler'
Jeweler::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://docs.rubygems.org/read/chapter/20 for more options
  gem.name = 'Empact-sexy_pg_constraints'
  gem.homepage = "http://github.com/maxim/sexy_pg_constraints"
  gem.description = "Use migrations and simple syntax to manage constraints in PostgreSQL DB."
  gem.email = "ben.woosley@gmail.com"
  gem.authors = ["Maxim Chernyak", "Ben Woosley"]
  # Include your dependencies below. Runtime dependencies are required when using your gem,
  # and development dependencies are only needed for development (ie running rake tasks, tests, etc)
  #  gem.add_runtime_dependency 'jabber4r', '> 0.1'
  #  gem.add_development_dependency 'rspec', '> 1.2.3'
end
Jeweler::RubygemsDotOrgTasks.new

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/*_test.rb'
  test.verbose = true
end

task :default => :test

require 'rdoc/task'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "test #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end


require "bundler/gem_tasks"

Rake::Task["release:rubygem_push"].clear

namespace :release do
  desc "Open CircleCI to watch the build and gem release process"
  task :monitor do
    require "pathname"

    repo_name = Pathname(File.expand_path(__dir__)).basename
    cmd = "open https://circleci.com/gh/staqapp/#{repo_name}"
    `#{cmd}`
  end
end

desc "Build the gem, create a git tag, and push to git. If the build passes, CircleCI will publish to packagecloud"
task :release, [:remote] => %w(build release:guard_clean release:source_control_push release:monitor)
