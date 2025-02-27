defmodule HostCore.HeartbeatEmitter do
  @moduledoc false
  use GenServer, restart: :transient
  require Logger

  @thirty_seconds 30_000

  alias HostCore.CloudEvent

  @doc """
  Starts the host server
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    :timer.send_interval(@thirty_seconds, self(), :publish_heartbeat)
    Process.send(self(), :publish_heartbeat, [:noconnect, :nosuspend])

    {:ok, opts}
  end

  @impl true
  def handle_info(:publish_heartbeat, state) do
    publish_heartbeat(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:publish_heartbeat, state) do
    publish_heartbeat(state)
    {:noreply, state}
  end

  def emit_heartbeat() do
    GenServer.cast(__MODULE__, :publish_heartbeat)
  end

  defp publish_heartbeat(state) do
    Logger.debug("Publishing heartbeat")
    topic = "wasmbus.evt.#{state[:lattice_prefix]}"
    msg = generate_heartbeat(state)
    Gnat.pub(:control_nats, topic, msg)
  end

  defp generate_heartbeat(state) do
    actors =
      HostCore.Actors.ActorSupervisor.all_actors_for_hb()
      |> Enum.map(fn {k, iid} -> %{public_key: k, instance_id: iid} end)

    providers =
      HostCore.Providers.ProviderSupervisor.all_providers()
      |> Enum.map(fn {_pid, pk, link, contract, instance_id} ->
        %{public_key: pk, link_name: link, contract_id: contract, instance_id: instance_id}
      end)

    %{
      actors: actors,
      providers: providers,
      labels: HostCore.Host.host_labels(),
      friendly_name: HostCore.Host.friendly_name()
    }
    |> CloudEvent.new("host_heartbeat", state[:host_key])
  end
end
