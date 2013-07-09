require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe HasMetadataColumn do
  describe "#has_metadata_column" do
    it "should not allow Rails-magic timestamped column names" do
      -> { SpecSupport::HasMetadataTester.has_metadata_column(created_at: {}) }.should raise_error(/timestamp/)
      -> { SpecSupport::HasMetadataTester.has_metadata_column(created_on: {}) }.should raise_error(/timestamp/)
      -> { SpecSupport::HasMetadataTester.has_metadata_column(updated_at: {}) }.should raise_error(/timestamp/)
      -> { SpecSupport::HasMetadataTester.has_metadata_column(updated_on: {}) }.should raise_error(/timestamp/)
    end

    it "should properly handle subclasses" do
      SpecSupport::HasMetadataTester.metadata_column_fields.should_not include(:inherited)
      SpecSupport::HasMetadataSubclass.metadata_column_fields.should include(:inherited)

      -> { SpecSupport::HasMetadataTester.new.inherited = true }.should raise_error(NoMethodError)
      sc           = SpecSupport::HasMetadataSubclass.new
      sc.inherited = true
      sc.inherited.should be_true
      sc.untyped = 'foo'
      sc.untyped.should eql('foo')
    end

    it "should not allow subclasses to redefine metadata fields" do
      -> { SpecSupport::HasMetadataSubclass.has_metadata_column(untyped: {presence: true}) }.should raise_error(/untyped/)
    end

    it "should not allow subclasses to redefine the metadata column" do
      -> { SpecSupport::HasMetadataSubclass.has_metadata_column(:other) }.should raise_error(/metadata/)
    end

    it "should allow subclasses to omit a custom metadata column" do
      pending "There's gotta be an easy way to test this"
    end

    it "should not allow types that cannot be serialized to JSON" do
      -> { SpecSupport::HasMetadataTester.has_metadata_column(bad_type: {type: Regexp}) }.should raise_error(ArgumentError, /Regexp/)
    end
  end

  [:attribute, :attribute_before_type_cast].each do |getter|
    describe "##{getter}" do
      before(:each) { @object = SpecSupport::HasMetadataTester.new }

      it "should return a field in the metadata object" do
        @object.send :write_attribute, :metadata, {untyped: 'bar'}.to_json
        @object.send(getter.to_s.sub('attribute', 'untyped')).should eql('bar')
      end

      it "should return nil if the metadata column is nil" do
        @object.send :write_attribute, :metadata, nil
        @object.send(getter.to_s.sub('attribute', 'untyped')).should be_nil
      end

      it "should return a default if one is specified" do
        @object.send :write_attribute, :metadata, {}.to_json
        @object.send(getter.to_s.sub('attribute', 'has_default')).should eql('default')
      end

      it "should return nil if nil is stored and the default is not nil" do
        @object.send :write_attribute, :metadata, {has_default: nil}.to_json
        @object.send(getter.to_s.sub('attribute', 'has_default')).should eql(nil)
      end

      it "should not return nil if the metadata" do
        @object         = SpecSupport::HasMetadataTester.new
        @object.boolean = false
        @object.date    = Date.today
        @object.number  = 5
        @object.save!
        object = SpecSupport::HasMetadataTester.select('id').where(id: @object.id).first!
        object.send(getter.to_s.sub('attribute', 'number')).should be_nil
      end
    end
  end

  describe "#attribute=" do
    before :each do
      @object         = SpecSupport::HasMetadataTester.new
      @object.boolean = false
      @object.date    = Date.today
      @object.number  = 5
    end

    it "should set the value in the metadata object" do
      @object.untyped = 'foo'
      JSON.parse(@object.metadata)['untyped'].should eql('foo')
    end

    it "should merge new values into the existing hash" do
      @object.metadata = {'can_be_nil' => 'bar'}.to_json
      @object.untyped  = 'foo'
      JSON.parse(@object.metadata)['untyped'].should eql('foo')
      JSON.parse(@object.metadata)['can_be_nil'].should eql('bar')
    end

    it "should enforce a type if given" do
      @object.date = 'not correct'
      @object.should_not be_valid
      @object.errors[:date].should_not be_empty
    end

    it "should not enforce a type if :skip_type_validation is true" do
      @object.number   = 123
      @object.no_valid = 'not correct'
      @object.should be_valid
    end

    it "should cast a type if possible" do
      @object.number = "50"
      @object.should be_valid
      @object.number.should eql(50)

      @object.boolean = "1"
      @object.should be_valid
      @object.boolean.should eql(true)

      @object.boolean = "0"
      @object.should be_valid
      @object.boolean.should eql(false)
    end

    it "should not try to convert integer types to octal" do
      @object.number = "08"
      @object.should be_valid
      @object.number.should eql(8)
    end

    it "should not enforce a type if :allow_nil is given" do
      @object.can_be_nil = nil
      @object.valid? #@object.should be_valid
      @object.errors[:can_be_nil].should be_empty
    end

    it "should not enforce a type if :allow_blank is given" do
      @object.can_be_blank = ""
      @object.valid? #@object.should be_valid
      @object.errors[:can_be_blank].should be_empty
    end

    it "should set to the default if given nil and allow_blank or allow_nil are false" do
      @object.can_be_nil_with_default = nil
      @object.can_be_nil_with_default.should be_nil

      @object.can_be_blank_with_default = nil
      @object.can_be_blank_with_default.should be_nil

      @object.cannot_be_nil_with_default.should eql(false)

      @object.cannot_be_nil_with_default = nil
      @object.should_not be_valid
      @object.errors[:cannot_be_nil_with_default].should_not be_empty
    end

    it "should enforce other validations as given" do
      @object.number = 'not number'
      @object.should_not be_valid
      @object.errors[:number].should_not be_empty
    end

    it "should mass-assign a multiparameter date attribute" do
      @object.attributes = {'date(1i)' => '1982', 'date(2i)' => '10', 'date(3i)' => '19'}
      @object.date.should eql(Date.civil(1982, 10, 19))
    end

    it "should set a multiparam attribute to nil when the elements are nil" do
      @object.attributes = {'date(1i)' => nil, 'date(2i)' => nil, 'date(3i)' => nil}
      @object.date.should be_nil
    end

    it "should set a multiparam attribute to nil when the elements are empty" do
      @object.attributes = {'date(1i)' => '', 'date(2i)' => '', 'date(3i)' => ''}
      @object.date.should be_nil
    end
  end

  describe "#attribute?" do
    before(:each) { @object = SpecSupport::HasMetadataTester.new }

    context "untyped field" do
      it "should return true if the string is not blank" do
        @object.metadata = {untyped: 'foo'}.to_json
        @object.untyped?.should be_true
      end

      it "should return false if the string is blank" do
        @object.metadata = {untyped: ' '}.to_json
        @object.untyped?.should be_false

        @object.metadata = {untyped: ''}.to_json
        @object.untyped?.should be_false
      end
    end

    context "numeric field" do
      it "should return true if the number is not zero" do
        @object.metadata = {number: 4}.to_json
        @object.number?.should be_true
      end

      it "should return false if the number is zero" do
        @object.metadata = {number: 0}.to_json
        @object.number?.should be_false
      end
    end

    context "typed, non-numeric field" do
      it "should return true if the string is not blank" do
        @object.metadata = {can_be_nil: Date.today}.to_json
        @object.can_be_nil?.should be_true
      end

      it "should return false if the string is blank" do
        @object.metadata = {can_be_nil: nil}.to_json
        @object.can_be_nil?.should be_false
      end
    end
  end

  context "[dirty]" do
    before :each do
      @object = SpecSupport::HasMetadataTester.create!(untyped: 'foo', number: 123, boolean: true, date: Date.today)
    end

    it "should merge local changes with changed metadata" do
      @object.login   = 'me'
      @object.untyped = 'baz'
      @object.changes['login'].should eql([nil, 'me'])
      @object.changes['untyped'].should eql(%w( foo baz ))
    end

    it "should clear changed metadata when saved" do
      @object.login   = 'me'
      @object.untyped = 'baz'
      @object.save!
      @object.changes.should eql({})
    end

    it "should work when there is no associated metadata" do
      SpecSupport::HasMetadataTester.new(login: 'hello').changes.should eql('login' => [nil, 'hello'])
    end

    describe "#attribute_changed?" do
      it "should work with metadata attributes" do
        @object.login   = 'me'
        @object.untyped = 'baz'
        @object.login_changed?.should be_true
        @object.untyped_changed?.should be_true
        @object.save!
        @object.login_changed?.should be_false
        @object.untyped_changed?.should be_false
      end
    end
  end

  describe "#as_json" do
    before :each do
      @object         = SpecSupport::HasMetadataTester.new
      @object.number  = 123
      @object.boolean = true
    end

    it "should include metadata fields" do
      @object.as_json.should eql(
                                 "id"                         => nil,
                                 'login'                      => nil,
                                 'untyped'                    => nil,
                                 'can_be_nil'                 => nil,
                                 'can_be_nil_with_default'    => Date.today,
                                 'can_be_blank'               => nil,
                                 'can_be_blank_with_default'  => Date.today,
                                 'cannot_be_nil_with_default' => false,
                                 'number'                     => 123,
                                 'boolean'                    => true,
                                 'date'                       => nil,
                                 'has_default'                => "default",
                                 'no_valid'                   => nil
                             )
    end

    it "should not clobber an existing :except option" do
      @object.as_json(except: :untyped).should eql(
                                                   "id"                         => nil,
                                                   'login'                      => nil,
                                                   'can_be_nil'                 => nil,
                                                   'can_be_nil_with_default'    => Date.today,
                                                   'can_be_blank'               => nil,
                                                   'can_be_blank_with_default'  => Date.today,
                                                   'cannot_be_nil_with_default' => false,
                                                   'number'                     => 123,
                                                   'boolean'                    => true,
                                                   'date'                       => nil,
                                                   'has_default'                => "default",
                                                   'no_valid'                   => nil
                                               )

      @object.as_json(except: [:untyped, :id]).should eql(
                                                          'login'                      => nil,
                                                          'can_be_nil'                 => nil,
                                                          'can_be_nil_with_default'    => Date.today,
                                                          'can_be_blank'               => nil,
                                                          'can_be_blank_with_default'  => Date.today,
                                                          'cannot_be_nil_with_default' => false,
                                                          'number'                     => 123,
                                                          'boolean'                    => true,
                                                          'date'                       => nil,
                                                          'has_default'                => "default",
                                                          'no_valid'                   => nil
                                                      )
    end

    it "should filter metadata fields with the :only option" do
      @object.as_json(:only => :untyped).should eql('untyped' => nil)

      @object.as_json(:only => [:untyped, :id]).should eql(
                                                           'id'      => nil,
                                                           'untyped' => nil
                                                       )
    end

    it "should not clobber an existing :methods option" do
      class << @object
        def foo()
          1
        end

        def bar()
          '1'
        end
      end

      @object.as_json(methods: :foo).should eql(
                                                "id"                         => nil,
                                                'login'                      => nil,
                                                'untyped'                    => nil,
                                                'can_be_nil'                 => nil,
                                                'can_be_nil_with_default'    => Date.today,
                                                'can_be_blank'               => nil,
                                                'can_be_blank_with_default'  => Date.today,
                                                'cannot_be_nil_with_default' => false,
                                                'number'                     => 123,
                                                'boolean'                    => true,
                                                'date'                       => nil,
                                                'has_default'                => "default",
                                                'no_valid'                   => nil,
                                                'foo'                        => 1
                                            )

      @object.as_json(methods: [:foo, :bar]).should eql(
                                                        "id"                         => nil,
                                                        'login'                      => nil,
                                                        'untyped'                    => nil,
                                                        'can_be_nil'                 => nil,
                                                        'can_be_nil_with_default'    => Date.today,
                                                        'can_be_blank'               => nil,
                                                        'can_be_blank_with_default'  => Date.today,
                                                        'cannot_be_nil_with_default' => false,
                                                        'number'                     => 123,
                                                        'boolean'                    => true,
                                                        'date'                       => nil,
                                                        'has_default'                => "default",
                                                        'no_valid'                   => nil,
                                                        'foo'                        => 1,
                                                        'bar'                        => '1'
                                                    )
    end
  end

  describe "#to_xml" do
    before :each do
      @object         = SpecSupport::HasMetadataTester.new
      @object.number  = 123
      @object.boolean = true
    end

    it "should include metadata fields" do
      @object.to_xml.should eql(<<-XML)
