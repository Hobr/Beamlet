import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :beamlet_web, Beamlet.Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "MG/AaNbP9nPoGDGCumwENJKa/K9e8iWAkN/IigvpvzkMMTgKyajj1sY8vAYj/34l",
  server: false
