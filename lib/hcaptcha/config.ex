defmodule Hcaptcha.Config do
  @moduledoc """
  Reads application configuration at runtime.

  Values are plain terms. Set them in `config/runtime.exs`.
  """

  @doc """
  Returns the value of `key` for `application`, or `default`.
  """
  @spec get_env(atom, atom, any) :: any
  def get_env(application, key, default \\ nil) do
    Application.get_env(application, key, default)
  end
end