<?xml version="1.0" encoding="UTF-8"?>
<has-metadata-tester>
  <id type="integer" nil="true"/>
  <login nil="true"/>
  <untyped nil="true"/>
  <can-be-nil nil="true"/>
  <can-be-nil-with-default type="date">#{Date.today.to_s}</can-be-nil-with-default>
  <can-be-blank nil="true"/>
  <can-be-blank-with-default type="date">#{Date.today.to_s}</can-be-blank-with-default>
  <cannot-be-nil-with-default type="boolean">false</cannot-be-nil-with-default>
  <number type="integer">123</number>
  <boolean type="boolean">true</boolean>
  <date nil="true"/>
  <has-default>default</has-default>
  <no-valid nil="true"/>
</has-metadata-tester>
      XML
    end

    it "should not clobber an existing :except option" do
      @object.to_xml(except: :untyped).should eql(<<-XML)
<?xml version="1.0" encoding="UTF-8"?>
<has-metadata-tester>
  <id type="integer" nil="true"/>
  <login nil="true"/>
  <can-be-nil nil="true"/>
  <can-be-nil-with-default type="date">#{Date.today.to_s}</can-be-nil-with-default>
  <can-be-blank nil="true"/>
  <can-be-blank-with-default type="date">#{Date.today.to_s}</can-be-blank-with-default>
  <cannot-be-nil-with-default type="boolean">false</cannot-be-nil-with-default>
  <number type="integer">123</number>
  <boolean type="boolean">true</boolean>
  <date nil="true"/>
  <has-default>default</has-default>
  <no-valid nil="true"/>
