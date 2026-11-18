#!/usr/bin/env ruby
# docs: https://github.com/ruby/reline/blob/master/doc/for_users.md
require 'io/console'
require 'reline'
require 'prism'
require 'lipgloss'

DEBUG = ARGV.include?('--debug')
ALLOWED_MESSAGES = %i[inspect class puts to_s reverse]
GAME_STATE = {
  prologue_completed: false,
  vignette_completed: false,
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
  TYPEWRITER_DELAY = 0.08
  DEFAULT_STYLE = Lipgloss::Style.new.foreground("#EFEFEF")
  SPEAKER_STYLE = Lipgloss::Style.new.bold(true).foreground("#CBC3E3")
  CODE_STYLE = Lipgloss::Style.new.foreground("#A0FFA0") # a light green
  SPEAKER_LINE = /\G([A-Z][A-Z0-9' ]*)\n/
  INLINE_CODE = /\G(?<!`)`([^`\n]+)`(?!`)/

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

  def completed?
    @current_page >= @pages.size
  end

  # Type out the current page. Any keypress prints the remainder immediately.
  # The keypress/input is discarded so that it has no other effect than skipping
  # the typewriting effect.
  def write_page
    @skip_typewriting_effect = false
    segments = tokenize_page
    return if segments.empty?

    segments.each do |style, text|
      text.each_char do |char|
        print(char == "\n" ? char : style.render(char))
        $stdout.flush

        next if @skip_typewriting_effect

        if stdin_ready?(TYPEWRITER_DELAY)
          @skip_typewriting_effect = true
          drain_stdin # discard any keypress input
        end
      end
    end
    puts
  end

  def tokenize_page
    text = @pages[current_page]
    return [] unless text

    segments = []
    current_style = DEFAULT_STYLE
    segment_style = DEFAULT_STYLE
    style_until = nil
    buffer = +""
    i = 0

    close_segment = -> {
      segments << [segment_style, buffer.dup] unless buffer.empty?
      buffer.clear
    }

    while i < text.length
      current_style, style_until = style_at(text, i, current_style, style_until)

      if current_style != segment_style
        close_segment.call
        segment_style = current_style
      end

      buffer << text[i]
      i += 1
    end

    close_segment.call
    segments
  end

  private

  # Resolve style for index +i+. Returns [style, style_until].
  def style_at(text, i, current_style, style_until)
    style = (style_until == i) ? DEFAULT_STYLE : current_style

    if (i.zero? || text[i - 1] == "\n") && (m = text.match(SPEAKER_LINE, i))
      [SPEAKER_STYLE, i + m[0].length]
    elsif m = text.match(INLINE_CODE, i)
      [CODE_STYLE, i + m[0].length]
    else
      [style, style_until]
    end
  end

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
  when Prism::SelfNode
    puts "Self node"
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

def repl_loop(area)
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
  return true if GAME_STATE[:prologue_completed]
  chapters = [Chapter.new("prologue/office.md"), Chapter.new("prologue/crossing.md")]
  chapter = chapters.first

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

      # We want to do switch to the crossing when the office is completed
      next_page_available = chapter.next_page!

      unless next_page_available
        chapters.shift
        break if chapters.empty?
        chapter = chapters.first
      end
    end

    has_first_input = true
  end

  true
end


def vignette_loop
  return true if GAME_STATE[:vignette_completed]
  print "\e[2J\e[H" # clear and move to top left
  vignette = Chapter.new("prologue/vignette.md")
  $stdin.noecho { vignette.write_page }
  print "\e[2J\e[H"
  true
end

# Main loop
begin
  #prologue_loop unless GAME_STATE[:prologue_completed]
  GAME_STATE[:prologue_completed] = true
  #vignette_loop unless GAME_STATE[:vignette_completed]
  GAME_STATE[:vignette_completed] = true

  outer_dump = Chapter.new("areas/outer_dump.md")
  $stdin.noecho { outer_dump.write_page }
  area = Area.new("Outer Dump")
  repl_loop(area)
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
