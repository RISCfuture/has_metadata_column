require 'boolean'

# @private
class Object

  # Creates a deep copy of this object.
  #
  # @raise [TypeError] If the object cannot be deep-copied. All objects that can
  #   be marshalled can be deep-copied.

  def deep_clone
    Marshal.load Marshal.dump(self)
  end
end

# Provides the {ClassMethods#has_metadata_column} method to subclasses of
# `ActiveRecord::Base`.

module HasMetadataColumn
  extend ActiveSupport::Concern

  included do
    after_save :_reset_metadata, prepend: true
  end

  # Valid values for the `:type` option.
  TYPES = [String, Fixnum, Integer, Float, Hash, Array, TrueClass, FalseClass, Boolean, NilClass, Date, Time]

  # @private
  def self.metadata_typecast(value, type=nil)
    type ||= String
    raise ArgumentError, "Can't convert objects of type #{type.to_s}" unless TYPES.include?(type)

    if value.kind_of?(String) then
      if type == Integer or type == Fixnum then
        begin
          return Integer(value.sub(/^0+/, '')) # so that it doesn't think it's in octal
        rescue ArgumentError
          return value
        end
      elsif type == Float then
        begin
          return Float(value)
        rescue ArgumentError
          return value
        end
      elsif type == Boolean then
        return value.parse_bool
      elsif type == Date then
        return nil if value.nil?
        begin
          return Date.parse(value)
        rescue ArgumentError
          return value
        end
      elsif type == Time then
        return nil if value.nil?
        begin
          return Time.parse(value)
        rescue ArgumentError
          return value
        end
      end
    end
    return value
  end

  # Class methods that are added to your model.

  module ClassMethods

    # Defines a set of fields whose values exist in the JSON metadata column.
    # Each key in the `fields` hash is the name of a metadata field, and the
    # value is a set of options to pass to the `validates` method. If you do not
    # want to perform any validation on a field, simply pass `true` as its key
    # value.
    #
    # In addition to the normal `validates` keys, you can also include a `:type`
    # key to restrict values to certain classes, or a `:default` key to specify
    # a value to return for the getter should none be set (normal default is
    # `nil`). See {TYPES} for a list of valid values.
    #
    # @overload has_metadata_column(column, fields)
    #   @param [Symbol] column (:metadata) The column containing the metadata
    #     information.
    #   @param [Hash<Symbol, Hash>] fields A mapping of field names to their
    #     validation options (and/or the `:type` key).
    # @raise [ArgumentError] If invalid arguments are given, or an invalid
    #   class for the `:type` key.
    # @raise [StandardError] If invalid field names are given (see source).
    #
    # @example Three metadata fields, one basic, one validated, and one type-checked.
    #   has_metadata_column(optional: true, required: { presence: true }, number: { type: Fixnum })

    def has_metadata_column(*args)
      fields = args.extract_options!
      column = args.shift

      raise ArgumentError, "has_metadata_column takes a column name and a hash of fields" unless args.empty?
      raise "Can't define Rails-magic timestamped columns as metadata" if Rails.version >= '3.2.0' && (fields.keys & [:created_at, :created_on, :updated_at, :updated_on]).any?
      classes = fields.values.select { |o| o[:type] && !TYPES.include?(o[:type]) }
      raise ArgumentError, "#{classes.to_sentence} cannot be serialized to JSON" if classes.any?

      if !respond_to?(:metadata_column_fields) then
        class_attribute :metadata_column_fields
        self.metadata_column_fields = fields.deep_clone
        class_attribute :metadata_column
        self.metadata_column = column || :metadata

        alias_method_chain :changed_attributes, :metadata_column
        alias_method_chain :attribute_will_change!, :metadata_column
        alias_method_chain :attribute_method?, :metadata
        alias_method_chain :attribute, :metadata
        alias_method_chain :attribute_before_type_cast, :metadata
        alias_method_chain :attribute=, :metadata
        alias_method_chain :query_attribute, :metadata
      else
        raise "Cannot redefine existing metadata column #{self.metadata_column}" if column && column != self.metadata_column
        if metadata_column_fields.slice(*fields.keys) != fields
          raise "Cannot redefine existing metadata fields: #{(fields.keys & self.metadata_column_fields.keys).to_sentence}" unless (fields.keys & self.metadata_column_fields.keys).empty?
          self.metadata_column_fields = self.metadata_column_fields.merge(fields)
        end
      end

      fields.each do |name, options|
        if options.kind_of?(Hash) then
          type          = options.delete(:type)
          type_validate = !options.delete(:skip_type_validation)
          options.delete :default

          validate do |obj|
            value = obj.send(name)
            if !HasMetadataColumn.metadata_typecast(value, type).kind_of?(type) &&
                (!options[:allow_nil] || (options[:allow_nil] && !value.nil?)) &&
                (!options[:allow_blank] || (options[:allow_blank] && !value.blank?))
              errors.add(name, :incorrect_type)
            end
          end if type && type_validate
          validates(name, options) unless options.empty? or (options.keys - [:allow_nil, :allow_blank]).empty?
        end
      end

      class << self
        def define_attribute_methods
          super
          metadata_column_fields.keys.each { |field| define_attribute_method field.to_s }
        end

        def define_method_attribute(attr_name)
          return super unless metadata_column_fields.include?(attr_name.to_sym)
          generated_attribute_methods.module_eval <<-RUBY, __FILE__, __LINE__ + 1
            def __temp__#{attr_name}
              options = self.class.metadata_column_fields[:#{attr_name}] || {}
              default = options.include?(:default) ? options[:default] : nil
              _metadata_hash.include?('#{attr_name}') ? HasMetadataColumn.metadata_typecast(_metadata_hash['#{attr_name}'], options[:type]) : default
            end
          RUBY
        end

        def define_method_attribute=(attr_name)
          return super unless metadata_column_fields.include?(attr_name.to_sym)
          generated_attribute_methods.module_eval <<-RUBY, __FILE__, __LINE__ + 1
            def __temp__#{attr_name}=(value)
              return value if _metadata_hash.include?(attr_name.to_s) && value == _metadata_hash[attr_name.to_s]
              attribute_will_change! :#{attr_name}
              old = _metadata_hash['#{attr_name}']
              send (self.class.metadata_column + '='), _metadata_hash.merge('#{attr_name}' => value).to_json
              @_metadata_hash          = nil
              @_changed_metadata[attr] = old
              value
            end
          RUBY
        end
      end
    end
  end

  # @private
  def as_json(options={})
    options          ||= Hash.new # the JSON encoder can sometimes give us nil options?
    options[:except] = Array.wrap(options[:except]) + [self.class.metadata_column]
    metadata         = self.class.metadata_column_fields.keys
    metadata &= Array.wrap(options[:only]) if options[:only]
    metadata          -= Array.wrap(options[:except])
    options[:methods] = Array.wrap(options[:methods]) + metadata
    super options
  end

  # @private
  def to_xml(options={})
    options[:except] = Array.wrap(options[:except]) + [self.class.metadata_column]
    metadata         = self.class.metadata_column_fields.keys
    metadata &= Array.wrap(options[:only]) if options[:only]
    metadata          -= Array.wrap(options[:except])
    options[:methods] = Array.wrap(options[:methods]) + metadata
    super options
  end

  # @private
  def assign_multiparameter_attributes(pairs)
    fake_attributes = pairs.select { |(field, _)| self.class.metadata_column_fields.include? field[0, field.index('(')].to_sym }

    fake_attributes.group_by { |(field, _)| field[0, field.index('(')] }.each do |field_name, parts|
      options = self.class.metadata_column_fields[field_name.to_sym]
      if options[:type] then
        args = parts.each_with_object([]) do |(part_name, value), ary|
          part_ann = part_name[part_name.index('(') + 1, part_name.length]
          index    = part_ann.to_i - 1
          raise "Out-of-bounds multiparameter argument index" unless index >= 0
          ary[index] = if value.blank? then
                         nil
                       elsif part_ann.ends_with?('i)') then
                         value.to_i
                       elsif part_ann.ends_with?('f)') then
                         value.to_f
                       else
                         value
                       end
        end
        send :"#{field_name}=", args.any? ? options[:type].new(*args) : nil
      else
        raise "#{field_name} has no type and cannot be used for multiparameter assignment"
      end
    end

    super(pairs - fake_attributes)
  end

  # @private
  def inspect
    "#<#{self.class.to_s} #{attributes.except(self.class.metadata_column.to_s).merge(_metadata_hash.try!(:stringify_keys) || {}).map { |k, v| "#{k}: #{v.inspect}" }.join(', ')}>"
  end

  # @private
  def reload(*)
    super.tap do
      @_metadata_hash    = nil
      _reset_metadata
    end
  end

  private

  def changed_attributes_with_metadata_column
    changed_attributes_without_metadata_column.merge(_changed_metadata)
  end

  def attribute_will_change_with_metadata_column!(attr)
    unless attribute_names.include?(attr)
      send :"#{self.class.metadata_column}_will_change!"
    end
    attribute_will_change_without_metadata_column! attr
  end

  def _metadata_hash
    @_metadata_hash ||= begin
      send(self.class.metadata_column) ? JSON.parse(send(self.class.metadata_column)) : {}
    rescue ActiveModel::MissingAttributeError
      {}
    end
  end

  def _changed_metadata
    @_changed_metadata ||= {}
  end

  ## ATTRIBUTE MATCHER METHODS

  def attribute_with_metadata(attr)
    return attribute_without_metadata(attr) unless self.class.metadata_column_fields.include?(attr.to_sym)

    options = self.class.metadata_column_fields[attr.to_sym] || {}
    default = options.include?(:default) ? options[:default] : nil
    _metadata_hash.include?(attr) ? HasMetadataColumn.metadata_typecast(_metadata_hash[attr], options[:type]) : default
  end

  def attribute_before_type_cast_with_metadata(attr)
    return attribute_before_type_cast_without_metadata(attr) unless self.class.metadata_column_fields.include?(attr.to_sym)
    options = self.class.metadata_column_fields[attr.to_sym] || {}
    default = options.include?(:default) ? options[:default] : nil
    _metadata_hash.include?(attr) ? _metadata_hash[attr] : default
  end

  def _attribute_with_metadata(attr)
    return _attribute_without_metadata(attr) unless self.class.metadata_column_fields.include?(attr.to_sym)
    attribute_with_metadata attr
  end

  def attribute_with_metadata=(attr, value)
    return send(:attribute_without_metadata=, attr, value) unless self.class.metadata_column_fields.include?(attr.to_sym)
    return value if _metadata_hash.include?(attr.to_s) && value == _metadata_hash[attr.to_s]

    attribute_will_change! attr
    old = _metadata_hash[attr.to_s]
    send :"#{self.class.metadata_column}=", _metadata_hash.merge(attr.to_s => value).to_json
    @_metadata_hash          = nil
    @_changed_metadata[attr] = old
    value
  end

  def query_attribute_with_metadata(attr)
    return query_attribute_without_metadata(attr) unless self.class.metadata_column_fields.include?(attr.to_sym)
    return false unless (value = send(attr))
    options = self.class.metadata_column_fields[attr.to_sym] || {}
    type    = options[:type] || String
    return !value.to_i.zero? if type.ancestors.include?(Numeric)
    return !value.blank?
  end

  def attribute_method_with_metadata?(attr)
    self.class.metadata_column_fields.include?(attr.to_sym) || attribute_method_without_metadata?(attr)
  end

  def _reset_metadata
    @_changed_metadata = {}
  end
end
