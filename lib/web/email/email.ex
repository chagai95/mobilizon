defmodule Mobilizon.Web.Email do
  @moduledoc """
  The Email context.
  """

  use Bamboo.Phoenix, view: Mobilizon.Web.EmailView

  alias Ecto.UUID
  alias Mobilizon.Config
  alias Mobilizon.Web.EmailView

  @spec base_email(keyword()) :: Bamboo.Email.t()
  def base_email(args) do
    instance = Config.instance_config()

    args
    |> new_email()
    |> from({Config.instance_name(), Config.instance_email_from()})
    |> put_header("Reply-To", Config.instance_email_reply_to())
    |> put_header("Date", date())
    |> put_header("Message-Id", message_id())
    |> assign(:instance, instance)
    |> put_html_layout({EmailView, "email.html"})
    |> put_text_layout({EmailView, "email.text"})
  end

  # Generating an UUID randomly causes Bamboo.Test.assert_delivered_email/1 to fail
  defp message_id do
    if Application.fetch_env!(:mobilizon, :env) == :test do
      "TEST_ENV_MESSAGE_ID@#{Config.instance_hostname()}"
    else
      "#{UUID.generate()}@#{Config.instance_hostname()}"
    end
  end

  defp date do
    if Application.fetch_env!(:mobilizon, :env) == :test do
      "REMOVED FOR TESTING"
    else
      Timex.format!(DateTime.utc_now(), "{WDshort}, {D} {Mshort} {YYYY} {h24}:{m}:{s} {Z}")
    end
  end
end
