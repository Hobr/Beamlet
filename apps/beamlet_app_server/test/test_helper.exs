postgres? = is_binary(System.get_env("BEAMLET_PG_SOCKET_DIR"))

# The two-phase end-to-end script runs its phases as separate OS processes and
# supplies their shared directory; an ordinary run uses the single-process test.
e2e? = is_binary(System.get_env("DURABLE_E2E_DIR"))

ExUnit.start(
  exclude:
    [:distributed] ++
      if(postgres?, do: [], else: [:postgres_db]) ++
      if(e2e?, do: [], else: [:durable_e2e_phase1, :durable_e2e_phase2])
)
