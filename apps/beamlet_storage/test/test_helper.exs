# The dual-adapter contract needs an isolated PostgreSQL cluster. It is excluded by
# default so the ordinary suite has no external service requirement, and it is never
# silently reported as passing: the exclusion is printed and the explicit run is
# recorded in the stage-A evidence. Setting BEAMLET_PG_SOCKET_DIR opts in; a missing
# cluster then fails loudly instead of skipping.
postgres? = is_binary(System.get_env("BEAMLET_PG_SOCKET_DIR"))

unless postgres? do
  IO.puts(
    "storage: excluding :postgres_db (set BEAMLET_PG_SOCKET_DIR/BEAMLET_PG_PORT " <>
      "to run the dual-adapter contract)"
  )
end

ExUnit.start(exclude: if(postgres?, do: [], else: [:postgres_db]))
