#
# Represents the content for a particular:
#
#   content_key
#   language
#   country
#   brand
#   application
#   mime_type
#
# Actual content is stored in Content#data.
#
class Content < ActiveRecord::Base
  include ContentModel

  # Base Content::Error class.
  class Error < ::Exception
    # Raised when an edit is attempted on a version that is older.
    class Conflict < self; end
    # Raised when an edit is attempted on a based on an ambiguous lookup.
    class Ambiguous < self; end
  end

  USE_VERSION = true unless defined? USE_VERSION
  if USE_VERSION 
    acts_as_versioned
    set_locking_column :version
  end

  BELONGS_TO =
    [
     :content_key,
     :language,
     :country,
     :brand,
     :application,
     :mime_type,
    ].freeze
  BELONGS_TO_ID =
    BELONGS_TO.map { | x | "#{x}_id".to_sym }.freeze

  BELONGS_TO.each do | x |
    belongs_to x
    validates_presence_of x
  end
  
  FIND_COLUMNS =
    ([ :id, :uuid, :version, :content_type, :data ] + BELONGS_TO).freeze

  EQUAL_COLUMNS =
    ([ :uuid, :version, :data ] + BELONGS_TO_ID).freeze

=begin
  validates_uniqueness_of :content_key, 
    :scope => BELONGS_TO_ID
=end

  def content_type
    @content_type ||= content_key.content_type
  end

  def key
    content_key.code
  end

  def key= x
    @key = x
  end


  ####################################################################
  # View/Controller helpers
  #


  def content_type_id
    (x = content_key) &&
      (x = x.content_type) &&
      x.id
  end

  def content_type_id= x
    @content_type = ContentType[x.to_i]
  end

  def content_type_code
    (x = content_key) &&
      (x = x.content_type) &&
      x.code
  end

  def content_type_code= x
    @content_type = ContentType[x.to_s]
  end

  def content_key_code
    (x = content_key) &&
      x.code
  end

  def content_key_code= x
    @content_key_code = x
  end



  before_validation :normalize_content_key!
  def normalize_content_key!
    if @content_type && @content_key_code
      # $stderr.puts "  normalize_content_key! #{self.inspect}"
      self.content_key = ContentKey.create_from_hash(:content_key => @content_key_code, :content_type_id => @content_type.id)
      @content_type = @content_key_code = nil
      $stderr.puts "normalized to content_key #{@content_key.inspect}"
    end
  end


  ####################################################################
  # Query support.
  #


  def self.find_column_names
    FIND_COLUMNS
  end


  def self.find_by_params opt, params, opts = EMPTY_HASH
    sql = <<"END"
SELECT #{table_name}.* 
FROM #{table_name}, #{BELONGS_TO.map{|x| x.to_s.pluralize} * ', '}, content_types
WHERE
    #{BELONGS_TO.map{|x| "(#{x.to_s.pluralize}.id = contents.#{x}_id)"} * "\nAND "}
