import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :beamlet_web, BeamletWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "4/spxVQ9dha50J0o/Jl5Ty2XVemTqKAqeNdeZh+zQ590acld7QpUxGypU+qMg/wu",
  server: false
