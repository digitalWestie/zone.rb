#!/usr/bin/env ruby
# docs: https://github.com/ruby/reline/blob/master/doc/for_users.md
require 'reline'
require 'prism'

# DEBUG arg for enabling debug mode
debug = ARGV.include?('--debug')

# define a class that will be used as the context for evaluation
class Area
  def initialize(area_name)
    @area_name = area_name
  end

  def look_around
    "You are somewhere special"
  end

  def get_binding
    binding
  end

  def to_s
    @area_name
  end

  def inspect
    "#{@area_name}\n It's a tight space surrounded by walls of rock. There is little light."
  end
end

area = Area.new("Outer Dump")

ALLOWED_MESSAGES = %i[inspect class puts to_s reverse]

def visit(node)
  case node
  when Prism::ProgramNode
    visit(node.statements)
  when Prism::StatementsNode
    # We'll have multiple statements if we nested blocks or conditionals
    # Multiple lines e.g. a=1; a*2 etc is still one statement
    node.body.each do |statement|
      visit(statement)
    end
  when Prism::LocalVariableReadNode
    puts "Local variable read: #{node.name}"
  when Prism::CallNode
    # Calling a method may be allowed, so we need to check what it is
    puts "Call node: #{node.name}, allowed: #{ALLOWED_MESSAGES.include?(node.name)}"
  when Prism::XStringNode
    # XString literals e.g. using system call backticks not allowed
    puts "XString node: #{node.inspect}, not allowed"
  else
    # There about 150 node types, so we just print otherwise
    puts "Unknown node: #{node.inspect}"
    puts node.inspect
    nil
  end
end

# Before we enter into the REPL, we save the TTY config
# so we can restore it later.
begin
  stty_save = `stty -g`.chomp
rescue
end

# Main loop
begin
  Reline.completion_proc = proc { |word|
    %w{
      help
      exit
    }
  }
  while line = Reline.readline("zone> ", true)
    case line.chomp
    when 'exit', 'quit'
      break
    when ''
      # NOOP
    else
      parse_result = Prism.parse(line)
      if parse_result.failure?
        puts "Syntax error: #{parse_result.errors.join(', ')}"
      else
        begin
          puts "=> #{area.get_binding.eval(line, "(zone)", 1)}"
          puts "--------------------------------"
          visit(parse_result.value)
          puts "--------------------------------"
        rescue StandardError => e
          puts "Error: #{e.message}"
          puts e.backtrace.join("\n") if debug
        end
      end
    end
  end
rescue Interrupt
  puts '^C'
  retry
ensure
  `stty #{stty_save}` if stty_save
end
puts

# The help text MAY need tweaked based on the context.
# Context is the current area, progression, and potentially a setting.
# If not high level we pass to the evaluator.

# We need to visit each node in the syntax tree and check if
# the statement is allowed or not.