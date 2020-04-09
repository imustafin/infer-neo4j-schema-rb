require 'json'
require 'set'
require 'pp'

def labels_keys_from_line(s)
  JSON.parse("[#{s}]")
end

class PropClass
  attr_reader :name, :properties, :records, :abstract, :interface, :parents

  def initialize(name)
    @name = name

    # @properties[i] = i is always present?
    @properties = Hash.new

    @records = 0

    @interface = interface

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

  def plantuml_classifier
    'class'
  end

  def as_plantuml_class
    properties = @properties
                   .keys
                   .map { |x| property_as_plantuml(x) }
                   .sort
                   .join("\n")

    parent_arrows = parents
                      .map { |parent| "\"#{parent.name}\" <|-- \"#{@name}\"" }
                      .join("\n")

    <<~PLANTUML
      #{plantuml_classifier} "#{name}" {
        #{properties}
      }
      #{parent_arrows}
    PLANTUML
  end

  def to_s
    "(C: #{@name})"
  end
end

class Interface < PropClass
  @@num = 0
  def initialize
    @@num += 1
    super(@@num.to_s)
  end

  def plantuml_classifier
    'interface'
  end

  def to_s
    "(I: #{@name})"
  end
end

def class_from(class_name, class_col)
  cls = class_col.fetch(class_name, PropClass.new(class_name))
  class_col[class_name] = cls
  cls
end

concrete_classes = {}

props = Set.new

ARGF.each_line do |line|
  next if ARGF.lineno == 1

  labels, keys = labels_keys_from_line(line)

  props.merge(keys)

  concrete_label = labels.join(':')

  class_from(concrete_label, concrete_classes).add_properties(keys)
end

somehow_groups = props.group_by do |prop|
  concrete_classes.values.select do |cls|
    cls.properties.key?(prop)
  end
end

interfaces = []

somehow_groups.each do |children, props|
  next if children.length <= 1 or props.empty?

  present_groups = props.group_by do |x|
    children.all? { |child| child.properties[x] }
  end

  pres_props = present_groups[true] || []
  maybe_props = present_groups[false] || []

  group_cls = Interface.new
  group_cls.add_properties(pres_props)
  group_cls.add_properties(pres_props + maybe_props)
  interfaces << group_cls

  children.each do |x|
    x.parents << group_cls

    x.properties.keys.each do |prop|
      if x.properties[prop] && maybe_props.include?(prop)
        cls = Interface.new
        cls.add_properties([prop] + pres_props)
        cls.add_properties([prop] + pres_props + maybe_props)

        x.parents << cls
        x.parents.delete(group_cls)
        cls.parents << group_cls
        interfaces << cls
      end
    end
  end
end

# Uniq interfaces
interfaces.group_by { |x| x.properties }.each do |props, group|
  next if group.length < 2


  children = concrete_classes.values.select { |child| (child.parents & group).any? }

  cls = group.shift

  interfaces.reject! { |i| group.include?(i) }

  children.each do |child|
    child.parents.reject! { |parent| group.include?(parent) }
    child.parents << cls
  end
end


same_ifs = interfaces.group_by do |i|
  concrete_classes.values.select { |x| x.parents.include?(i) }
end

same_ifs.each do |children, group|
  next if group.length <= 1 || children.length <= 1

  props = group.map { |x| x.properties.keys }.flatten
  pres_props = props.select do |prop|
    group.any? { |x| x.properties[prop] }
  end

  cls = Interface.new
  cls.add_properties(pres_props)
  cls.add_properties(pres_props + props)
  cls.parents.concat(group)
  interfaces << cls

  children.each do |child|
    child.parents.reject! { |x| group.include?(x) }

    child.parents << cls
  end
end

all_classes = interfaces + concrete_classes.values

puts "@startuml"
all_classes.each do |cls|
  puts cls.as_plantuml_class
end
puts "@enduml"
