defmodule ExMicrosoftBot.TokenManager do
  @moduledoc """
  This module is a GenServer that handles getting access token from
  Microsoft bot framework and also is responsible for refreshing the token
  before it expires.
  """
  use ExMicrosoftBot.RefreshableAgent

  alias ExMicrosoftBot.Models
  alias ExMicrosoftBot.Client

  ################################################
  ##### Functions to interact with GenServer #####
  ################################################

  @doc """
  Get the token that can be used to authorize calls to Microsoft Bot Framework
  """
  def get_token() do
    %{token: token} = get_state

    token
  end

  #######################################
  ##### Refreshable Agent Callbacks #####
  #######################################

  @default_time_gap_to_refresh_in_seconds 500
  @doc """
  Refresh the token by making a service call and then scheduling a message to
  this GenServer before token expires so that it can be refreshed
  """
  def get_refreshed_state(%Models.AuthData{} = auth_data, old_state) do
    Application.get_env(:ex_microsoftbot, :using_bot_emulator)
    |> get_refreshed_state(auth_data, old_state)
  end

  @doc """
  The time to refresh which is taken from the response of the token
  """
  def time_to_refresh_after_in_seconds(%{expiry_in_seconds: expiry_in_seconds}) do
    (expiry_in_seconds - @default_time_gap_to_refresh_in_seconds)
  end

  ###############################
  ####### Helper functions ######
  ###############################

  defp get_refreshed_state(true, %Models.AuthData{} = _auth_data, _old_state) do
    %{token: "TestToken", expiry_in_seconds: 36000}
  end

  defp get_refreshed_state(_, %Models.AuthData{} = auth_data, _old_state) do
    refresh_token(auth_data)
    |> validate_token
  end

  defp validate_token(%{token: token} = token_response) do
    # TODO: See what other checks are needed to verify the JWT
    with jwt <- JOSE.JWT.peek_payload(token),
         true <- contains_valid_app_id_claim?(jwt)
         do
           true
         else
           result -> raise "Error validating token. Result: #{inspect(result)}"
    end

    token_response
  end

  defp contains_valid_app_id_claim?(%JOSE.JWT{} = jwt) do
    contains_valid_app_id_claim?(Application.get_env(:ex_microsoftbot, :app_id), jwt)
  end

  defp contains_valid_app_id_claim?(expected_app_id, %JOSE.JWT{fields: %{"appid" => expected_app_id}}), do: true
  defp contains_valid_app_id_claim?(_, %JOSE.JWT{}), do: false


  @auth_api_endpoint "https://login.microsoftonline.com/common/oauth2/v2.0/token"
  defp refresh_token(%Models.AuthData{} = auth_data) do
    {:ok, token_response} = get_token_from_service(auth_data)

    %{
      token: Map.get(token_response, "access_token"),
      expiry_in_seconds: Map.get(token_response, "expires_in")
    }
  end

  defp get_token_from_service(%Models.AuthData{app_id: app_id, app_password: app_password}) do
    body = [
      dummy_param: "dummy", # In testing the first param was not detected by the API hence adding a dummy param
      grant_type: "client_credentials",
      client_id: app_id,
      client_secret: app_password,
      scope: "https://graph.microsoft.com/.default"
    ] |> convert_to_post_params_string

    HTTPotion.post(@auth_api_endpoint, [body: Poison.encode!(body)])
    |> Client.deserialize_response(&(Poison.decode!(&1, as: %{})))
  end

  defp convert_to_post_params_string(params) do
    Enum.reduce(params, [], fn ({k, v}, acc) -> ["#{k}=#{URI.encode_www_form(v)}" | acc] end)
    |> Enum.reverse
    |> Enum.join("&")
  end

end
