# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Kite4rent.Repo.insert!(%Kite4rent.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# Only run seeds in development environment
if Mix.env() == :dev do
  alias Kite4rent.Repo
  alias Kite4rent.Rental.Gear
  alias Kite4rent.Users.User

  Repo.insert(%User{
    name: "Facundo",
    email: "user@example.com",
    whatsapp: "34600000000",
    kite_gear: [
      %Gear{
        type: "kite",
        size: "139x42",
        year: "2021",
        model: "Master",
        brand: "Eleveight"
      },
      %Gear{
        type: "twintip",
        size: "135x49",
        year: "2017",
        model: "Spectrum",
        brand: "Cabrinha"
      }
    ]
  })
end
