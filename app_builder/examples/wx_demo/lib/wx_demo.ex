defmodule WxDemo.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WxDemo.Preboot,
      WxDemo.Window
    ]

    opts = [strategy: :one_for_one, name: WxDemo.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

defmodule WxDemo.Preboot do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil)
  end

  @impl true
  def init(_) do
    if node = find_running_node() do
      IO.inspect(node)
      Node.spawn_link(node, fn ->
        send(WxDemo.Window, {:new_instance, System.argv()})
      end)

      System.stop()
      {:stop, :shutdown}
    else
      {:ok, nil}
    end
  end

  defp find_running_node do
    server = :"windows_installer@#{:net_adm.localhost()}"

    case :net_adm.ping(server) do
      :pong ->
        server
        nil

      :pang ->
        nil
    end
  end
end

defmodule WxDemo.Window do
  @moduledoc false

  @behaviour :wx_object

  # https://github.com/erlang/otp/blob/OTP-24.1.2/lib/wx/include/wx.hrl#L1314
  @wx_id_exit 5006

  def start_link(_) do
    {:wx_ref, _, _, pid} = :wx_object.start_link(__MODULE__, [], [])
    true = Process.register(pid, __MODULE__)
    {:ok, pid}
  end

  def child_spec(init_arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [init_arg]},
      restart: :transient
    }
  end

  @impl true
  def init(_) do
    title = "WxDemo"

    wx = :wx.new()
    frame = :wxFrame.new(wx, -1, title, size: {100, 100})

    if macos?() do
      fixup_macos_menubar(frame, title)
    end

    :wxFrame.show(frame)
    :wxFrame.connect(frame, :command_menu_selected)
    :wxFrame.connect(frame, :close_window, skip: true)

    if macos?() do
      :wx.subscribe_events()
    end

    state = %{frame: frame}
    {frame, state}
  end

  @impl true
  def handle_event({:wx, @wx_id_exit, _, _, _}, state) do
    :init.stop()
    {:stop, :shutdown, state}
  end

  @impl true
  def handle_event({:wx, _, _, _, {:wxClose, :close_window}}, state) do
    :init.stop()
    {:stop, :shutdown, state}
  end

  ## preboot messages

  @impl true
  def handle_info({:new_instance, argv}, state) do
    IO.inspect [new_instance: argv]
    {:noreply, state}
  end

  ## wx messages

  @impl true
  def handle_info({:open_url, url}, state) do
    :wxMessageDialog.new(state.frame, inspect(url))
    |> :wxDialog.showModal()

    {:noreply, state}
  end

  @impl true
  # ignore other events
  def handle_info(_event, state) do
    {:noreply, state}
  end

  defp fixup_macos_menubar(frame, title) do
    menubar = :wxMenuBar.new()
    # :wxMenuBar.setAutoWindowMenu(false)
    :wxFrame.setMenuBar(frame, menubar)

    # App Menu
    menu = :wxMenuBar.oSXGetAppleMenu(menubar)

    # Remove all items except for quit
    for item <- :wxMenu.getMenuItems(menu) do
      if :wxMenuItem.getId(item) == @wx_id_exit do
        :wxMenuItem.setText(item, "Quit #{title}\tCtrl+Q")
      else
        :wxMenu.delete(menu, item)
      end
    end
  end

  defp macos?() do
    :os.type() == {:unix, :darwin}
  end
end
