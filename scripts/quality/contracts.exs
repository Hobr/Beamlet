defmodule Beamlet.Quality.Contracts do
  @moduledoc """
  只做解析、不展开宏也不求值源码的契约清单工具。它只证明声明是否存在，
  不判断 typespec 本身是否合理；编译、Dialyzer 与人工审阅仍然是必需的。
  没有应用/模块豁免机制，动态定义无法归属时会判为失败。

  Parse-only source contract inventory. Never expands macros or evaluates source.

  Run `elixir scripts/quality/check-contracts.exs [--inventory] [PATH ...]`.
  With no paths, checks every `apps/*/lib/**/*.ex`. Exit 1 means missing contracts
  or unclassifiable syntax; exit 2 means invalid CLI usage. No exemptions exist.
  `--inventory` prints every identity, declaration, and generation boundary.
  This checks declaration presence, not typespec validity or semantic accuracy;
  compilation, Dialyzer and human review remain mandatory.
  """

  @type kind :: :def | :defp | :defdelegate | :defmacro | :defmacrop
  @type location :: %{file: String.t(), line: non_neg_integer(), column: non_neg_integer()}
  @type scope :: {String.t() | nil, [String.t()]}
  @type signature :: {atom(), non_neg_integer()}
  @type identity :: {String.t(), scope(), atom(), non_neg_integer(), kind()}
  @typep context :: %{
           location: location(),
           scope: scope(),
           aliases: %{optional(String.t()) => String.t()},
           in_function: boolean(),
           dynamic: boolean(),
           quote_parents: [context()],
           unquote?: boolean()
         }
  @typep event ::
           {:definition, location(), scope(), kind(), signature(), non_neg_integer(), boolean()}
           | {:contract, location(), scope(), :spec | :callback | :macrocallback, signature()}
           | {:boundary, location(), scope(), String.t()}
           | {:behaviour, location(), scope(), String.t()}
           | {:impl, location(), scope(), String.t()}
           | {:module, location(), scope()}
           | {:error, location(), String.t()}
  @type function_entry :: %{
          id: identity(),
          location: location(),
          scope: scope(),
          kind: kind(),
          name: atom(),
          arity: non_neg_integer(),
          clauses: non_neg_integer(),
          heads: non_neg_integer(),
          lines: [non_neg_integer()],
          defaults: non_neg_integer(),
          specs: non_neg_integer(),
          impl: [String.t()],
          behaviours: [String.t()],
          callbacks: [String.t()]
        }
  @type declaration :: %{
          location: location(),
          scope: scope(),
          kind: :spec | :callback | :macrocallback,
          signature: signature()
        }
  @type module_entry :: %{location: location(), scope: scope()}
  @type boundary :: %{location: location(), scope: scope(), source: String.t()}
  @type diagnostic :: %{location: location(), message: String.t()}
  @type report :: %{
          files: [String.t()],
          modules: [module_entry()],
          functions: [function_entry()],
          declarations: [declaration()],
          boundaries: [boundary()],
          errors: [diagnostic()]
        }
  @typep collection :: %{
           modules: [module_entry()],
           functions: %{optional(identity()) => function_entry()},
           declarations: [declaration()],
           boundaries: [boundary()],
           errors: [diagnostic()],
           behaviours: %{optional(scope()) => [String.t()]},
           pending_impl: %{optional(scope()) => String.t()}
         }

  @spec scan([String.t()]) :: report()
  def scan(paths) do
    paths = Enum.uniq(paths)

    events =
      Enum.flat_map(paths, fn path ->
        case File.read(path) do
          {:ok, source} -> parse(source, path)
          {:error, reason} -> [{:error, loc(path), "cannot read: #{inspect(reason)}"}]
        end
      end)

    collect(events, paths)
  end

  @spec scan_source(String.t(), String.t()) :: report()
  def scan_source(source, path \\ "fixture.ex"), do: collect(parse(source, path), [path])

  @spec missing(report()) :: [function_entry()]
  def missing(report), do: Enum.filter(report.functions, &(&1.specs == 0))

  @spec status(report()) :: 0 | 1
  def status(report), do: if(report.errors == [] and missing(report) == [], do: 0, else: 1)

  @spec label(scope()) :: String.t()
  def label({module, templates}) do
    Enum.join([module || "<no module>" | templates], " / ")
  end

  @spec render(report(), boolean()) :: String.t()
  def render(report, inventory \\ false) do
    summary = [
      "Files: #{length(report.files)}; functions: #{length(report.functions)}; " <>
        "covered: #{length(report.functions) - length(missing(report))}; " <>
        "missing: #{length(missing(report))}; errors: #{length(report.errors)}"
    ]

    groups =
      report.functions
      |> Enum.group_by(fn f -> {app(f.location.file), f.kind, elem(f.scope, 1) != []} end)
      |> Enum.sort()
      |> Enum.map(fn {{app, kind, template}, functions} ->
        "#{app} #{kind}#{if template, do: " template", else: ""}: " <>
          "#{Enum.count(functions, &(&1.specs > 0))}/#{length(functions)} covered"
      end)

    functions =
      if(inventory, do: report.functions, else: missing(report))
      |> Enum.map(&render_function/1)

    errors = Enum.map(report.errors, &"ERROR #{position(&1.location)} #{&1.message}")
    details = if inventory, do: render_details(report), else: []
    Enum.join(summary ++ groups ++ functions ++ errors ++ details, "\n") <> "\n"
  end

  @spec main([String.t()]) :: 0 | 1 | 2
  def main(args) do
    {options, paths, invalid} = OptionParser.parse(args, strict: [inventory: :boolean])

    if invalid != [] do
      IO.puts(:stderr, "Invalid options: #{inspect(invalid)}; no exemptions are supported")
      2
    else
      paths = if paths == [], do: Path.wildcard("apps/*/lib/**/*.ex"), else: paths
      report = scan(paths)

      report =
        if paths == [],
          do: %{report | errors: [%{location: loc("apps"), message: "no source files"}]},
          else: report

      IO.write(render(report, Keyword.get(options, :inventory, false)))
      status(report)
    end
  end

  @spec parse(String.t(), String.t()) :: [event()]
  defp parse(source, file) do
    case Code.string_to_quoted(source, columns: true, file: file) do
      {:ok, ast} ->
        context = %{
          location: loc(file),
          scope: {nil, []},
          aliases: %{},
          in_function: false,
          dynamic: false,
          quote_parents: [],
          unquote?: true
        }

        walk(ast, context)

      {:error, {meta, error, token}} ->
        [
          {:error,
           %{
             loc(file)
             | line: Keyword.get(meta, :line, 0),
               column: Keyword.get(meta, :column, 0)
           }, "parse error: #{IO.iodata_to_binary(error)}#{token}"}
        ]
    end
  end

  @spec walk(Macro.t(), context()) :: [event()]
  defp walk({:__block__, _, nodes}, ctx), do: sequence(nodes, ctx)

  defp walk({:defmodule, meta, [name, [do: body]]}, ctx) do
    case module_name(name, ctx, true) do
      nil ->
        [error(meta, ctx, "dynamic module name requires explicit scanner support")]

      module ->
        scope = {module, elem(ctx.scope, 1)}
        [{:module, at(meta, ctx), scope} | walk(body, %{ctx | scope: scope, in_function: false})]
    end
  end

  defp walk({:quote, meta, args}, ctx) do
    marker = "quote@#{meta[:line]}:#{meta[:column]}"
    options = args |> Enum.filter(&is_list/1) |> List.flatten()
    unquote? = Keyword.get(options, :unquote, not Keyword.has_key?(options, :bind_quoted))

    quoted = %{
      ctx
      | scope: {elem(ctx.scope, 0), elem(ctx.scope, 1) ++ [marker]},
        in_function: false,
        quote_parents: [ctx | ctx.quote_parents],
        unquote?: unquote?
    }

    if unquote? in [true, false] do
      walk_quote(args, ctx, quoted)
    else
      [error(meta, ctx, "dynamic quote unquote option requires explicit scanner support")]
    end
  end

  defp walk({kind, meta, args}, %{unquote?: true, quote_parents: [parent | _]} = ctx)
       when kind in [:unquote, :unquote_splicing] do
    [{:boundary, at(meta, ctx), ctx.scope, "#{kind} (composition evaluated in parent scope)"}] ++
      walk(args, parent)
  end

  defp walk({{{:., _, [_module, :unquote]}, _, _name}, meta, _args}, ctx) do
    [error(meta, ctx, "dynamic qualified macro dispatch requires explicit scanner support")]
  end

  defp walk({{:unquote, _, _name}, meta, _args}, ctx) do
    [error(meta, ctx, "dynamic macro dispatch requires explicit scanner support")]
  end

  defp walk({{:., _, [module, kind]}, meta, args}, ctx)
       when kind in [:def, :defp, :defdelegate, :defmacro, :defmacrop, :defmodule] do
    if module_name(module, ctx, false) == "Kernel" do
      walk({kind, meta, args}, ctx)
    else
      [error(meta, ctx, "qualified definition-like macro requires explicit scanner support")]
    end
  end

  defp walk({kind, meta, [head | rest]}, ctx)
       when kind in [:def, :defp, :defdelegate, :defmacro, :defmacrop] do
    # 函数头可能带 guard；只取真实定义身份（名/元数/默认值个数），
    # guard 内的调用不算定义。设错静态模块或出现在函数体/动态生成里则报错。
    case signature(head) do
      {:ok, name, arity, defaults} ->
        issues =
          if elem(ctx.scope, 0) == nil or ctx.in_function or ctx.dynamic,
            do: [
              error(
                meta,
                ctx,
                "definition has no static module-level owner: #{kind} #{name}/#{arity}"
              )
            ],
            else: []

        head_only = rest == []

        [
          {:definition, at(meta, ctx), ctx.scope, kind, {name, arity}, defaults, head_only}
          | issues
        ] ++
          walk_head(head, %{ctx | in_function: true}) ++
          Enum.flat_map(rest, &walk(&1, %{ctx | in_function: true}))

      :error ->
        [error(meta, ctx, "dynamic or unsupported #{kind} head: #{Macro.to_string(head)}")]
    end
  end

  defp walk({:@, meta, [{kind, _, [value]}]}, ctx)
       when kind in [:spec, :callback, :macrocallback] do
    case contract_signature(value) do
      {:ok, name, arity, _} ->
        issues =
          if ctx.in_function or elem(ctx.scope, 0) == nil,
            do: [error(meta, ctx, "@#{kind} has no static module-level owner")],
            else: []

        [{:contract, at(meta, ctx), ctx.scope, kind, {name, arity}} | issues]

      :error ->
        [error(meta, ctx, "dynamic or unsupported @#{kind}")]
    end
  end

  defp walk({:@, meta, [{:behaviour, _, [value]}]}, ctx) do
    case module_name(value, ctx, false) do
      nil -> [error(meta, ctx, "dynamic behaviour")]
      module -> [{:behaviour, at(meta, ctx), ctx.scope, module}]
    end
  end

  defp walk({:@, meta, [{:impl, _, [value]}]}, ctx),
    do: [{:impl, at(meta, ctx), ctx.scope, Macro.to_string(value)}]

  defp walk({:@, meta, [{kind, _, values}]}, ctx)
       when kind in [:before_compile, :after_compile, :on_definition, :derive] do
    [{:boundary, at(meta, ctx), ctx.scope, "@#{kind} #{Macro.to_string(values)}"}]
  end

  defp walk({kind, meta, args}, ctx)
       when kind in [:use, :defstruct, :defexception, :schema, :embedded_schema, :embed_templates] and
              is_list(args) do
    # Keep the origin concise; the file/line identifies the complete DSL body.
    signature_args = Enum.reject(args, &(is_list(&1) and Keyword.has_key?(&1, :do)))
    origin = Macro.to_string({kind, [], signature_args}) |> String.replace(~r/\s+/, " ")
    [{:boundary, at(meta, ctx), ctx.scope, origin}] ++ walk(args, ctx)
  end

  defp walk({kind, meta, _args}, ctx)
       when kind in [
              :defprotocol,
              :defimpl,
              :defguard,
              :defguardp,
              :defmodule,
              :def,
              :defp,
              :defmacro,
              :defmacrop,
              :defdelegate
            ] do
    [error(meta, ctx, "#{kind} requires explicit scanner support")]
  end

  defp walk({:alias, meta, [{{:., _, [prefix, :{}]}, _, suffixes}]}, ctx) do
    if module_name(prefix, ctx, false) && Enum.all?(suffixes, &module_name(&1, ctx, false)) do
      []
    else
      [error(meta, ctx, "dynamic grouped alias requires explicit scanner support")]
    end
  end

  defp walk({:alias, meta, [name | options]}, ctx) do
    as = options |> List.flatten() |> Keyword.get(:as)

    if module_name(name, ctx, false) && (is_nil(as) || module_name(as, ctx, false)) do
      []
    else
      [error(meta, ctx, "dynamic alias requires explicit scanner support")]
    end
  end

  defp walk({:for, _, args}, ctx), do: walk(args, %{ctx | dynamic: true})

  defp walk({{:., _, [module, name]}, meta, args}, ctx)
       when name in [
              :create,
              :eval_quoted,
              :eval_string,
              :compile_quoted,
              :compile_string,
              :compile_file
            ] do
    if module_name(module, ctx, false) in ["Module", "Code"] do
      [error(meta, ctx, "runtime code generation requires explicit scanner support")] ++
        walk(args, ctx)
    else
      walk(args, ctx)
    end
  end

  defp walk({_form, _meta, args}, ctx) when is_list(args), do: walk(args, ctx)
  defp walk(nodes, ctx) when is_list(nodes), do: sequence(nodes, ctx)
  defp walk(node, ctx) when is_tuple(node), do: node |> Tuple.to_list() |> walk(ctx)
  defp walk(_literal, _ctx), do: []

  @spec walk_quote([Macro.t()], context(), context()) :: [event()]
  defp walk_quote(args, ctx, quoted) do
    # Options (including bind_quoted) execute outside the new template. Only the
    # do body owns definitions/specs in this template; neither scope leaks out.
    Enum.flat_map(args, fn
      options when is_list(options) ->
        Enum.flat_map(options, fn
          {:do, body} -> walk(body, quoted)
          {_key, value} -> walk(value, ctx)
        end)

      other ->
        walk(other, ctx)
    end)
  end

  @spec walk_head(Macro.t(), context()) :: [event()]
  defp walk_head({:when, _, [head | guards]}, ctx), do: walk_head(head, ctx) ++ walk(guards, ctx)
  defp walk_head({_name, _, args}, ctx) when is_list(args), do: walk(args, ctx)
  defp walk_head(_, _ctx), do: []

  @spec sequence([Macro.t()], context()) :: [event()]
  defp sequence(nodes, ctx) do
    {events, _ctx} =
      Enum.map_reduce(nodes, ctx, fn node, current ->
        {walk(node, current), alias_context(node, current)}
      end)

    List.flatten(events)
  end

  @spec alias_context(Macro.t(), context()) :: context()
  defp alias_context({:defmodule, _, [{:__aliases__, _, [short]} = name, _body]}, ctx)
       when is_atom(short) do
    case module_name(name, ctx, true) do
      nil -> ctx
      module -> %{ctx | aliases: Map.put(ctx.aliases, Atom.to_string(short), module)}
    end
  end

  defp alias_context({:alias, _, [{{:., _, [prefix, :{}]}, _, suffixes}]}, ctx) do
    resolved = module_name(prefix, ctx, false)

    Enum.reduce(suffixes, ctx, fn suffix, current ->
      short = module_name(suffix, %{ctx | aliases: %{}}, false)

      if resolved && short do
        %{
          current
          | aliases:
              Map.put(
                current.aliases,
                List.last(String.split(short, ".")),
                resolved <> "." <> short
              )
        }
      else
        current
      end
    end)
  end

  defp alias_context({:alias, _, [name | options]}, ctx) do
    resolved = module_name(name, ctx, false)
    as = options |> List.flatten() |> Keyword.get(:as)

    short =
      if as,
        do: module_name(as, %{ctx | aliases: %{}}, false),
        else: resolved && List.last(String.split(resolved, "."))

    if resolved && short, do: %{ctx | aliases: Map.put(ctx.aliases, short, resolved)}, else: ctx
  end

  defp alias_context(_, ctx), do: ctx

  @spec module_name(Macro.t(), context(), boolean()) :: String.t() | nil
  defp module_name({:__aliases__, _, [{:__MODULE__, _, _} | rest]}, ctx, _),
    do: join_module(elem(ctx.scope, 0), rest)

  defp module_name({:__aliases__, _, [:"Elixir" | parts]}, _ctx, _) when is_list(parts),
    do: if(Enum.all?(parts, &is_atom/1), do: Enum.join(parts, "."))

  defp module_name({:__aliases__, _, [first | rest]}, ctx, nested) when is_atom(first) do
    if Enum.all?(rest, &is_atom/1) do
      resolve_alias(first, rest, ctx, nested)
    end
  end

  defp module_name({:__MODULE__, _, _}, ctx, _), do: elem(ctx.scope, 0)

  defp module_name(name, _ctx, _) when is_atom(name) and not is_nil(name),
    do: name |> Atom.to_string() |> String.trim_leading("Elixir.")

  defp module_name(_, _, _), do: nil

  @spec resolve_alias(atom(), [atom()], context(), boolean()) :: String.t()
  defp resolve_alias(first, rest, ctx, nested) do
    case Map.get(ctx.aliases, Atom.to_string(first)) do
      nil ->
        name = Enum.join([first | rest], ".")
        if nested, do: join_module(elem(ctx.scope, 0), [name]), else: name

      prefix ->
        join_module(prefix, rest)
    end
  end

  @spec join_module(String.t() | nil, [atom() | String.t()]) :: String.t()
  defp join_module(nil, parts), do: Enum.join(parts, ".")
  defp join_module(parent, parts), do: Enum.join([parent | parts], ".")

  @spec signature(Macro.t()) :: {:ok, atom(), non_neg_integer(), non_neg_integer()} | :error
  defp signature({:when, _, [head | _]}), do: signature(head)

  defp signature({name, _, args})
       when is_atom(name) and name not in [:unquote, :unquote_splicing] and is_list(args) do
    if Enum.any?(args, &match?({:unquote_splicing, _, _}, &1)) do
      :error
    else
      {:ok, name, length(args), Enum.count(args, &match?({:\\, _, _}, &1))}
    end
  end

  defp signature({name, _, context}) when is_atom(name) and is_atom(context),
    do: {:ok, name, 0, 0}

  defp signature(_), do: :error

  @spec contract_signature(Macro.t()) ::
          {:ok, atom(), non_neg_integer(), non_neg_integer()} | :error
  defp contract_signature({:when, _, [contract | _]}), do: contract_signature(contract)
  defp contract_signature({:"::", _, [head, _return]}), do: signature(head)
  defp contract_signature(_), do: :error

  @spec collect([event()], [String.t()]) :: report()
  defp collect(events, paths) do
    initial = %{
      modules: [],
      functions: %{},
      declarations: [],
      boundaries: [],
      errors: [],
      behaviours: %{},
      pending_impl: %{}
    }

    collected = Enum.reduce(events, initial, &collect_event/2)

    functions =
      collected.functions
      |> Map.values()
      |> Enum.map(&decorate(&1, collected))
      |> Enum.sort_by(& &1.id)

    %{
      files: paths,
      modules: Enum.reverse(collected.modules),
      functions: functions,
      declarations: Enum.reverse(collected.declarations),
      boundaries: Enum.reverse(collected.boundaries),
      errors: Enum.reverse(collected.errors)
    }
  end

  @spec collect_event(event(), collection()) :: collection()
  defp collect_event({:module, loc, scope}, state),
    do: %{state | modules: [%{location: loc, scope: scope} | state.modules]}

  defp collect_event({:definition, loc, scope, kind, {name, arity}, defaults, head?}, state) do
    id = {loc.file, scope, name, arity, kind}
    impl = Map.get(state.pending_impl, scope)

    entry =
      Map.get(state.functions, id, %{
        id: id,
        location: loc,
        scope: scope,
        kind: kind,
        name: name,
        arity: arity,
        clauses: 0,
        heads: 0,
        lines: [],
        defaults: 0,
        specs: 0,
        impl: [],
        behaviours: [],
        callbacks: []
      })

    entry = %{
      entry
      | clauses: entry.clauses + if(head?, do: 0, else: 1),
        heads: entry.heads + if(head?, do: 1, else: 0),
        lines: entry.lines ++ [loc.line],
        defaults: max(entry.defaults, defaults),
        impl: Enum.uniq(entry.impl ++ if(impl, do: [impl], else: []))
    }

    %{
      state
      | functions: Map.put(state.functions, id, entry),
        pending_impl: Map.delete(state.pending_impl, scope)
    }
  end

  defp collect_event({:contract, loc, scope, kind, signature}, state),
    do: %{
      state
      | declarations: [
          %{location: loc, scope: scope, kind: kind, signature: signature} | state.declarations
        ]
    }

  defp collect_event({:boundary, loc, scope, source}, state),
    do: %{state | boundaries: [%{location: loc, scope: scope, source: source} | state.boundaries]}

  defp collect_event({:error, loc, message}, state),
    do: %{state | errors: [%{location: loc, message: message} | state.errors]}

  defp collect_event({:behaviour, _loc, scope, module}, state),
    do: %{state | behaviours: Map.update(state.behaviours, scope, [module], &[module | &1])}

  defp collect_event({:impl, _loc, scope, value}, state),
    do: %{state | pending_impl: Map.put(state.pending_impl, scope, value)}

  @spec decorate(function_entry(), collection()) :: function_entry()
  defp decorate(f, state) do
    signature = {f.name, f.arity}

    specs =
      Enum.count(
        state.declarations,
        &(&1.kind == :spec and &1.scope == f.scope and &1.location.file == f.location.file and
            &1.signature == signature)
      )

    behaviours = Map.get(state.behaviours, f.scope, []) |> Enum.uniq() |> Enum.sort()

    callbacks =
      for d <- state.declarations,
          d.kind in [:callback, :macrocallback],
          d.signature == signature,
          elem(d.scope, 0) in behaviours,
          do: elem(d.scope, 0)

    %{f | specs: specs, behaviours: behaviours, callbacks: Enum.uniq(callbacks)}
  end

  @spec loc(String.t()) :: location()
  defp loc(file), do: %{file: file, line: 0, column: 0}
  @spec at(keyword(), context()) :: location()
  defp at(meta, ctx),
    do: %{ctx.location | line: Keyword.get(meta, :line, 0), column: Keyword.get(meta, :column, 0)}

  @spec error(keyword(), context(), String.t()) :: event()
  defp error(meta, ctx, message), do: {:error, at(meta, ctx), message}
  @spec position(location()) :: String.t()
  defp position(loc), do: "#{loc.file}:#{loc.line}:#{loc.column}"
  @spec app(String.t()) :: String.t()
  defp app(path) do
    case Path.split(path) do
      ["apps", app | _] -> app
      _ -> "explicit paths"
    end
  end

  @spec render_function(function_entry()) :: String.t()
  defp render_function(f) do
    "#{if f.specs == 0, do: "MISSING", else: "COVERED"} #{position(f.location)} " <>
      "#{label(f.scope)} #{f.kind} #{f.name}/#{f.arity} " <>
      "clauses=#{f.clauses} heads=#{f.heads} defaults=#{f.defaults} " <>
      "lines=#{Enum.join(f.lines, ",")} specs=#{f.specs} " <>
      "impl=#{inspect(f.impl)} behaviours=#{inspect(f.behaviours)} callbacks=#{inspect(f.callbacks)}"
  end

  @spec render_details(report()) :: [String.t()]
  defp render_details(report) do
    Enum.map(report.modules, &"MODULE #{position(&1.location)} #{label(&1.scope)}") ++
      Enum.map(report.declarations, fn d ->
        {name, arity} = d.signature
        "DECLARATION #{position(d.location)} #{label(d.scope)} @#{d.kind} #{name}/#{arity}"
      end) ++
      Enum.map(
        report.boundaries,
        &"BOUNDARY #{position(&1.location)} #{label(&1.scope)} #{&1.source}"
      )
  end
end