</has-metadata-tester>
      XML

      @object.to_xml(except: [:untyped, :id]).should eql(<<-XML)
<?xml version="1.0" encoding="UTF-8"?>
<has-metadata-tester>
  <login nil="true"/>
  <can-be-nil nil="true"/>
  <can-be-nil-with-default type="date">#{Date.today.to_s}</can-be-nil-with-default>
  <can-be-blank nil="true"/>
  <can-be-blank-with-default type="date">#{Date.today.to_s}</can-be-blank-with-default>
  <cannot-be-nil-with-default type="boolean">false</cannot-be-nil-with-default>
  <number type="integer">123</number>
  <boolean type="boolean">true</boolean>
  <date nil="true"/>
  <has-default>default</has-default>
  <no-valid nil="true"/>
</has-metadata-tester>
      XML
    end

    it "should filter metadata with an :only option" do
      @object.to_xml(:only => :untyped).should eql(<<-XML)
<?xml version="1.0" encoding="UTF-8"?>
<has-metadata-tester>
  <untyped nil="true"/>
</has-metadata-tester>
      XML

      @object.to_xml(:only => [:untyped, :id]).should eql(<<-XML)
<?xml version="1.0" encoding="UTF-8"?>
<has-metadata-tester>
  <id type="integer" nil="true"/>
  <untyped nil="true"/>
