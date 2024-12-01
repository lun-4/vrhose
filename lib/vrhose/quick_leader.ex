defmodule VRHose.QuickLeader do
  require Logger
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  def acquire() do
    GenServer.call(VRHose.QuickLeader, :acquire)
  end

  def init(_opts) do
    {:ok,
     %{
       leader: nil,
       leader_monitor: nil
     }}
  end

  def handle_call(:acquire, from_ref, state) do
    {from, _} = from_ref

    if state.leader == nil do
      Logger.info("quick leader: #{inspect(from)} is now leader")
      monitor_ref = Process.monitor(from)

      state = put_in(state.leader, from)
      state = put_in(state.leader_monitor, monitor_ref)

      {:reply, :leader, state}
    else
      if from == state.leader do
        {:reply, :leader, state}
      else
        {:reply, :not_leader, state}
      end
    end
  end

  def handle_info({:DOWN, monitor_ref, :process, _pid, reason}, state) do
    if monitor_ref == state.leader_monitor do
      Logger.warning(
        "LEADER DOWN message on monitor_ref #{inspect(monitor_ref)} reason=#{inspect(reason)}"
      )

      true = Process.demonitor(monitor_ref, [:flush])
      state = put_in(state.leader, nil)
      {:noreply, state}
    else
      Logger.warning(
        "unknown DOWN message on monitor_ref #{inspect(monitor_ref)} reason=#{inspect(reason)}"
      )
    end
  end
end
