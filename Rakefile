# encoding: utf-8

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
  gem.name                  = "has_metadata_column"
  gem.homepage              = "http://github.com/riscfuture/has_metadata_column"
  gem.license               = "MIT"
  gem.summary               = %Q{Schemaless metadata using JSON columns}
  gem.description           = %Q{Reduce your table width and migration overhead by moving non-indexed columns to a separate metadata column.}
  gem.email                 = "git@timothymorgan.info"
  gem.authors               = ["Tim Morgan"]
  gem.required_ruby_version = '>= 1.9'
  gem.files                 = %w( lib/**/* has_metadata_column.gemspec LICENSE README.md )
  # dependencies defined in Gemfile
end
Jeweler::RubygemsDotOrgTasks.new

require 'rspec/core'
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = FileList['spec/**/*_spec.rb']
end

RSpec::Core::RakeTask.new(:rcov) do |spec|
  spec.pattern = 'spec/**/*_spec.rb'
  spec.rcov    = true
end

task default: :spec

require 'yard'
YARD::Rake::YardocTask.new('doc') do |doc|
  doc.options << '-m' << 'markdown' << '-M' << 'redcarpet'
  doc.options << '--protected' << '--no-private'
  doc.options << '-r' << 'README.md'
  doc.options << '-o' << 'doc'
  doc.options << '--title' << 'HasMetadataColumn Documentation'

  doc.files = %w( lib/**/* README.md )
end
