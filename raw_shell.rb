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
    puts "You are somewhere special"
  end

  def get_binding
    binding
  end

  def to_s
    @area_name
  end
end

area = Area.new("Outer Dump")

begin
  stty_save = `stty -g`.chomp
rescue
end

begin
  Reline.completion_proc = proc { |word|
    %w{
      help
      exit
    }
  }
  while line = Reline.readline("zone> ", true)
    case line.chomp
    when 'exit', 'quit', 'q'
      exit 0
    when ''
      # NOOP
    else
      parse = Prism.parse(line)
      if parse.failure?
        puts "Syntax error: #{parse.errors.join(', ')}"
      else
        begin
          area.get_binding.eval(line, "(zone)", 1)
        rescue StandardError => e
          puts "Error: #{e.message}"
          puts e.backtrace.join("\n") if debug
        end
      end
    end
  end
rescue Interrupt
  puts '^C'
  `stty #{stty_save}` if stty_save
  exit 0
end
puts

# We need to handle help text and other high level commands here.
# The help text MAY need tweaked based on the context.
# Context is the current area, progression, and potentially a setting.
# If not high level we pass to the evaluator.