AND (content_types.id = content_keys.content_type_id)
END

    # Construct find :conditions.
    find_column_names.each do | column |
      if params.key?(column)
        value = params[column]
        field = 
          case column 
          when :id 
            'contents.id'
          when :version
            'contents.version'
          when :uuid
            'contents.uuid'
          when :content_key_uuid
            'content_keys.uuid'
          when :data
            'contents.data'
          else 
            "#{column.to_s.pluralize}.code"
          end
 
        # Coerce value.
        case value
        when Symbol
          value = value.to_s
        when Regexp
          value = value.inspect
        when String
          value = value
        when ActiveRecord::Base
          value = value.code rescue value.id
        end

        # $stderr.puts "#{column} = #{value.inspect}"

        # Handle meta values.
        case
          # Match NULL
        when value == 'NULL'
          field += ' IS NULL'

          # Match !NULL
        when value == '!NULL'
          field += ' IS NOT NULL'

          # Match Regexp
        when value =~ /^\/(.*)\/$/
          value = $1
          field += ' ~ %s'

          # Match not Regexp
        when value =~ /^!\/(.*)\/$/
          value = $1
          field += ' !~ %s'

          # Match not String.
        when (value = value.dup) && value.sub!(/\A!/, '')
          field = "#{field} IS NULL OR #{field} <> %s"

          # Relational:
        when (value = value.dup) && value.sub!(/\A(<|>|<=|>=|=)/, '')
          field += ' ' + $1 + ' %s'

          # Match exact.
        else
          field += ' = %s'
        end

        case column
        when :version
          value = value.to_i
        end

        sql << "\nAND (#{field % Content.connection.quote(value)})"
      end
    end

    case opt
    when :first
      sql << "\nLIMIT 1"
    end
    case
    when opts[:limit]
      sql << "\nLIMIT #{opts[:limit]}"
    end

    # $stderr.puts "  sql =\n #{sql}"

    result = 
      Content.
      find_by_sql(sql)

    case opt
    when :first
      result = result.first
    end

    result
  end


  def is_equal_to_hash? hash
    EQUAL_COLUMNS.all? do | k | 
      ks = k.to_s
      case v = hash[k]
      when ActiveRecord::Base
        v = v.id
      end
      ! hash.key?(k) || (self.send(k) == hash[k])
    end
  end


  def to_hash
    result = { :id => id, :uuid => uuid, :data => data }
    if USE_VERSION 
      result[:version] = version
    end

    BELONGS_TO.each do | x |
      v = send(x)
      if v
        v.add_to_hash(result)
      else
        result[x] = '_'
      end
    end
    result
  end


  def self.load_from_hash hash
    hash = hash.dup

    if v = hash[:key]
      hash[:content_key] = v
      hash.delete(:key)
    end

    obj = nil

    # Try to locate by id or uuid first.
    [ :id, :uuid ].each do | key |
      obj = hash[key] && find_by_params(:first, key => hash[key])
      break if obj
    end

    # Try to locate by all other params.
    unless obj 
      params = hash.dup
      params.delete(:data)
      obj = find_by_params(:all, params, :limit => 2)
      if obj.size > 1 
        raise Content::Error::Ambiguous, "Search by #{params.inspect} is ambiguous"
      end
      obj = obj.first
    end

    action = nil

    if obj 
      hash = normalize_hash(hash)

      # Check version.
      if hash[:version] && hash[:version].to_s != obj.version
        raise Content::Error::Collision, "Content uuid #{obj.uuid}: edit of version #{hash[:version]} of which is now version #{obj.version}"
      end

      # $stderr.puts "  UPDATE: load_from_hash(#{hash.inspect})"
      if obj.is_equal_to_hash? hash
        $stderr.write "."
      else
        $stderr.write "*"
        $stderr.puts "\n  #{obj.to_hash.inspect}"
        obj.attributes = hash
        obj.save!
        action = :save
      end
    else
      hash = normalize_hash(hash)
      # $stderr.puts "  CREATE: load_from_hash(#{hash.inspect})"
      $stderr.write "+"
      obj = self.create(hash)
      raise ArgumentError, "#{obj.errors.to_s}" unless obj.errors.empty?
      action = :create
    end
    obj
  end


  def self.load_from_yaml! yaml
    result = YAML::load(yaml)
    columns = result[:result_columns]
    self.transaction do 
      result[:results].map do | r |
        i = -1
        hash = columns.inject({ }) do | h, k |
          h[k] = r[i += 1]
          h
        end
        hash.delete(:id)
        load_from_hash hash
      end
    end
  end


  def self.normalize_hash hash
    result = hash.dup

    BELONGS_TO.each do | column |
      # $stderr.puts "normalize #{column.inspect}"
      cls = Object.const_get(column.to_s.classify)
      obj = cls.create_from_hash(hash)
      result[column] = obj
    end
    # content_type is handled via content_key.
    result.delete(:content_type)

    result
  end


  before_save :default_selectors!

  EMPTY_HASH = { }.freeze

  def default_selectors!
    hash = to_hash
    BELONGS_TO.each do | column |
      next if self.send(column)
      cls = Object.const_get(column.to_s.classify)
      obj = cls[hash]
      self.send("#{column}=", obj) if obj
    end
  end

  before_save :initialize_uuid!
  def initialize_uuid!
    self.uuid ||= Contenter::UUID.generate_random
  end

end

