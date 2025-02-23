alias Instream.Admin.Database
alias Instream.TestHelpers.Connections

# grab ALL helpers and start connections
File.ls!("test/helpers/connections")
|> Enum.filter(&String.contains?(&1, "connection"))
|> Enum.reject(&(&1 == "init_connection.ex"))
|> Enum.map(fn helper ->
  conn =
    helper
    |> String.replace(".ex", "")
    |> String.replace("udp", "UDP")
    |> Macro.camelize()

  Module.concat(Connections, conn)
end)
|> Supervisor.start_link(strategy: :one_for_one)

# setup test database
_ = "test_database" |> Database.drop() |> Connections.DefaultConnection.execute()
_ = "test_database" |> Database.create() |> Connections.DefaultConnection.execute()

# start up inets fake influxdb server
root = String.to_charlist(__DIR__)

httpd_config = [
  document_root: root,
  modules: [Instream.TestHelpers.Inets.Handler],
  port: 0,
  server_name: 'instream_testhelpers_inets_handler',
  server_root: root
]

{:ok, httpd_pid} = :inets.start(:httpd, httpd_config)

inets_env =
  :instream
  |> Application.get_env(Connections.InetsConnection)
  |> Keyword.put(:port, :httpd.info(httpd_pid)[:port])

Application.put_env(:instream, Connections.InetsConnection, inets_env)

# configure InfluxDB test exclusion
config = ExUnit.configuration()
version = to_string(Connections.DefaultConnection.version())

config =
  case Version.parse(version) do
    :error ->
      config

    {:ok, version} ->
      versions = ["1.4", "1.5", "1.6", "1.7"]
      config = Keyword.put(config, :exclude, config[:exclude] || [])

      Enum.reduce(versions, config, fn ver, acc ->
        case Version.match?(version, "~> #{ver}") do
          true -> acc
          false -> Keyword.put(acc, :exclude, [{:influxdb_version, ver} | acc[:exclude]])
        end
      end)
  end

IO.puts("Running tests for InfluxDB version: #{version}")

# configure OTP test exclusion
release = System.otp_release()
{:ok, version} = Version.parse("#{release}.0.0")
versions = ["19.0", "20.0"]

config =
  Enum.reduce(versions, config, fn ver, acc ->
    case Version.match?(version, ">= #{ver}.0") do
      true -> acc
      false -> Keyword.put(acc, :exclude, [{:otp_release, ver} | acc[:exclude]])
    end
  end)

IO.puts("Running tests for OTP release: #{release}")

# start ExUnit
ExUnit.start(config)
