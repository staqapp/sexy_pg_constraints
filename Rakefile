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
