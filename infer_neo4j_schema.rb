require 'json'
require 'set'
require 'pp'

def labels_keys_from_line(s)
  JSON.parse("[#{s}]")
end

class Class
  attr_reader :name, :properties, :records, :abstract
  attr_accessor :parents

  def initialize(name, abstract: false)
    @name = name

    # @properties[i] = i is always present?
    @properties = Hash.new

    @records = 0

    @abstract = abstract

    @parents = []
  end

  def add_properties(properties)
    if @records == 0
      properties.each do |p|
        @properties[p] = true
      end
    else
      new_and_missed = properties.to_set ^ @properties.keys

      new_and_missed.each do |p|
        @properties[p] = false
      end
    end

    @records += 1
  end

  def property_as_plantuml(property)
    ans = property
    ans = ans + '?' unless @properties[property]

    inherited = parents.any? { |x| x.properties.keys.any? { |y| y == property } }
    ans = '^' + ans if inherited

    ans
  end

  def as_plantuml_class
    properties = @properties
                   .keys
                   .map { |x| property_as_plantuml(x) }
                   .sort
                   .join("\n")

    "#{abstract ? 'abstract' : ''} class \"#{@name}\" { \n #{properties} \n }"
  end

  def to_s
    "(#{@name})"
  end
end

def class_from(class_name, class_col)
  cls = class_col.fetch(class_name, Class.new(class_name))
  class_col[class_name] = cls
  cls
end

concrete_classes = {}
per_label_classes = {}

props = Set.new

ARGF.each_line do |line|
  next if ARGF.lineno == 1

  labels, keys = labels_keys_from_line(line)

  props.merge(keys)

  concrete_label = labels.join(':')

  class_from(concrete_label, concrete_classes).add_properties(keys)

  labels.each { |x| class_from(x, per_label_classes).add_properties(keys) }
end

# Extract non-nulls to separate classes

non_null_classes = []

prop_groups = props.group_by do |prop|
  concrete_classes.values.select { |cls| cls.properties[prop] }
end

prop_groups.each do |having, props|
  next if props.empty? || having.length < 2

  cls = Class.new("Having: #{props.join(' ')}", abstract: true)
  cls.add_properties(props)

  having.each do |h|
    h.parents << cls
  end

  non_null_classes << cls
end

puts "@startuml"
concrete_classes.each do |name, cls|
  puts cls.as_plantuml_class  

  cls.parents.each do |parent|
    puts "\"#{parent.name}\" <|-- \"#{cls.name}\""
  end
end

non_null_classes.each do |cls|
  puts cls.as_plantuml_class
end
puts "@enduml"
