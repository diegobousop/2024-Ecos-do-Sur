defmodule Http.Authentication.SignUpEmail do
  import Swoosh.Email
  require Logger

  @from "no-reply@example.com"

  def send_code(to_email, code) when is_binary(to_email) and is_binary(code) do
    email =
      new()
      |> from(@from)
      |> to(to_email)
      |> subject("Your Sign-Up Code")
      |> text_body("Your verification code is: #{code}")
      |> html_body("<p>Your verification code is: <strong>#{code}</strong></p>")

    case Http.Authentication.Mailer.deliver(email) do
      {:ok, _} ->
        Logger.info("sign-up email sent to #{to_email}")
        :ok

      {:error, reason} ->
        Logger.error("failed to send sign-up email to #{to_email}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
