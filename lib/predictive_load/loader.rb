module PredictiveLoad
  # Predictive loader
  #
  # Usage:
  # ActiveRecord::Relation.collection_observer = LazyLoader
  #
  class Loader
    def self.observe(records)
      new(records).observe
    end

    def initialize(records)
      @records = records
    end

    def observe
      records.each do |record|
        record.collection_observer = self
      end
    end

    def loading_association(record, association)
      association_name = association.reflection.name

      if all_records_will_likely_load_association?(association_name) && supports_preload?(association)
        preload(association_name)
      end
    end

    protected

    attr_reader :records

    def all_records_will_likely_load_association?(association_name)
      if defined?(Mocha) && association_name.to_s.index('_stub_')
        false
      else
        true
      end
    end

    def supports_preload?(association)
      return false if ActiveRecord::Base.predictive_load_disabled.include?(association.klass)
      return false if association.reflection.options[:predictive_load] == false
      return false if association.reflection.options[:conditions].respond_to?(:to_proc) # rails 3 conditions proc (we do not know if it uses instance methods)
      if ActiveRecord::VERSION::MAJOR > 3 && scope = association.reflection.scope
        if scope.is_a?(Proc)
          # rails 4+ conditions block, if it uses a passed in object, we assume it is not preloadable
          return false if scope.arity.to_i > 0
        elsif where = scope.options[:where]
          # ActiveRecord::Associations::Builder::DeprecatedOptionsProc from rails 4.0 and deprecated finders
          # when conditions was a proc the where will be a proc too -> check arity
          return false if where.is_a?(Proc) && where.arity > 0
        end
      end
      true
    end

    def preload(association_name)
      if ActiveRecord::VERSION::STRING <= "4.1.0"
        ActiveRecord::Associations::Preloader.new(records_with_association(association_name), [ association_name ]).run
      else
        ActiveRecord::Associations::Preloader.new.preload(records_with_association(association_name), [ association_name ])
      end
    end

    def records_with_association(association_name)
      if mixed_collection?
        @records.select { |r| r.class.reflect_on_association(association_name) }
      else
        @records
      end
    end

    def mixed_collection?
      @mixed_collection ||= begin
        klass = records.first.class
        records.any? { |record| record.class != klass }
      end
    end
  end
end
