require 'cgi'
require 'active_record'

require 'activerecord/tablefree/version'
require 'activerecord/tablefree/cast_type'
require 'activerecord/tablefree/schema_cache'
require 'activerecord/tablefree/connection'
require 'activerecord/tablefree/transaction'

module ActiveRecord
  # = ActiveRecord::Tablefree
  #
  # Allow classes to behave like ActiveRecord models, but without an associated
  # database table. A great way to capitalize on validations. Based on the
  # original post at http://www.railsweenie.com/forums/2/topics/724 (which seems
  # to have disappeared from the face of the earth).
  #
  # = Example usage
  #
  #  class ContactMessage < ActiveRecord::Base
  #
  #    has_no_table
  #
  #    column :name,    :string
  #    column :email,   :string
  #    column :message, :string
  #
  #  end
  #
  #  msg = ContactMessage.new( params[:msg] )
  #  if msg.valid?
  #    ContactMessageSender.deliver_message( msg )
  #    redirect_to :action => :sent
  #  end
  #
  module Tablefree
    class NoDatabase < StandardError; end
    class Unsupported < StandardError; end
    class InvalidColumnType < ArgumentError; end

    def self.included(base) #:nodoc:
      base.send :extend, ActsMethods
    end

    module ActsMethods #:nodoc:
      # A model that needs to be tablefree will call this method to indicate
      # it.
      def has_no_table(options = { database: :fail_fast })
        raise ArgumentError, "Invalid database option '#{options[:database]}'" unless %i[fail_fast pretend_success].member? options[:database]
        # keep our options handy
        class_attribute :tablefree_options
        self.tablefree_options = {
          database: options[:database],
          columns_hash: {}
        }

        # extend
        extend  ActiveRecord::Tablefree::SingletonMethods
        extend  ActiveRecord::Tablefree::ClassMethods

        # include
        include ActiveRecord::Tablefree::InstanceMethods

        # setup columns
        include ActiveModel::AttributeAssignment
        include ActiveRecord::ModelSchema
      end

      def tablefree?
        false
      end
    end

    module SingletonMethods
      # Used internally by ActiveRecord 5.  This is the special hook that makes everything else work.
      def load_schema!
        @columns_hash = tablefree_options[:columns_hash].except(*ignored_columns)
        @columns_hash.each do |name, column|
          define_attribute(
            name,
            column.sql_type_metadata,
            default: column.default,
            user_provided_default: false
          )
        end
      end

      # Register a new column.
      def column(name, sql_type = nil, default = nil, null = true, cast_class_params = nil)
        cast_class = if sql_type.is_a?(Class) && sql_type < ActiveModel::Type::Value
                       sql_type
                     else
                       "ActiveRecord::Type::#{sql_type.to_s.camelize}".constantize rescue nil
                     end
        raise InvalidColumnType, "sql_type is #{sql_type} (#{sql_type.class}), which is not supported" unless cast_class.respond_to?(:new)
        cast_type = cast_class.new(*cast_class_params)
        tablefree_options[:columns_hash][name.to_s] = ActiveRecord::ConnectionAdapters::Column.new(name.to_s, default, cast_type, null)
      end

      # Register a set of columns with the same SQL type
      def add_columns(sql_type, *args)
        args.each do |col|
          column col, sql_type
        end
      end

      def destroy(*_args)
        case tablefree_options[:database]
        when :pretend_success
          new
        when :fail_fast
          raise NoDatabase, "Can't #destroy on Tablefree class"
        end
      end

      def destroy_all(*_args)
        case tablefree_options[:database]
        when :pretend_success
          []
        when :fail_fast
          raise NoDatabase, "Can't #destroy_all on Tablefree class"
        end
      end

      case ActiveRecord::VERSION::MAJOR
      when 5
        def find_by_sql(*_args)
          case tablefree_options[:database]
          when :pretend_success
            []
          when :fail_fast
            raise NoDatabase, "Can't #find_by_sql on Tablefree class"
          end
        end
      else
        raise Unsupported, 'Unsupported ActiveRecord version'
      end

      def transaction
        #        case tablefree_options[:database]
        #        when :pretend_success
        @_current_transaction_records ||= []
        yield
        #        when :fail_fast
        #          raise NoDatabase.new("Can't #transaction on Tablefree class")
        #        end
      end

      def tablefree?
        true
      end

      def table_exists?
        false
      end
    end

    module ClassMethods
      def from_query_string(query_string)
        if query_string.blank?
          new
        else
          params = query_string.split('&').collect do |chunk|
            next if chunk.empty?
            key, value = chunk.split('=', 2)
            next if key.empty?
            value = value.nil? ? nil : CGI.unescape(value)
            [CGI.unescape(key), value]
          end.compact.to_h

          new(params)
        end
      end

      def connection
        @_connection ||= ActiveRecord::Tablefree::Connection.new
      end
    end

    module InstanceMethods
      def to_query_string(prefix = nil)
        attributes.to_a.collect { |(name, value)| escaped_var_name(name, prefix) + '=' + escape_for_url(value) if value }.compact.join('&')
      end

      def quote_value(_value, _column = nil)
        ''
      end

      %w[create create_record _create_record update update_record _update_record].each do |method_name|
        define_method(method_name) do |*_args|
          case self.class.tablefree_options[:database]
          when :pretend_success
            true
          when :fail_fast
            raise NoDatabase, "Can't ##{method_name} a Tablefree object"
          end
        end
      end

      def destroy
        case self.class.tablefree_options[:database]
        when :pretend_success
          @destroyed = true
          freeze
        when :fail_fast
          raise NoDatabase, "Can't #destroy a Tablefree object"
        end
      end

      def reload(*_args)
        case self.class.tablefree_options[:database]
        when :pretend_success
          self
        when :fail_fast
          raise NoDatabase, "Can't #reload a Tablefree object"
        end
      end

      def add_to_transaction; end

      private

      def escaped_var_name(name, prefix = nil)
        prefix ? "#{CGI.escape(prefix)}[#{CGI.escape(name)}]" : CGI.escape(name)
      end

      def escape_for_url(value)
        case value
        when true then '1'
        when false then '0'
        when nil then ''
        else CGI.escape(value.to_s)
        end
      rescue
        ''
      end
    end
  end
end

ActiveRecord::Base.send(:include, ActiveRecord::Tablefree)
