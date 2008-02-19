module ObjectDaddy

  def self.included(klass)
    klass.extend ClassMethods
    if defined? ActiveRecord and klass < ActiveRecord::Base
      klass.extend RailsClassMethods    
      
      class << klass
        alias_method :validates_presence_of_without_object_daddy, :validates_presence_of
        alias_method :validates_presence_of, :validates_presence_of_with_object_daddy
      end   
    end
  end
    
  module ClassMethods
    attr_accessor :exemplars_generated, :exemplar_path, :generators
    attr_reader :presence_validated_attributes
    protected :exemplars_generated=
    
    # create a valid instance of this class, using any known generators
    def generate(args = {})
      gather_exemplars unless exemplars_generated
      (generators || {}).each_pair do |handle, gen_data|
        next if args[handle]
        generator = gen_data[:generator]
        if generator[:block]
          if generator[:start]
            generator[:prev] = args[handle] = generator[:start]
            generator.delete(:start)
          else
            generator[:prev] = args[handle] = generator[:block].call(generator[:prev])
          end
        elsif generator[:method]
          args[handle] = send(generator[:method])
        elsif generator[:class]
          args[handle] = generator[:class].next
        end
      end
      if presence_validated_attributes
        req = {}
        (@presence_validated_attributes.keys - args.keys).each {|a| req[a.to_s] = true } # find attributes required by validates_presence_of not already set
        
        # NOTE: This rigamarole ensures that requiring a belongs_to association by name will just do a normal generate while
        # requiring the association by ID will do a generate-and-save (so that there is an ID).
        # This probably actually needs to be changed to always do a generate-and-save
        missing = {}
        belongs_to_associations = reflect_on_all_associations(:belongs_to).to_a
        missing[:name] = belongs_to_associations.select { |a|  req[a.name.to_s] }
        missing[:col]  = belongs_to_associations.select { |a|  req[a.primary_key_name.to_s] }
        missing[:name].each {|a| args[a.name] = a.class_name.constantize.generate }
        missing[:col].each {|a| args[a.name] = a.class_name.constantize.generate! }
      end
      new(args)
    end

    # register a generator for an attribute of this class
    # generator_for :foo do ... end
    # generator_for :foo, :class => GeneratorClass
    # generator_for :foo, :method => :method_name
    def generator_for(handle, args = {}, &block)
      raise ArgumentError, "an attribute name must be specified" unless handle = handle.to_sym
      
      if args[:method]
        raise ArgumentError, "generator method :[#{args[:method]}] is not known" unless respond_to?(args[:method].to_sym)
        record_generator_for(handle, :method => args[:method].to_sym)
      elsif args[:class]
        raise ArgumentError, "generator class [#{args[:class].name}] does not have a :next method" unless args[:class].respond_to?(:next)
        record_generator_for(handle, :class => args[:class])
      elsif block
        raise ArgumentError, "generator block must take an optional single argument" unless (-1..1).include?(block.arity)  # NOTE: lambda {} has an arity of -1, while lambda {||} has an arity of 0
        h = { :block => block }
        h[:start] = args[:start] if args[:start]
        record_generator_for(handle, h)
      else
        raise ArgumentError, "a block, :class generator, or :method generator must be specified to generator_for"
      end
    end
    
  protected
    
    def gather_exemplars
      if superclass.respond_to?(:gather_exemplars)
        superclass.gather_exemplars
        self.generators = (superclass.generators || {}).dup
      end
      
      path = File.join(exemplar_path, "#{underscore(name)}_exemplar.rb")
      load(path) if File.exists?(path)
      self.exemplars_generated = true
    end
    
    # we define an underscore helper ourselves since the ActiveSupport isn't available if we're not using Rails
    def underscore(string)
      string.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
    end
    
    def record_generator_for(handle, generator)
      self.generators ||= {}
      raise ArgumentError, "a generator for attribute [:#{handle}] has already been specified" if (generators[handle] || {})[:source] == self
      generators[handle] = { :generator => generator, :source => self }
    end
  end
  
  module RailsClassMethods
    def exemplar_path
      File.join(RAILS_ROOT, 'test', 'exemplars')
    end
    
    def validates_presence_of_with_object_daddy(*attr_names)
      @presence_validated_attributes ||= {}
      new_attr = attr_names.dup
      new_attr.pop if new_attr.last.is_a?(Hash)
      new_attr.each {|a| @presence_validated_attributes[a] = true }
      validates_presence_of_without_object_daddy(*attr_names)
    end
    
    def generate!(args = {})
      obj = generate(args)
      obj.save!
      obj
    end
  end
end
