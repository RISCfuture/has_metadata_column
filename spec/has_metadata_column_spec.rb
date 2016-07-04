require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe HasMetadataColumn do
  describe "#has_metadata_column" do
    it "should not allow Rails-magic timestamped column names" do
      expect { SpecSupport::HasMetadataTester.has_metadata_column(created_at: {}) }.to raise_error(/timestamp/)
      expect { SpecSupport::HasMetadataTester.has_metadata_column(created_on: {}) }.to raise_error(/timestamp/)
      expect { SpecSupport::HasMetadataTester.has_metadata_column(updated_at: {}) }.to raise_error(/timestamp/)
      expect { SpecSupport::HasMetadataTester.has_metadata_column(updated_on: {}) }.to raise_error(/timestamp/)
    end

    it "should properly handle subclasses" do
      expect(SpecSupport::HasMetadataTester.metadata_column_fields).not_to include(:inherited)
      expect(SpecSupport::HasMetadataSubclass.metadata_column_fields).to include(:inherited)

      expect { SpecSupport::HasMetadataTester.new.inherited = true }.to raise_error(NoMethodError)
      sc           = SpecSupport::HasMetadataSubclass.new
      sc.inherited = true
      expect(sc.inherited).to be_truthy
      sc.untyped = 'foo'
      expect(sc.untyped).to eql('foo')
    end

    it "should not allow subclasses to redefine metadata fields" do
      expect { SpecSupport::HasMetadataSubclass.has_metadata_column(untyped: {presence: true}) }.to raise_error(/untyped/)
    end

    it "should not allow subclasses to redefine the metadata column" do
      expect { SpecSupport::HasMetadataSubclass.has_metadata_column(:other) }.to raise_error(/metadata/)
    end

    it "should allow subclasses to omit a custom metadata column"

    it "should not allow types that cannot be serialized to JSON" do
      expect { SpecSupport::HasMetadataTester.has_metadata_column(bad_type: {type: Regexp}) }.to raise_error(ArgumentError, /Regexp/)
    end
  end

  [:attribute, :attribute_before_type_cast].each do |getter|
    describe "##{getter}" do
      before(:each) { @object = SpecSupport::HasMetadataTester.new }

      it "should return a field in the metadata object" do
        @object.send :write_attribute, :metadata, {untyped: 'bar'}.to_json
        expect(@object.send(getter.to_s.sub('attribute', 'untyped'))).to eql('bar')
      end

      it "should return nil if the metadata column is nil" do
        @object.send :write_attribute, :metadata, nil
        expect(@object.send(getter.to_s.sub('attribute', 'untyped'))).to be_nil
      end

      it "should return a default if one is specified" do
        @object.send :write_attribute, :metadata, {}.to_json
        expect(@object.send(getter.to_s.sub('attribute', 'has_default'))).to eql('default')
      end

      it "should return nil if nil is stored and the default is not nil" do
        @object.send :write_attribute, :metadata, {has_default: nil}.to_json
        expect(@object.send(getter.to_s.sub('attribute', 'has_default'))).to eql(nil)
      end

      it "should not return nil if the metadata" do
        @object         = SpecSupport::HasMetadataTester.new
        @object.boolean = false
        @object.date    = Date.today
        @object.number  = 5
        @object.save!
        object = SpecSupport::HasMetadataTester.select('id').where(id: @object.id).first!
        expect(object.send(getter.to_s.sub('attribute', 'number'))).to be_nil
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
      expect(JSON.parse(@object.metadata)['untyped']).to eql('foo')
    end

    it "should merge new values into the existing hash" do
      @object.metadata = {'can_be_nil' => 'bar'}.to_json
      @object.untyped  = 'foo'
      expect(JSON.parse(@object.metadata)['untyped']).to eql('foo')
      expect(JSON.parse(@object.metadata)['can_be_nil']).to eql('bar')
    end

    it "should enforce a type if given" do
      @object.date = 'not correct'
      expect(@object).not_to be_valid
      expect(@object.errors[:date]).not_to be_empty
    end

    it "should not enforce a type if :skip_type_validation is true" do
      @object.number   = 123
      @object.no_valid = 'not correct'
      expect(@object).to be_valid
    end

    it "should cast a type if possible" do
      @object.number = "50"
      expect(@object).to be_valid
      expect(@object.number).to eql(50)

      @object.boolean = "1"
      expect(@object).to be_valid
      expect(@object.boolean).to eql(true)

      @object.boolean = "0"
      expect(@object).to be_valid
      expect(@object.boolean).to eql(false)
    end

    it "should not try to convert integer types to octal" do
      @object.number = "08"
      expect(@object).to be_valid
      expect(@object.number).to eql(8)
    end

    it "should not enforce a type if :allow_nil is given" do
      @object.can_be_nil = nil
      @object.valid? #@object.should be_valid
      expect(@object.errors[:can_be_nil]).to be_empty
    end

    it "should not enforce a type if :allow_blank is given" do
      @object.can_be_blank = ""
      @object.valid? #@object.should be_valid
      expect(@object.errors[:can_be_blank]).to be_empty
    end

    it "should set to the default if given nil and allow_blank or allow_nil are false" do
      @object.can_be_nil_with_default = nil
      expect(@object.can_be_nil_with_default).to be_nil

      @object.can_be_blank_with_default = nil
      expect(@object.can_be_blank_with_default).to be_nil

      expect(@object.cannot_be_nil_with_default).to eql(false)

      @object.cannot_be_nil_with_default = nil
      expect(@object).not_to be_valid
      expect(@object.errors[:cannot_be_nil_with_default]).not_to be_empty
    end

    it "should enforce other validations as given" do
      @object.number = 'not number'
      expect(@object).not_to be_valid
      expect(@object.errors[:number]).not_to be_empty
    end

    it "should mass-assign a multiparameter date attribute" do
      @object.attributes = {'date(1i)' => '1982', 'date(2i)' => '10', 'date(3i)' => '19'}
      expect(@object.date).to eql(Date.civil(1982, 10, 19))
    end

    it "should set a multiparam attribute to nil when the elements are nil" do
      @object.attributes = {'date(1i)' => nil, 'date(2i)' => nil, 'date(3i)' => nil}
      expect(@object.date).to be_nil
    end

    it "should set a multiparam attribute to nil when the elements are empty" do
      @object.attributes = {'date(1i)' => '', 'date(2i)' => '', 'date(3i)' => ''}
      expect(@object.date).to be_nil
    end
  end

  describe "#attribute?" do
    before(:each) { @object = SpecSupport::HasMetadataTester.new }

    context "untyped field" do
      it "should return true if the string is not blank" do
        @object.metadata = {untyped: 'foo'}.to_json
        expect(@object.untyped?).to be_truthy
      end

      it "should return false if the string is blank" do
        @object.metadata = {untyped: ' '}.to_json
        expect(@object.untyped?).to be_falsey

        @object.metadata = {untyped: ''}.to_json
        expect(@object.untyped?).to be_falsey
      end
    end

    context "numeric field" do
      it "should return true if the number is not zero" do
        @object.metadata = {number: 4}.to_json
        expect(@object.number?).to be_truthy
      end

      it "should return false if the number is zero" do
        @object.metadata = {number: 0}.to_json
        expect(@object.number?).to be_falsey
      end
    end

    context "typed, non-numeric field" do
      it "should return true if the string is not blank" do
        @object.metadata = {can_be_nil: Date.today}.to_json
        expect(@object.can_be_nil?).to be_truthy
      end

      it "should return false if the string is blank" do
        @object.metadata = {can_be_nil: nil}.to_json
        expect(@object.can_be_nil?).to be_falsey
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
      expect(@object.changes['login']).to eql([nil, 'me'])
      expect(@object.changes['untyped']).to eql(%w( foo baz ))
    end

    it "should clear changed metadata when saved" do
      @object.login   = 'me'
      @object.untyped = 'baz'
      @object.save!
      expect(@object.changes).to eql({})
    end

    it "should work when there is no associated metadata" do
      expect(SpecSupport::HasMetadataTester.new(login: 'hello').changes).to eql('login' => [nil, 'hello'])
    end

    describe "#attribute_changed?" do
      it "should work with metadata attributes" do
        @object.login   = 'me'
        @object.untyped = 'baz'
        expect(@object.login_changed?).to be_truthy
        expect(@object.untyped_changed?).to be_truthy
        @object.save!
        expect(@object.login_changed?).to be_falsey
        expect(@object.untyped_changed?).to be_falsey
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
      expect(@object.as_json).to eql(
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
      expect(@object.as_json(except: :untyped)).to eql(
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

      expect(@object.as_json(except: [:untyped, :id])).to eql(
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
      expect(@object.as_json(:only => :untyped)).to eql('untyped' => nil)

      expect(@object.as_json(:only => [:untyped, :id])).to eql(
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

      expect(@object.as_json(methods: :foo)).to eql(
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

      expect(@object.as_json(methods: [:foo, :bar])).to eql(
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
      expect(@object.to_xml).to eql(<<-XML)
<?xml version="1.0" encoding="UTF-8"?>
<has-metadata-tester>
  <id nil="true"/>
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
      expect(@object.to_xml(except: :untyped)).to eql(<<-XML)
<?xml version="1.0" encoding="UTF-8"?>
<has-metadata-tester>
  <id nil="true"/>
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

      expect(@object.to_xml(except: [:untyped, :id])).to eql(<<-XML)
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
      expect(@object.to_xml(:only => :untyped)).to eql(<<-XML)
<?xml version="1.0" encoding="UTF-8"?>
<has-metadata-tester>
  <untyped nil="true"/>
</has-metadata-tester>
      XML

      expect(@object.to_xml(:only => [:untyped, :id])).to eql(<<-XML)
<?xml version="1.0" encoding="UTF-8"?>
<has-metadata-tester>
  <id nil="true"/>
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

      expect(@object.to_xml(methods: :foo)).to eql(<<-XML)
<?xml version="1.0" encoding="UTF-8"?>
<has-metadata-tester>
  <id nil="true"/>
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

      expect(@object.to_xml(methods: [:foo, :bar])).to eql(<<-XML)
<?xml version="1.0" encoding="UTF-8"?>
<has-metadata-tester>
  <id nil="true"/>
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
      expect(@object.reload.untyped).to eql('reloaded')
    end
  end
end
