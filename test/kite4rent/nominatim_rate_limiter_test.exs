defmodule Kite4rent.NominatimRateLimiterTest do
  use ExUnit.Case, async: false

  alias Kite4rent.NominatimRateLimiter

  setup do
    # Ensure enough time has passed since last test
    # This prevents rate limiting from affecting test isolation
    Process.sleep(1100)
    :ok
  end

  describe "throttle/1" do
    test "executes function immediately when rate limit not exceeded" do
      # Make one request to set a baseline
      NominatimRateLimiter.throttle(fn -> :setup end)

      # Wait for rate limit window to pass
      Process.sleep(1100)

      # Now this request should be immediate
      start_time = System.monotonic_time(:millisecond)
      result = NominatimRateLimiter.throttle(fn -> :ok end)
      elapsed = System.monotonic_time(:millisecond) - start_time

      assert result == :ok
      # Should execute immediately without significant delay
      assert elapsed < 100
    end

    test "returns function result" do
      result = NominatimRateLimiter.throttle(fn -> {:ok, "test_result"} end)

      assert result == {:ok, "test_result"}
    end

    test "enforces 1 second minimum between requests" do
      # First request
      NominatimRateLimiter.throttle(fn -> :first end)

      # Second request should wait
      start_time = System.monotonic_time(:millisecond)
      result = NominatimRateLimiter.throttle(fn -> :second end)
      elapsed = System.monotonic_time(:millisecond) - start_time

      assert result == :second
      # Should have waited approximately 1000ms
      assert elapsed >= 950
      assert elapsed <= 1100
    end

    test "allows immediate execution after 1+ seconds have passed" do
      # First request
      NominatimRateLimiter.throttle(fn -> :first end)

      # Wait more than 1 second
      Process.sleep(1100)

      # Second request should execute immediately
      start_time = System.monotonic_time(:millisecond)
      result = NominatimRateLimiter.throttle(fn -> :second end)
      elapsed = System.monotonic_time(:millisecond) - start_time

      assert result == :second
      # Should execute immediately without additional delay
      assert elapsed < 100
    end

    test "serializes concurrent requests" do
      parent = self()

      # Spawn multiple processes making concurrent requests
      tasks =
        for i <- 1..3 do
          Task.async(fn ->
            result = NominatimRateLimiter.throttle(fn -> i end)
            send(parent, {:completed, i, System.monotonic_time(:millisecond)})
            result
          end)
        end

      # Collect completion times
      completion_times =
        for _i <- 1..3 do
          receive do
            {:completed, _index, time} -> time
          after
            5000 -> nil
          end
        end

      # Wait for all tasks to complete
      results = Task.await_many(tasks)

      # All tasks should complete successfully
      assert Enum.sort(results) == [1, 2, 3]

      # Calculate intervals between completions
      [time1, time2, time3] = Enum.sort(completion_times)
      interval1 = time2 - time1
      interval2 = time3 - time2

      # Each interval should be approximately 1000ms
      assert interval1 >= 950
      assert interval1 <= 1100
      assert interval2 >= 950
      assert interval2 <= 1100
    end

    test "propagates function errors to caller" do
      # Function that returns an error tuple should work fine
      result = NominatimRateLimiter.throttle(fn -> {:error, :test_error} end)

      assert result == {:error, :test_error}

      # Rate limiter should still work for subsequent requests
      start_time = System.monotonic_time(:millisecond)
      result2 = NominatimRateLimiter.throttle(fn -> :ok end)
      elapsed = System.monotonic_time(:millisecond) - start_time

      assert result2 == :ok
      # Should enforce rate limit after error result
      assert elapsed >= 950
      assert elapsed <= 1100
    end
  end
end
