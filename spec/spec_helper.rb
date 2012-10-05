require 'bundler'
Bundler.require :default, :development
require 'active_record'
require 'active_support/concern'

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'has_metadata_column'

ActiveRecord::Base.establish_connection(
  adapter:  'sqlite3',
  database: 'test.sqlite'
)

module SpecSupport
  class ConstructorTester
    attr_reader :args
    def initialize(*args) @args = args end
  end

  class HasMetadataTester < ActiveRecord::Base
    include HasMetadataColumn
    self.table_name = 'users'
    has_metadata_column :metadata,
                        untyped:                    {},
                        can_be_nil:                 { type: Date, allow_nil: true },
                        can_be_nil_with_default:    { type: Date, allow_nil: true, default: Date.today },
                        can_be_blank:               { type: Date, allow_blank: true },
                        can_be_blank_with_default:  { type: Date, allow_blank: true, default: Date.today },
                        cannot_be_nil_with_default: { type: Boolean, allow_nil: false, default: false },
                        number:                     { type: Fixnum, numericality: true },
                        boolean:                    { type: Boolean },
                        date:                       { type: Date },
                        has_default:                { default: 'default' },
                        no_valid:                   { type: Fixnum, skip_type_validation: true }
  end

  class HasMetadataSubclass < HasMetadataTester
    has_metadata_column :metadata, inherited: {}
  end
end

# Requires supporting files with custom matchers and macros, etc,
# in ./support/ and its subdirectories.
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

RSpec.configure do |config|
  config.before(:each) do
    SpecSupport::HasMetadataTester.connection.execute "DROP TABLE IF EXISTS users"
    SpecSupport::HasMetadataTester.connection.execute "CREATE TABLE users (id INTEGER PRIMARY KEY ASC, metadata TEXT, login VARCHAR(100))"
  end
end
