defmodule I18n.Application do
  @moduledoc false
  use Application

  alias I18n.{
    InvisibleMarker,
    Translator
  }

  require Logger

  def start(_type, _args) do
    children = []
    opts = [strategy: :one_for_one, name: I18n.Supervisor]

    # Initialize the stateful parts of the application:
    # * The InvisibleMarker system
    InvisibleMarker.setup()
    # * The translations in the translator
    Translator.setup()

    Logger.debug("I18.Application started.")
    Supervisor.start_link(children, opts)
  end
end
