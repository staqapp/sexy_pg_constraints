# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-
# stub: Empact-sexy_pg_constraints 0.4.1 ruby lib

Gem::Specification.new do |s|
  s.name = "Empact-sexy_pg_constraints".freeze
  s.version = "0.4.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Maxim Chernyak".freeze, "Ben Woosley".freeze]
  s.date = "2016-09-29"
  s.description = "Use migrations and simple syntax to manage constraints in PostgreSQL DB.".freeze
  s.email = "ben.woosley@gmail.com".freeze
  s.extra_rdoc_files = [
    "CHANGELOG.rdoc",
    "LICENSE.txt",
    "README.md"
  ]
  s.files = [
    ".ruby-version",
    ".simplecov",
    "CHANGELOG.rdoc",
    "Empact-sexy_pg_constraints.gemspec",
    "Gemfile",
    "Gemfile.lock",
    "LICENSE.txt",
    "README.md",
    "Rakefile",
    "VERSION",
    "circle.yml",
    "init.rb",
    "lib/sexy_pg_constraints.rb",
    "lib/sexy_pg_constraints/constrainers/constrainer.rb",
    "lib/sexy_pg_constraints/constrainers/deconstrainer.rb",
    "lib/sexy_pg_constraints/constrainers/helpers.rb",
    "lib/sexy_pg_constraints/constraints.rb",
    "lib/sexy_pg_constraints/railtie.rb",
    "lib/sexy_pg_constraints/schema_definitions.rb"
  ]
  s.homepage = "http://github.com/maxim/sexy_pg_constraints".freeze
  s.rubygems_version = "2.6.4".freeze
  s.summary = nil

  s.metadata["allowed_push_host"] = "https://packagecloud.io"
  s.add_development_dependency "test-unit"

  s.add_runtime_dependency(%q<activerecord>, [">= 3.0.0"])
  s.add_development_dependency(%q<pg>, [">= 0"])
  s.add_development_dependency(%q<shoulda>, [">= 0"])
  s.add_development_dependency(%q<jeweler>, [">= 0"])
end

