if ENV["COVERAGE"]
  require "simplecov"

  if artifacts_dir = ENV["CIRCLE_ARTIFACTS"]
    # see https://circleci.com/docs/code-coverage/
    dir = File.join(artifacts_dir,"coverage")
    SimpleCov.coverage_dir(dir)
  end

  SimpleCov.start do
    add_filter "/test/"
    add_filter "/.bundle/"
    add_filter "/vendor/cache/"
  end
end
