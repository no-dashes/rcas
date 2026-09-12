# frozen_string_literal: true

require "rcas"

begin
  require "anthropic"
rescue LoadError
  # The REPL works without the gem; only questions to Claude need it.
end

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
