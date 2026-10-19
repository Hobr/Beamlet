defmodule Beamlet.Storage.Repo do
  @moduledoc """
  声明使用基础连接策略的可信 Repo：use Beamlet.Storage.Repo, adapter: :sqlite 或 :postgres。每个模块只有其模块名注册的实例；加载不启动，init 不迁移。Dataset 负责打开校验，Host 可承接生命周期；直接 start_link 不等于数据集验证或准入。

  Declare an explicitly named trusted repository with the foundation connection
  settings. Example: `use Beamlet.Storage.Repo, adapter: :sqlite` (or `:postgres`).
  Each declared module is its own registered instance. Loading it starts nothing;
  Dataset opens it and Host may own its lifecycle. No migrations run in init.
  """
  @doc "生成显式命名的 Ecto.Repo 及连接初始化回调，仅接受 sqlite/postgres；其他 adapter 抛出 ArgumentError。不执行安装或启动。"
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    {adapter, configure} =
      case Keyword.fetch!(opts, :adapter) do
        :sqlite -> {Ecto.Adapters.SQLite3, :sqlite}
        :postgres -> {Ecto.Adapters.Postgres, :postgres}
        _ -> raise ArgumentError, "unsupported storage adapter"
      end

    quote do
      use Ecto.Repo, otp_app: :beamlet_storage, adapter: unquote(adapter)
      # 生成的 Repo.init 仅固定连接策略；安装由显式 Dataset 调用负责。
      @impl true
      @spec init(:supervisor | :runtime, keyword()) :: {:ok, keyword()}
      def init(_, config) do
        {:ok, apply(Beamlet.Storage.Connections, unquote(configure), [config])}
      end
    end
  end
end
