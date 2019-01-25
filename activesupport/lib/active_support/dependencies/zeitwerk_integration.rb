module ActiveSupport
  module Dependencies
    module ZeitwerkIntegration
      module Decorations
        def clear
          Dependencies.unload_interlock do
            Rails.autoloader.reload
          end
        end

        def constantize(cpath)
          Inflector.constantize(cpath)
        end

        def safe_constantize(cpath)
          Inflector.safe_constantize(cpath)
        end

        def autoloaded_constants
          Rails.autoloader.loaded.to_a
        end

        def autoloaded?(object)
          cpath = object.is_a?(Module) ? object.name : object.to_s
          Rails.autoloader.loaded?(cpath)
        end
      end

      def self.take_over
        (Dependencies.autoload_paths - Dependencies.autoload_once_paths).each do |path|
          Rails.autoloader.push_dir(path) if File.directory?(path)
        end
        Rails.autoloader.setup

        once_loader = Zeitwerk::Loader.new
        Dependencies.autoload_once_paths.each do |path|
          once_loader.push_dir(path) if File.directory?(path)
        end
        once_loader.setup

        Dependencies.autoload_paths.freeze
        Dependencies.autoload_once_paths.freeze

        Object.class_eval { alias_method :require_dependency, :require }
        Dependencies.singleton_class.prepend(Decorations)
      end
    end
  end
end
