# frozen_string_literal: true

require "active_support/inflector/methods"
require "active_support/dependencies"

class BasicObject
  alias_method :send_keyword_hash, :__send__ unless respond_to?(:send_keyword_hash)
end

class Module
  unless respond_to?(:ruby2_keywords, true)
    def self.ruby2_keywords(*)
    end
  end
end

module ActionDispatch
  class MiddlewareStack
    class Middleware
      attr_reader :args, :block, :klass

      def initialize(klass, args, block)
        @klass = klass
        @args  = args
        @block = block
      end

      def name; klass.name; end

      def ==(middleware)
        case middleware
        when Middleware
          klass == middleware.klass
        when Class
          klass == middleware
        end
      end

      def inspect
        if klass.is_a?(Class)
          klass.to_s
        else
          klass.class.to_s
        end
      end

      def build(app)
        klass.send_keyword_hash(:new, app, *args, &block)
      end

      def build_instrumented(app)
        InstrumentationProxy.new(build(app), inspect)
      end
    end

    # This class is used to instrument the execution of a single middleware.
    # It proxies the `call` method transparently and instruments the method
    # call.
    class InstrumentationProxy
      EVENT_NAME = "process_middleware.action_dispatch"

      def initialize(middleware, class_name)
        @middleware = middleware

        @payload = {
          middleware: class_name,
        }
      end

      def call(env)
        ActiveSupport::Notifications.instrument(EVENT_NAME, @payload) do
          @middleware.call(env)
        end
      end
    end

    include Enumerable

    attr_accessor :middlewares

    def initialize(*args)
      @middlewares = []
      yield(self) if block_given?
    end

    def each
      @middlewares.each { |x| yield x }
    end

    def size
      middlewares.size
    end

    def last
      middlewares.last
    end

    def [](i)
      middlewares[i]
    end

    ruby2_keywords def unshift(klass, *args, &block)
      middlewares.unshift(build_middleware(klass, args, block))
    end

    def initialize_copy(other)
      self.middlewares = other.middlewares.dup
    end

    ruby2_keywords def insert(index, klass, *args, &block)
      index = assert_index(index, :before)
      middlewares.insert(index, build_middleware(klass, args, block))
    end

    alias_method :insert_before, :insert

    ruby2_keywords def insert_after(index, *args, &block)
      index = assert_index(index, :after)
      insert(index + 1, *args, &block)
    end

    ruby2_keywords def swap(target, *args, &block)
      index = assert_index(target, :before)
      insert(index, *args, &block)
      middlewares.delete_at(index + 1)
    end

    def delete(target)
      middlewares.delete_if { |m| m.klass == target }
    end

    ruby2_keywords def use(klass, *args, &block)
      middlewares.push(build_middleware(klass, args, block))
    end

    def build(app = nil, &block)
      instrumenting = ActiveSupport::Notifications.notifier.listening?(InstrumentationProxy::EVENT_NAME)
      middlewares.freeze.reverse.inject(app || block) do |a, e|
        if instrumenting
          e.build_instrumented(a)
        else
          e.build(a)
        end
      end
    end

    private
      def assert_index(index, where)
        i = index.is_a?(Integer) ? index : middlewares.index { |m| m.klass == index }
        raise "No such middleware to insert #{where}: #{index.inspect}" unless i
        i
      end

      def build_middleware(klass, args, block)
        Middleware.new(klass, args, block)
      end
  end
end
