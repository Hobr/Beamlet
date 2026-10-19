import Config

# 测试不监听端口：连接测试用 Plug 直接构造 conn，`server: false` 下
# 端口值不会被占用。测试用固定的 secret 仅用于本环境。
# We don't run a server during test. If one is required,
# you can enable the server option below.
config :beamlet_app_web, Beamlet.Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "MG/AaNbP9nPoGDGCumwENJKa/K9e8iWAkN/IigvpvzkMMTgKyajj1sY8vAYj/34l",
  server: false
