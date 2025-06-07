defmodule DSPEx.ClientTest do
  use ExUnit.Case, async: false

  setup do
    # Start a mock HTTP server for testing
    bypass = Bypass.open()
    client_config = %{
      base_url: "http://localhost:#{bypass.port}",
      api_key: "test_key",
      model: "test_model",
      timeout: 5000,
      max_retries: 3
    }

    {:ok, client} = DSPEx.Client.start_link(client_config)

    %{client: client, bypass: bypass, config: client_config}
  end

  describe "client initialization" do
    test "starts with correct configuration", %{client: client, config: config} do
      state = :sys.get_state(client)
      assert state.config.model == config.model
      assert state.config.api_key == config.api_key
    end

    test "validates required configuration" do
      assert {:error, :missing_api_key} =
        DSPEx.Client.start_link(%{model: "test"})

      assert {:error, :missing_model} =
        DSPEx.Client.start_link(%{api_key: "test"})
    end
  end

  describe "HTTP requests" do
    test "makes successful API call", %{client: client, bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/completions", fn conn ->
        assert conn.request_path == "/completions"
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test_key"]

        Plug.Conn.resp(conn, 200, Jason.encode!(%{
          choices: [%{message: %{content: "Hello, world!"}}],
          usage: %{prompt_tokens: 10, completion_tokens: 5}
        }))
      end)

      request = %{
        messages: [%{role: "user", content: "Hello"}],
        model: "test_model"
      }

      assert {:ok, response} = DSPEx.Client.request(client, request)
      assert response.choices
      assert response.usage
    end

    test "handles API errors with retries", %{client: client, bypass: bypass} do
      # First two requests fail, third succeeds
      Bypass.expect(bypass, "POST", "/completions", fn conn ->
        case Plug.Conn.get_req_header(conn, "x-retry-count") do
          [] -> Plug.Conn.resp(conn, 500, "Internal Server Error")
          ["1"] -> Plug.Conn.resp(conn, 500, "Internal Server Error")
          ["2"] -> Plug.Conn.resp(conn, 200, Jason.encode!(%{
            choices: [%{message: %{content: "Success"}}]
          }))
        end
      end)

      request = %{messages: [%{role: "user", content: "Test"}]}
      assert {:ok, _response} = DSPEx.Client.request(client, request)
    end

    test "fails after max retries", %{client: client, bypass: bypass} do
      Bypass.expect(bypass, "POST", "/completions", fn conn ->
        Plug.Conn.resp(conn, 500, "Internal Server Error")
      end)

      request = %{messages: [%{role: "user", content: "Test"}]}
      assert {:error, :max_retries_exceeded} = DSPEx.Client.request(client, request)
    end
  end

  describe "circuit breaker" do
    test "opens circuit after failure threshold", %{client: client, bypass: bypass} do
      Bypass.down(bypass)

      request = %{messages: [%{role: "user", content: "Test"}]}

      # Trigger circuit breaker
      for _ <- 1..5 do
        {:error, _} = DSPEx.Client.request(client, request)
      end

      # Circuit should be open now
      assert {:error, :circuit_open} = DSPEx.Client.request(client, request)
    end

    test "circuit recovers after timeout" do
      # This would be an integration test that waits for circuit breaker timeout
      # Implementation would depend on the specific circuit breaker library used
    end
  end

  describe "caching" do
    test "caches identical requests", %{client: client, bypass: bypass} do
      response_body = Jason.encode!(%{
        choices: [%{message: %{content: "Cached response"}}]
      })

      Bypass.expect_once(bypass, "POST", "/completions", fn conn ->
        Plug.Conn.resp(conn, 200, response_body)
      end)

      request = %{messages: [%{role: "user", content: "Same request"}]}

      # First request hits the server
      assert {:ok, response1} = DSPEx.Client.request(client, request)

      # Second identical request should be cached
      assert {:ok, response2} = DSPEx.Client.request(client, request)

      assert response1 == response2
    end

    test "cache respects TTL" do
      # Test that cache entries expire after configured TTL
      # Implementation depends on cache configuration
    end
  end
end
