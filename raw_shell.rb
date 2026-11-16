#!/usr/bin/env ruby
# docs: https://github.com/ruby/reline/blob/master/doc/for_users.md
require 'io/console'
require 'reline'
require 'prism'

DEBUG = ARGV.include?('--debug')
ALLOWED_MESSAGES = %i[inspect class puts to_s reverse]
GAME_STATE = {
  prologue_completed: false,
  crossing_completed: false,
}

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


class Chapter
  DEFAULT_CONTENT_ROOT = File.expand_path("content", __dir__)
  TYPEWRITER_DELAY = 0.05

  attr_reader :source, :pages, :current_page
  attr_writer :current_page

  def initialize(source, content_root = DEFAULT_CONTENT_ROOT)
    @content_root = content_root
    @source = source
    @pages = pages_for(@source)
    @current_page = 0
    @skip_typewriting_effect = false
  end

  def skip_typewriting_effect!
    @skip_typewriting_effect = true
  end

  def next_page!
    @current_page += 1
    @current_page < @pages.size
  end

  # Type out the current page. Any keypress prints the remainder immediately.
  # The keypress/input is discarded so that it has no other effect than skipping
  # the typewriting effect.
  def write_page
    @skip_typewriting_effect = false
    text = @pages[current_page]
    return unless text

    i = 0
    while i < text.length
      print text[i]
      $stdout.flush # Flush so each character appears immediately.
      i += 1

      if @skip_typewriting_effect || stdin_ready?(TYPEWRITER_DELAY)
        @skip_typewriting_effect = true
        drain_stdin # discard any keypress input
        print text[i..] # print the remainder of the page immediately
        break
      end
    end
    puts
  end

  private

  # True if the user typed something within +timeout+ seconds.
  # IO.select watches file descriptors until timeout;
  # returns early on input.
  def stdin_ready?(timeout)
    !!IO.select([$stdin], nil, nil, timeout)
  end

  def drain_stdin
    loop { $stdin.read_nonblock(4096) }
  rescue IO::WaitReadable, EOFError
  end

  def pages_for(source)
    path = File.join(@content_root, source)
    File.read(path).split(/\n---\n/) #.map(&:rstrip)
  end
end


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
  when Prism::XStringNode || Prism::InterpolatedXStringNode
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

def repl_loop
  area = Area.new("Outer Dump")

  Reline.completion_proc = proc { |word|
    %w{
      help
      exit
    }
  }
  while line = Reline.readline("zone> ", true)
    case line.chomp
    when 'exit', 'quit'
      raise SystemExit
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
          puts e.backtrace.join("\n") if DEBUG
        end
      end
    end
  end
end

def prologue_loop
  chapter = Chapter.new("prologue/office.md")
  has_first_input = false

  loop do
    $stdin.noecho { chapter.write_page } # Don't mirror keypresses while writing page

    prompt = has_first_input ? "> " : "(h=help, s=skip, e=exit, Enter to continue)> "
    line = Reline.readline(prompt, true)
    break if line.nil?

    case line.chomp
    when 'exit', 'e'
      raise SystemExit
    when 'help', 'h'
      puts "Commands:"
      puts "  enter - continue"
      puts "  skip - skip prologue completely"
      puts "  exit - quit"
      puts "  help - show commands"
    when 'skip', 's'
      break
    else
      print "\e[1A\e[2K" # up 1 line, clear entire line
      $stdout.flush
      break unless chapter.next_page!
    end

    has_first_input = true
  end

  true
end


# Main loop
begin
  prologue_loop unless GAME_STATE[:prologue_completed]
  GAME_STATE[:prologue_completed] = true
  #crossing_loop unless GAME_STATE[:crossing_completed]
  repl_loop
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
