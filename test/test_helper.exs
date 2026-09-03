Application.put_env(:ecto_auth, EctoAuth.TestRepo, [])
{:ok, _pid} = EctoAuth.TestRepo.start_link()

ExUnit.start()
