defmodule Mobilizon.Service.Geospatial.Photon do
  @moduledoc """
  [Photon](https://photon.komoot.de) backend.
  """
  alias Mobilizon.Service.Geospatial.Provider
  require Logger
  alias Mobilizon.Addresses.Address

  @behaviour Provider

  @endpoint Application.get_env(:mobilizon, __MODULE__) |> get_in([:endpoint])

  @impl Provider
  @doc """
  Photon implementation for `c:Mobilizon.Service.Geospatial.Provider.geocode/3`.

  Note: It seems results are quite wrong.
  """
  @spec geocode(number(), number(), keyword()) :: list(Address.t())
  def geocode(lon, lat, options \\ []) do
    url = build_url(:geocode, %{lon: lon, lat: lat}, options)
    Logger.debug("Asking photon for reverse geocoding with #{url}")

    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <-
           HTTPoison.get(url),
         {:ok, %{"features" => features}} <- Poison.decode(body) do
      processData(features)
    end
  end

  @impl Provider
  @doc """
  Photon implementation for `c:Mobilizon.Service.Geospatial.Provider.search/2`.
  """
  @spec search(String.t(), keyword()) :: list(Address.t())
  def search(q, options \\ []) do
    url = build_url(:search, %{q: q}, options)
    Logger.debug("Asking photon for addresses with #{url}")

    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <-
           HTTPoison.get(url),
         {:ok, %{"features" => features}} <- Poison.decode(body) do
      processData(features)
    end
  end

  @spec build_url(atom(), map(), list()) :: String.t()
  defp build_url(method, args, options) do
    limit = Keyword.get(options, :limit, 10)
    lang = Keyword.get(options, :lang, "en")
    coords = Keyword.get(options, :coords, nil)
    endpoint = Keyword.get(options, :endpoint, @endpoint)

    case method do
      :search ->
        url = "#{endpoint}/api/?q=#{URI.encode(args.q)}&lang=#{lang}&limit=#{limit}"
        if is_nil(coords), do: url, else: url <> "&lat=#{coords.lat}&lon=#{coords.lon}"

      :geocode ->
        "#{endpoint}/reverse?lon=#{args.lon}&lat=#{args.lat}&lang=#{lang}&limit=#{limit}"
    end
  end

  defp processData(features) do
    features
    |> Enum.map(fn %{"geometry" => geometry, "properties" => properties} ->
      %Address{
        country: Map.get(properties, "country"),
        locality: Map.get(properties, "city"),
        region: Map.get(properties, "state"),
        description: Map.get(properties, "name") || streetAddress(properties),
        floor: Map.get(properties, "floor"),
        geom: Map.get(geometry, "coordinates") |> Provider.coordinates(),
        postal_code: Map.get(properties, "postcode"),
        street: properties |> streetAddress()
      }
    end)
  end

  defp streetAddress(properties) do
    if Map.has_key?(properties, "housenumber") do
      Map.get(properties, "housenumber") <> " " <> Map.get(properties, "street")
    else
      Map.get(properties, "street")
    end
  end
end