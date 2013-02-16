require "rubygems"
# gem install json
require "json"
# gem install json_pure
require "json/pure"
# gem install yajl-ruby
require "yajl"

require File.join(File.dirname(__FILE__), "json_samples")

def time(name, &block)
  elapsed = (1..5).map {|i| s = Time.now; block.call; (Time.now - s) * 1000 }.min
  puts name+"\t"+elapsed.to_s
end

puts "Ruby Performance (msecs)"

time "JSON::Ext" do
  JSON::Ext::Parser.new($a).parse
  JSON::Ext::Parser.new($b).parse
  JSON::Ext::Parser.new($c).parse
  JSON::Ext::Parser.new($d).parse
  JSON::Ext::Parser.new($e).parse
end

time "JSON::Pure" do
  JSON::Pure::Parser.new($a).parse
  JSON::Pure::Parser.new($b).parse
  JSON::Pure::Parser.new($c).parse
  JSON::Pure::Parser.new($d).parse
  JSON::Pure::Parser.new($e).parse
end

time "Yajl\t" do
  Yajl::Parser.parse($a)
  Yajl::Parser.parse($b)
  Yajl::Parser.parse($c)
  Yajl::Parser.parse($d)
  Yajl::Parser.parse($e)
end

puts ""
