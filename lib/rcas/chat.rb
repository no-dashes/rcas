# frozen_string_literal: true

require "rcas"

module RCAS
  # A Claude-Code-style terminal front end for rcas (bin/rcas-chat).
  #
  # * Ruby is evaluated in a session where bare identifiers are variables,
  #   like bin/rcas; results are shown as text and, in iTerm2, typeset.
  # * Anything that is not Ruby is a question for Claude, which answers by
  #   running rcas code in the same session through the rcas_eval tool.
  # * /commands configure the session, !cmd runs a shell command, and
  #   sessions are saved so `rcas-chat --continue` picks up where you left.
  module Chat
    class Error < StandardError; end

    # The anthropic gem, loaded on first need: when credentials are present,
    # or a test hands the assistant a scripted runner. A session nobody asks
    # Claude in never loads it - it was a thousand files and a fifth of a
    # second on every start of rcas-chat, and one of its dependencies
    # (standardwebhooks) warns under -w. true when the gem is there.
    def self.load_anthropic
      return true if defined?(EvalTool)
      return false if @anthropic_missing
      quietly do
        require "anthropic"
        require_relative "chat/tool"
      end
      true
    rescue LoadError
      @anthropic_missing = true
      false
    end

    # $VERBOSE off for the block and back to what it was on every way out.
    def self.quietly
      verbose = $VERBOSE
      $VERBOSE = nil
      yield
    ensure
      $VERBOSE = verbose
    end
  end
end

require_relative "chat/settings"
require_relative "chat/style"
require_relative "chat/workspace"
require_relative "chat/ui"
require_relative "chat/usage"
require_relative "chat/assistant"
require_relative "chat/session"
require_relative "chat/picker"
require_relative "chat/repl"
