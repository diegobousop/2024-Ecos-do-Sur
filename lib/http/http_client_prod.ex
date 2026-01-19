defmodule Http.HttpClientProd do
  alias Http.HttpBehaviour
  @behaviour HttpBehaviour

  def post(url, body, header) do
    HTTPoison.post(url, Poison.encode!(body), header)
  end

  def get(url, header) do
    HTTPoison.get(url, header)
  end

end
