defmodule Mobilizon.Service.HTTP.RichMediaPreviewClient do
  @moduledoc """
  Tesla HTTP Basic Client that fetches HTML to extract metadata preview
  """

  use Tesla
  alias Mobilizon.Config

  @default_opts [
    recv_timeout: 20_000
  ]

  adapter(Tesla.Adapter.Hackney, @default_opts)

  @user_agent Config.instance_user_agent()

  plug(Tesla.Middleware.FollowRedirects)

  plug(Tesla.Middleware.Timeout, timeout: 10_000)

  plug(Tesla.Middleware.Headers, [{"User-Agent", @user_agent}])
end