</has-metadata-tester>
      XML
    end

    it "should not clobber an existing :methods option" do
      class << @object
        def foo()
          1
        end

        def bar()
          '1'
        end
      end

      @object.to_xml(methods: :foo).should eql(<<-XML)
<?xml version="1.0" encoding="UTF-8"?>
<has-metadata-tester>
  <id type="integer" nil="true"/>
  <login nil="true"/>
  <foo type="integer">1</foo>
  <untyped nil="true"/>
  <can-be-nil nil="true"/>
  <can-be-nil-with-default type="date">#{Date.today.to_s}</can-be-nil-with-default>
  <can-be-blank nil="true"/>
  <can-be-blank-with-default type="date">#{Date.today.to_s}</can-be-blank-with-default>
  <cannot-be-nil-with-default type="boolean">false</cannot-be-nil-with-default>
  <number type="integer">123</number>
  <boolean type="boolean">true</boolean>
  <date nil="true"/>
  <has-default>default</has-default>
  <no-valid nil="true"/>
</has-metadata-tester>
      XML

      @object.to_xml(methods: [:foo, :bar]).should eql(<<-XML)
<?xml version="1.0" encoding="UTF-8"?>
<has-metadata-tester>
  <id type="integer" nil="true"/>
  <login nil="true"/>
  <foo type="integer">1</foo>
  <bar>1</bar>
  <untyped nil="true"/>
  <can-be-nil nil="true"/>
  <can-be-nil-with-default type="date">#{Date.today.to_s}</can-be-nil-with-default>
  <can-be-blank nil="true"/>
  <can-be-blank-with-default type="date">#{Date.today.to_s}</can-be-blank-with-default>
  <cannot-be-nil-with-default type="boolean">false</cannot-be-nil-with-default>
  <number type="integer">123</number>
  <boolean type="boolean">true</boolean>
  <date nil="true"/>
  <has-default>default</has-default>
  <no-valid nil="true"/>
</has-metadata-tester>
      XML
    end
  end

  describe "#reload" do
    before(:each) { @object = SpecSupport::HasMetadataTester.create!(untyped: 'foo', number: 123, boolean: true, date: Date.today) }

    it "should reload instance variables properly" do
      SpecSupport::HasMetadataTester.where(id: @object.id).update_all(metadata: {untyped: 'reloaded'}.to_json)
      @object.reload.untyped.should eql('reloaded')
    end
  end
end
