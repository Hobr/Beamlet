# 扫描器回归测试：先证明分类规则本身正确，再用它检查生产源码。
# 这里的夹具（生成/缺 spec/嵌套/quote 等）不作为生产模块的 API 承诺。
Code.require_file("contracts.exs", __DIR__)
ExUnit.start(seed: 631_927)

defmodule Beamlet.Quality.ContractsTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  alias Beamlet.Quality.Contracts

  @spec scan(String.t()) :: Contracts.report()
  defp scan(body), do: Contracts.scan_source("defmodule Example do\n#{body}\nend")

  @spec one(Contracts.report()) :: Contracts.function_entry()
  defp one(report) do
    assert [function] = report.functions
    function
  end

  test "missing ordinary public and private functions fail independently" do
    for kind <- ["def", "defp"] do
      report = scan("#{kind} call(value), do: value")
      assert Contracts.status(report) == 1
      assert one(report).specs == 0
      assert one(report).arity == 1
      assert one(report).kind == String.to_existing_atom(kind)
    end
  end

  test "deleting either spec or adding an unannotated function is a failing mutation" do
    source = """
    @spec public(integer()) :: integer()
    def public(x), do: private(x)
    @spec private(integer()) :: integer()
    defp private(x), do: x
    """

    assert Contracts.status(scan(source)) == 0

    for spec <- ["@spec public(integer()) :: integer()", "@spec private(integer()) :: integer()"] do
      report = source |> String.replace(spec, "") |> scan()
      assert Contracts.status(report) == 1
      assert length(Contracts.missing(report)) == 1
    end

    assert Contracts.status(scan(source <> "\ndef added, do: :ok")) == 1
  end

  test "multi clauses and guards form one logical function" do
    report =
      scan("""
      @spec call(integer() | nil) :: integer()
      def call(x) when is_integer(x), do: x
      def call(nil), do: 0
      """)

    assert Contracts.status(report) == 0
    assert one(report).clauses == 2
    assert one(report).lines == [3, 4]
  end

  test "default declaration head requires only maximum arity and counts heads separately" do
    report =
      scan(~S"""
      @spec call(integer(), integer()) :: integer()
      def call(x, y \\ 0)
      def call(x, y) when is_integer(x), do: x + y
      def call(nil, y), do: y
      """)

    function = one(report)
    assert {function.arity, function.defaults, function.heads, function.clauses} == {2, 1, 1, 2}
    assert Contracts.status(report) == 0
  end

  test "inline defaults and nontrailing defaults do not invent wrapper identities" do
    for args <- [~S"x \\ 0, y", ~S"x, y \\ 0"] do
      report = scan("@spec call(integer(), integer()) :: integer()\ndef call(#{args}), do: x + y")
      assert one(report).defaults == 1
      assert one(report).arity == 2
      assert Contracts.status(report) == 0
    end
  end

  test "an explicitly defined different arity still needs its own spec" do
    report = scan("@spec call(integer()) :: integer()\ndef call(x), do: x\ndef call, do: 0")
    assert [%{name: :call, arity: 0}] = Contracts.missing(report)
  end

  test "a spec for the generated default wrapper does not cover maximum arity" do
    report =
      scan(~S"""
      @spec call() :: integer()
      def call(x \\ 0), do: x
      """)

    assert Contracts.status(report) == 1
    assert one(report).arity == 1
  end

  test "delegates require contracts including defaults and renamed targets" do
    report =
      scan(~S"""
      @spec call(integer()) :: integer()
      defdelegate call(x \\ 0), to: Other, as: :target
      """)

    assert Contracts.status(report) == 0
    assert {one(report).kind, one(report).defaults} == {:defdelegate, 1}
    assert Contracts.status(scan("defdelegate call(x), to: Other")) == 1
  end

  test "overloaded and constrained polymorphic specs match one identity" do
    report =
      scan("""
      @spec call(integer()) :: integer()
      @spec call(value) :: value when value: var
      def call(x), do: x
      """)

    assert Contracts.status(report) == 0
    assert one(report).specs == 2
  end

  test "nested module specs cannot cover a parent or sibling" do
    report =
      scan("""
      @spec call() :: :ok
      def call, do: :ok
      defmodule Child do
        def call, do: :ok
      end
      defmodule Other do
        @spec call() :: :ok
        def call, do: :ok
      end
      """)

    assert [%{scope: {"Example.Child", []}}] = Contracts.missing(report)
    assert length(report.functions) == 3
  end

  test "nested absolute, module-relative, and aliased module names have distinct owners" do
    report =
      scan("""
      alias Elixir.External, as: Target
      defmodule Target do
        @spec call() :: :ok
        def call, do: :ok
      end
      defmodule __MODULE__.Child do
        @spec call() :: :ok
        def call, do: :ok
      end
      defmodule Elixir.Absolute do
        @spec call() :: :ok
        def call, do: :ok
      end
      """)

    assert Enum.sort(Enum.map(report.functions, &elem(&1.scope, 0))) == [
             "Absolute",
             "Example.Child",
             "External"
           ]

    assert Contracts.status(report) == 0
  end

  test "separate files and reopened modules do not borrow each other's specs" do
    dir = temporary_directory()
    a = Path.join(dir, "a.ex")
    b = Path.join(dir, "b.ex")
    File.write!(a, "defmodule Example do\n@spec call() :: :ok\nend")
    File.write!(b, "defmodule Example do\ndef call, do: :ok\nend")
    assert Contracts.status(Contracts.scan([a, b])) == 1
  end

  test "public and private macro definitions require explicit source arity specs" do
    for kind <- ["defmacro", "defmacrop"] do
      report = scan("@spec call(Macro.t()) :: Macro.t()\n#{kind} call(ast), do: ast")
      assert Contracts.status(report) == 0
      assert one(report).arity == 1
      assert Contracts.status(scan("#{kind} call(ast), do: ast")) == 1
    end
  end

  test "Repo style quote definitions and callbacks are owned by the template not the macro module" do
    report =
      scan("""
      @spec __using__(Macro.t()) :: Macro.t()
      defmacro __using__(_opts) do
        quote do
          use Ecto.Repo, otp_app: :example
          @impl true
          @spec init(term(), keyword()) :: {:ok, keyword()}
          def init(_, config), do: {:ok, config}
        end
      end
      """)

    assert Contracts.status(report) == 0

    assert [%{name: :init, impl: ["true"], scope: {"Example", [_]}}] =
             Enum.filter(report.functions, &(&1.name == :init))

    assert length(report.boundaries) == 1
  end

  test "a host spec cannot cover a quoted definition and a quoted spec cannot cover the host" do
    report =
      scan("""
      @spec make() :: Macro.t()
      @spec call() :: :ok
      def make do
        quote do
          def call, do: :ok
          @spec other() :: :ok
        end
      end
      def other, do: :ok
      """)

    assert Enum.sort(Enum.map(Contracts.missing(report), & &1.name)) == [:call, :other]
  end

  test "sibling quote templates and nested quotes never share contracts" do
    report =
      scan("""
      @spec make() :: Macro.t()
      def make do
        quote do
          @spec call() :: :ok
          def call, do: :ok
          quote do
            def call, do: :ok
          end
        end
        quote do
          def call, do: :ok
        end
      end
      """)

    assert length(report.functions) == 4
    assert length(Contracts.missing(report)) == 2

    assert Enum.map(Contracts.missing(report), &length(elem(&1.scope, 1))) |> Enum.sort() == [
             1,
             2
           ]
  end

  test "same-line quotes are distinguished by column" do
    report =
      scan(
        "@spec make() :: Macro.t()\ndef make do\nquote(do: (@spec call() :: :ok; def call, do: :ok)); quote(do: (def call, do: :ok))\nend"
      )

    assert length(Contracts.missing(report)) == 1
  end

  test "nested module in a template cannot cover its surrounding template" do
    report =
      scan("""
      @spec make() :: Macro.t()
      def make do
        quote do
          defmodule Child do
            @spec call() :: :ok
            def call, do: :ok
          end
          def call, do: :ok
        end
      end
      """)

    assert [%{scope: {"Example", [_]}}] = Contracts.missing(report)
  end

  test "callback declarations are inventoried, not treated as implementation specs" do
    report =
      Contracts.scan_source("""
      defmodule Contract do
        @callback call(integer()) :: integer()
        @macrocallback build(Macro.t()) :: Macro.t()
      end
      defmodule Implementation do
        @behaviour Contract
        @impl true
        def call(x), do: x
      end
      """)

    assert one(report).callbacks == ["Contract"]
    assert one(report).behaviours == ["Contract"]
    assert one(report).impl == ["true"]
    assert Contracts.status(report) == 1
    assert Enum.map(report.declarations, & &1.kind) == [:callback, :macrocallback]
  end

  test "OTP impl marker never exempts ordinary definitions" do
    report = scan("@impl GenServer\ndef init(state), do: {:ok, state}")
    assert one(report).impl == ["GenServer"]
    assert Contracts.status(report) == 1
  end

  test "Phoenix component rewriting remains a generation boundary, not an exclusion" do
    report =
      scan(~S"""
      use Phoenix.Component
      attr :name, :string
      @spec hello(map()) :: Phoenix.LiveView.Rendered.t()
      def hello(assigns), do: ~H"<p>{@name}</p>"
      embed_templates "example/*"
      defp helper(x), do: x
      """)

    assert Enum.map(Contracts.missing(report), & &1.name) == [:helper]
    assert Enum.any?(report.boundaries, &String.starts_with?(&1.source, "use "))
    assert Enum.any?(report.boundaries, &String.starts_with?(&1.source, "embed_templates"))
    refute Enum.any?(report.functions, &(&1.name == :__components__))
  end

  test "modules without functions remain explicitly inventoried" do
    report = Contracts.scan_source("defmodule Empty do\n@moduledoc false\nend")
    assert [%{scope: {"Empty", []}}] = report.modules
    assert report.functions == []
    assert Contracts.render(report, true) =~ "MODULE fixture.ex:1:1 Empty"
  end

  test "schema variables and function heads are not mistaken for DSL generation" do
    report = scan("@spec schema(term()) :: term()\ndef schema(schema), do: schema")
    assert report.boundaries == []
    assert Contracts.status(report) == 0
  end

  test "nested module's implicit alias resolves its later callback implementation" do
    report =
      scan("""
      defmodule Contract do
        @callback call() :: :ok
      end
      defmodule Implementation do
        @behaviour Contract
        @spec call() :: :ok
        def call, do: :ok
      end
      """)

    assert one(report).callbacks == ["Example.Contract"]
    assert Contracts.status(report) == 0
  end

  test "struct/schema/framework generated exports are not invented as source functions" do
    report = scan("use Ecto.Schema\nschema \"records\" do\nfield :name, :string\nend")
    assert report.functions == []
    assert length(report.boundaries) == 2
    assert Contracts.status(report) == 0
  end

  test "dynamic heads, names, argument splices, modules, and generation fail closed" do
    for body <- [
          "def unquote(name)(x), do: x",
          "def call(unquote_splicing(args)), do: :ok",
          "defmodule unquote(name) do\nend",
          "for name <- [:call] do\ndef unquote(name)(), do: :ok\nend",
          "for _ <- [1, 2] do\n@spec call() :: :ok\ndef call, do: :ok\nend",
          "Module.create(Name, ast, [])",
          "Code.eval_quoted(ast)",
          "Code.eval_string(source)",
          "Code.compile_string(source)",
          "Code.compile_quoted(ast)",
          "Code.compile_file(path)",
          "quote do\nKernel.unquote(kind)(call(), do: :ok)\nend",
          "quote do\nunquote(kind)(call(), do: :ok)\nend",
          "alias unquote(name)",
          "quote unquote: setting do\n@spec call() :: :ok\ndef call, do: :ok\nend",
          "defguard valid?(x) when is_integer(x)",
          "defprotocol Protocol do\ndef call(x)\nend",
          "defimpl Protocol, for: Any do\ndef call(x), do: x\nend"
        ] do
      report = scan(body)
      assert report.errors != [], body
      assert Contracts.status(report) == 1
    end
  end

  test "definitions without module owners and unsupported contract syntax fail" do
    assert Contracts.status(Contracts.scan_source("@spec call() :: :ok\ndef call, do: :ok")) == 1
    assert scan("@spec unquote(contract)").errors != []
    assert scan("@behaviour unquote(behaviour)").errors != []
  end

  test "a nested ordinary definition cannot masquerade as a module function" do
    report =
      scan("@spec call() :: :ok\ndef call do\n@spec nested() :: :ok\ndef nested, do: :ok\nend")

    assert report.errors != []
    assert Contracts.status(report) == 1
  end

  test "parse and read failures are actionable nonzero reports" do
    report = Contracts.scan_source("defmodule Broken do", "broken.ex")
    assert [%{location: %{file: "broken.ex", line: 1}, message: message}] = report.errors
    assert message =~ "parse error"
    assert Contracts.status(report) == 1
    assert Contracts.status(Contracts.scan(["/definitely/no/such/source.ex"])) == 1
  end

  test "parsed source and macros are never executed" do
    source = """
    raise "must not run"
    defmodule NeverLoadedByContractsFixture do
      use DoesNotExist
      @before_compile DoesNotExist
      @spec call() :: :ok
      def call, do: :ok
    end
    """

    report = Contracts.scan_source(source)
    assert Contracts.status(report) == 0
    refute Code.ensure_loaded?(NeverLoadedByContractsFixture)
    assert length(report.boundaries) == 2
  end

  test "no exception mechanism accepts stale, duplicate, or broad exemptions" do
    for options <- [
          ["--exceptions", "stale.json"],
          ["--exclude", "Example"],
          ["--ignore-missing"],
          ["--exceptions", "a", "--exceptions", "a"]
        ] do
      assert capture_io(:stderr, fn -> assert Contracts.main(options) == 2 end) =~ "no exemptions"
    end

    # A made-up exemption attribute/comment cannot suppress an ordinary private.
    report = scan("@contract_exception :private\n# ignore missing\ndefp private, do: :ok")
    assert Contracts.status(report) == 1
  end

  test "rendering includes unique counts, missing identities and optional audit detail" do
    report = scan("use GenServer\n@callback call() :: :ok\ndefp call, do: :ok")
    text = Contracts.render(report, true)
    assert text =~ "functions: 1; covered: 0; missing: 1; errors: 0"
    assert text =~ "Example defp call/0 clauses=1"
    assert text =~ "DECLARATION"
    assert text =~ "BOUNDARY"
    refute Contracts.render(report) =~ "BOUNDARY"
  end

  test "CLI subprocess returns actual nonzero for a mutation and zero for complete source" do
    dir = temporary_directory()
    file = Path.join(dir, "source.ex")
    script = Path.join(__DIR__, "check-contracts.exs")
    elixir = System.find_executable("elixir")
    File.write!(file, "defmodule Complete do\n@spec call() :: :ok\ndef call, do: :ok\nend")
    assert {output, 0} = System.cmd(elixir, [script, file], env: [{"ERL_FLAGS", "+S 2:2"}])
    assert output =~ "covered: 1; missing: 0"
    File.write!(file, "defmodule Complete do\ndef call, do: :ok\nend")
    assert {output, 1} = System.cmd(elixir, [script, file], env: [{"ERL_FLAGS", "+S 2:2"}])
    assert output =~ "MISSING"
    assert {_output, 1} = System.cmd(elixir, [script], cd: dir, env: [{"ERL_FLAGS", "+S 2:2"}])

    assert {_output, 2} =
             System.cmd(elixir, [script, "--exceptions", "stale.json"],
               stderr_to_stdout: true,
               env: [{"ERL_FLAGS", "+S 2:2"}]
             )
  end

  test "unquote composition returns to its parent and cannot borrow an outer template spec" do
    report =
      scan("""
      @spec make() :: Macro.t()
      def make do
        quote do
          @spec call() :: :ok
          unquote(quote do
            def call, do: :ok
          end)
        end
      end
      """)

    assert [%{name: :call, scope: {"Example", [_]}}] = Contracts.missing(report)
    assert length(report.boundaries) == 1
  end

  test "bind_quoted and disabled unquoting do not escape the template" do
    for opts <- ["unquote: false", "bind_quoted: [value: :ok]"] do
      report =
        scan("""
        @spec make() :: Macro.t()
        def make do
          quote #{opts} do
            unquote(quote do
              def call, do: :ok
            end)
          end
        end
        """)

      assert [%{scope: {"Example", [_, _]}}] = Contracts.missing(report)
      assert report.boundaries == []
    end
  end

  test "default expressions containing templates are scanned too" do
    report =
      scan(~S"""
      @spec make(Macro.t()) :: Macro.t()
      def make(value \\ quote(do: (def call, do: :ok))), do: value
      """)

    assert [%{name: :call}] = Contracts.missing(report)
  end

  test "qualified Kernel definitions have ordinary obligations" do
    report = scan("@spec call() :: :ok\nKernel.def call, do: :ok\nKernel.defp missing, do: :ok")
    assert [%{name: :missing, kind: :defp}] = Contracts.missing(report)
    assert length(report.functions) == 2
    assert scan("Custom.def call, do: :ok").errors != []
  end

  test "grouped aliases used for module ownership resolve without expansion" do
    report =
      scan("""
      alias Elixir.Group.{One, Two}
      defmodule One do
        @spec call() :: :ok
        def call, do: :ok
      end
      defmodule Two do
        def call, do: :ok
      end
      """)

    assert [%{scope: {"Group.Two", []}}] = Contracts.missing(report)
    assert Enum.any?(report.functions, &(&1.scope == {"Group.One", []}))
  end

  test "compiler evidence confirms source arity contracts and generated wrapper exclusions" do
    # Only this fixed, trusted fixture is compiled. The scanner never compiles
    # its inputs. No umbrella applications or framework dependencies are loaded.
    source = ~S"""
    defmodule ContractsCompiledFixture do
      @spec call(integer()) :: integer()
      def call(x \\ 0), do: x
      @spec build(Macro.t()) :: Macro.t()
      defmacro build(ast), do: ast
      @spec __using__(Macro.t()) :: Macro.t()
      defmacro __using__(_) do
        quote do
          @spec generated() :: :ok
          def generated, do: :ok
        end
      end
      defmodule Child do
        @spec call() :: :ok
        def call, do: :ok
      end
    end
    defmodule ContractsUsingFixture do
      use ContractsCompiledFixture
    end
    """

    report = Contracts.scan_source(source)
    assert Contracts.status(report) == 0
    assert length(report.functions) == 5
    compiled = Code.compile_string(source)

    on_exit(fn ->
      for {module, _} <- compiled do
        :code.purge(module)
        :code.delete(module)
      end
    end)

    {fixture, _beam} = List.keyfind(compiled, ContractsCompiledFixture, 0)
    {using_fixture, _beam} = List.keyfind(compiled, ContractsUsingFixture, 0)
    assert [{:call, 0}, {:call, 1}] = fixture.__info__(:functions)
    assert [{:__using__, 1}, {:build, 1}] = fixture.__info__(:macros)
    assert [generated: 0] = using_fixture.__info__(:functions)

    assert {:ok, specs} =
             Code.Typespec.fetch_specs(Keyword.fetch!(compiled, ContractsCompiledFixture))

    assert List.keymember?(specs, {:call, 1}, 0)
    assert List.keymember?(specs, {:"MACRO-build", 2}, 0)
  end

  test "checker implementation itself has complete public and private coverage" do
    report =
      Contracts.scan([
        Path.join(__DIR__, "contracts.exs"),
        Path.join(__DIR__, "check-contracts.exs")
      ])

    assert report.errors == []
    assert Contracts.missing(report) == []
    assert Contracts.status(report) == 0
  end

  @spec temporary_directory() :: String.t()
  defp temporary_directory do
    path = Path.join(System.tmp_dir!(), "beamlet-contracts-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
