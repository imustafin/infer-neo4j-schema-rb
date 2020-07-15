require 'json'
require 'set'
require 'pp'
require 'csv'
require 'optparse'

def labels_keys_from_line(s)
  JSON.parse("[#{s}]")
end

class PropClass
  attr_reader :name, :properties, :records, :abstract, :interface, :parents

  def initialize(name)
    raise "Name can't be empty" if name.empty?

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
    ans = ans + '?' unless properties[property]

    inherited = parents.any? { |x| x.properties.key?(property) }
    ans = '^' + ans if inherited

    if inherited
      redefined = parents.any? { |x| x.properties.key?(property) && x.properties[property] != properties[property] }
      ans = ans + " {redefines #{property}}" if redefined
    end

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

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: infer_neo4j_schema.rb [options]"

  opts.on('--csv') do
    options[:csv] = true
  end

  opts.on('--labels Abc,Xyz', Array) do |labels|
    options[:labels] = labels
  end
end.parse!

STDIN.each_line do |line|
  next if STDIN.lineno == 1

  original_labels, keys = labels_keys_from_line(line)

  original_labels = ['UNLABELED'] if original_labels.empty?

  original_labels.sort!

  props.merge(keys)

  labels = original_labels
  labels = (labels & options[:labels]) if options[:labels]

  if labels.empty?
    STDERR.puts "Ignoring node #{original_labels.join(':')} no labels are in --labels"

    next
  end

  concrete_label = labels.join(':')

  class_from(concrete_label, concrete_classes).add_properties(keys)
end

if options[:csv]
  CSV(STDOUT) do |csv|
    csv << ['class', 'property', 'always present']
    concrete_classes.values.each do |cls|
      cls.properties.each do |prop, always_present|
        csv << [cls.name, prop, always_present]
      end
    end
  end
  exit(true)
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

  pres_specializations = children.group_by do |child|
    maybe_props.select { |x| child.properties[x] }
  end

  pres_specializations.each do |new_props, classes|
    if new_props.empty?
      classes.each { |c| c.parents << group_cls }
    else
      cls = Interface.new
      cls.add_properties(new_props + pres_props)
      cls.add_properties(new_props + pres_props + maybe_props)
      cls.parents << group_cls

      interfaces << cls

      classes.each { |c| c.parents << cls }
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

all_classes.each { |x| x.parents.uniq! }

puts "@startuml"
all_classes.each do |cls|
  puts cls.as_plantuml_class
end
puts "@enduml"
