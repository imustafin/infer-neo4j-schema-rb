require 'json'
require 'set'
require 'pp'

def labels_keys_from_line(s)
  JSON.parse("[#{s}]")
end

class Class
  attr_reader :name, :properties, :records

  def initialize(name)
    @name = name

    # @properties[i] = i is always present?
    @properties = Hash.new

    @records = 0
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

  def as_plantuml_class
    properties = @properties
                   .keys
                   .map { |x| "#{x}#{@properties[x] ? '' : '?'}" }
                   .join("\n")

    "class #{@name} { \n #{properties} \n }"
  end
end

classes = {}

ARGF.each_line do |line|
  next if ARGF.lineno == 1

  labels, keys = labels_keys_from_line(line)

  labels << 'ANY'

  labels.each do |label|
    cls = classes.fetch(label, Class.new(label))

    cls.add_properties(keys)

    classes[label] = cls
  end
end

puts "@startuml"
classes.each do |name, cls|
  puts cls.as_plantuml_class  
end
puts "@enduml"
