# Differential corpus test: does the reference parser (`Tptp`) accept the same files
# as the tree-sitter and Lezer parsers? See README.md.
#
#     cd gen && mix run ../tools/differential/differential.exs [--sample N] [--max-size BYTES] [--jobs N]
#
# Exits non-zero when a file is accepted by some parsers and rejected by others, unless
# allowlist.txt lists it with a reason.

defmodule Differential do
  @here Path.expand(".", __DIR__)
  @root Path.expand("../..", __DIR__)

  def main(argv) do
    {opts, _} =
      OptionParser.parse!(argv,
        strict: [sample: :integer, max_size: :integer, report: :string, tptp: :string, jobs: :integer]
      )

    tptp = opts[:tptp] || System.get_env("TPTP") || "/opt/TPTP"
    sample = opts[:sample] || 1
    max_size = opts[:max_size] || 5_000_000
    report = opts[:report] || Path.join(@root, "gen/_build/differential.tsv")
    jobs = opts[:jobs] || System.schedulers_online()

    files = files(tptp, sample, max_size)
    IO.puts("#{length(files)} files from #{tptp} (1 in #{sample}, up to #{max_size} bytes), #{jobs} jobs")

    lists = write_lists(files, jobs)

    reference = timed("Tptp", fn -> reference_rejects(files) end)
    tree_sitter_lib = build_tree_sitter()
    tree_sitter = timed("tree-sitter", fn -> in_parallel(lists, &tree_sitter_rejects(&1, tree_sitter_lib)) end)
    lezer = timed("Lezer", fn -> in_parallel(lists, &lezer_rejects/1) end)
    Enum.each([tree_sitter_lib | lists], &File.rm/1)

    allowed = allowlist()

    rows =
      for file <- files do
        verdicts = Enum.map([reference, tree_sitter, lezer], &if(MapSet.member?(&1, file), do: "reject", else: "accept"))
        {file, verdicts}
      end

    File.mkdir_p!(Path.dirname(report))

    File.write!(
      report,
      ["file\tTptp\ttree-sitter\tLezer\n" | Enum.map(rows, fn {f, v} -> Enum.join([f | v], "\t") <> "\n" end)]
    )

    disagreements = for {file, v} <- rows, length(Enum.uniq(v)) > 1, do: {file, v}
    {known, unknown} = Enum.split_with(disagreements, fn {file, _} -> Map.has_key?(allowed, relative(file, tptp)) end)

    IO.puts("report: #{report}")
    IO.puts("rejected by Tptp: #{MapSet.size(reference)}, tree-sitter: #{MapSet.size(tree_sitter)}, Lezer: #{MapSet.size(lezer)}")
    IO.puts("disagreements: #{length(disagreements)} (#{length(known)} allow-listed)")

    for {file, [r, t, l]} <- unknown do
      IO.puts("  #{relative(file, tptp)}: Tptp #{r}, tree-sitter #{t}, Lezer #{l}")
    end

    if unknown != [], do: System.halt(1)
  end

  defp files(tptp, sample, max_size) do
    ["Problems/**/*.p", "Axioms/**/*.ax", "Solutions/**/*.s"]
    |> Enum.flat_map(&Path.wildcard(Path.join(tptp, &1)))
    |> Enum.sort()
    |> Enum.take_every(sample)
    |> Enum.filter(&(File.stat!(&1).size <= max_size))
  end

  # One file list per job. Files are dealt out largest first, so the multi-megabyte
  # problems (which take the external parsers seconds each) are spread evenly.
  defp write_lists(files, jobs) do
    stamp = System.unique_integer([:positive])

    files
    |> Enum.sort_by(&(-File.stat!(&1).size))
    |> Enum.with_index()
    |> Enum.group_by(fn {_file, i} -> rem(i, jobs) end, fn {file, _i} -> file end)
    |> Enum.map(fn {job, chunk} ->
      list = Path.join(System.tmp_dir!(), "lang-tptp-differential-#{stamp}-#{job}.txt")
      File.write!(list, Enum.join(chunk, "\n") <> "\n")
      list
    end)
  end

  # Runs one external parser per list concurrently and merges the rejected files.
  defp in_parallel(lists, rejects) do
    lists
    |> Task.async_stream(rejects, timeout: :infinity, max_concurrency: length(lists))
    |> Enum.reduce(MapSet.new(), fn {:ok, rejected}, acc -> MapSet.union(acc, rejected) end)
  end

  defp reference_rejects(files) do
    files
    |> Task.async_stream(
      fn file ->
        {:ok, _file, diagnostics} = Tptp.from_string(File.read!(file))
        {file, Enum.any?(diagnostics, &(&1.severity == :error))}
      end,
      timeout: :infinity,
      ordered: false
    )
    |> Enum.flat_map(fn {:ok, {file, rejected}} -> if rejected, do: [file], else: [] end)
    |> MapSet.new()
  end

  # Compiles the parser once, so the parallel `tree-sitter parse` jobs do not each compile
  # it into the same cache path at the same time.
  defp build_tree_sitter do
    lib = Path.join(System.tmp_dir!(), "lang-tptp-differential-#{System.unique_integer([:positive])}.so")

    case System.cmd("tree-sitter", ["build", "--output", lib],
           cd: Path.join(@root, "packages/tree-sitter-tptp"),
           stderr_to_stdout: true
         ) do
      {_, 0} -> lib
      {out, status} -> raise "tree-sitter build exited with #{status}:\n#{out}"
    end
  end

  # `tree-sitter parse --quiet` prints one line per file whose tree has ERROR or MISSING.
  # It exits 1 on any such file, so the status cannot tell a finished run from an aborted
  # one; the `--stat` summary's parse count can.
  defp tree_sitter_rejects(list, lib) do
    {out, status} =
      System.cmd("tree-sitter", ["parse", "--quiet", "--stat", "--lib-path", lib, "--lang-name", "tptp", "--paths", list],
        cd: Path.join(@root, "packages/tree-sitter-tptp"),
        stderr_to_stdout: true
      )

    lines = String.split(out, "\n")
    expected = list |> File.read!() |> String.split("\n", trim: true) |> length()
    parsed =
      case Regex.run(~r/^Total parses: (\d+);/m, out) do
        [_, n] -> String.to_integer(n)
        nil -> 0
      end

    if parsed != expected,
      do: raise("tree-sitter parsed #{parsed} of #{expected} files in #{list} (exit #{status}):\n#{out}")

    for line <- lines,
        line =~ ~r/\((ERROR|MISSING)/,
        [path | _] = String.split(line, "\t"),
        into: MapSet.new(),
        do: String.trim(path)
  end

  defp lezer_rejects(list) do
    case System.cmd("node", [Path.join(@here, "lezer.mjs"), list], stderr_to_stdout: true) do
      {out, 0} -> out |> String.split("\n", trim: true) |> MapSet.new()
      {out, status} -> raise "lezer.mjs exited with #{status}:\n#{out}"
    end
  end

  # allowlist.txt: `relative/path<TAB>reason`, `#` comments.
  defp allowlist do
    Path.join(@here, "allowlist.txt")
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Map.new(fn line ->
      case String.split(line, "\t", parts: 2) do
        [path, reason] when reason != "" -> {path, reason}
        _ -> raise "allowlist.txt: every entry needs a path, a tab and a reason: #{inspect(line)}"
      end
    end)
  end

  defp relative(file, tptp), do: Path.relative_to(file, tptp)

  defp timed(label, fun) do
    {micros, result} = :timer.tc(fun)
    IO.puts("#{label}: #{div(micros, 1000)} ms")
    result
  end
end

Differential.main(System.argv())
